import AppKit
import UniformTypeIdentifiers

let clipboardShelfImageDirectory: URL = {
    let base = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base.appendingPathComponent("ShelfBar/ClipboardImages", isDirectory: true)
}()

enum ClipboardShelfItemType: String, Codable {
    case text
    case url
    case image
    case file
}

struct ClipboardShelfItem: Codable, Equatable {
    let id: UUID
    var type: ClipboardShelfItemType
    var title: String
    var copiedAt: Date
    var text: String?
    var urlString: String?
    var fileURLString: String?
    var imageFilename: String?
    var pinned: Bool

    var stableKey: String {
        switch type {
        case .text:
            "text:\(Self.canonicalText(text))"
        case .url:
            "url:\(Self.canonicalURL(urlString))"
        case .file:
            "file:\(Self.canonicalFileURL(fileURLString))"
        case .image:
            "image:\(Self.canonicalImage(filename: imageFilename) ?? imageFilename ?? title)"
        }
    }

    var displayImage: NSImage {
        switch type {
        case .text:
            return NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: title) ?? NSImage()
        case .url:
            return NSImage(systemSymbolName: "link", accessibilityDescription: title) ?? NSImage()
        case .file:
            if let fileURLString, let url = URL(string: fileURLString), url.isFileURL {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return NSImage(systemSymbolName: "doc", accessibilityDescription: title) ?? NSImage()
        case .image:
            if let imageFilename,
               let image = NSImage(contentsOf: clipboardShelfImageDirectory.appendingPathComponent(imageFilename)) {
                image.size = NSSize(width: 24, height: 24)
                return image
            }
            return NSImage(systemSymbolName: "photo", accessibilityDescription: title) ?? NSImage()
        }
    }

    static func canonicalText(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalURL(_ value: String?) -> String {
        guard let value,
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return canonicalText(value) }
        return url.absoluteString
    }

    static func canonicalFileURL(_ value: String?) -> String {
        guard let value,
              let url = URL(string: value),
              url.isFileURL
        else { return canonicalText(value) }
        return url.standardizedFileURL.path
    }

    static func canonicalImage(filename: String?) -> String? {
        guard let filename,
              let data = try? Data(contentsOf: clipboardShelfImageDirectory.appendingPathComponent(filename))
        else { return nil }
        return "\(data.count):\(fnv1a64Hex(data))"
    }

    static func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

@MainActor
final class ClipboardStore {
    private static let storageKey = "ShelfBar.clipboard.items.v1"
    static let imageDirectory = clipboardShelfImageDirectory

    private let defaults: UserDefaults
    private let settings: AppSettingsStore
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var isWritingPasteboard = false
    private(set) var items: [ClipboardShelfItem]
    var onChange: (([ClipboardShelfItem]) -> Void)?
    var isMonitoring: Bool { timer != nil }

    init(settings: AppSettingsStore, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ClipboardShelfItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
        enforceLimit()
        if settings.isFeatureEnabled(.clipboardShelf) {
            startMonitoring()
        }
    }

    func settingsDidChange(_ change: AppSettingsStore.Change) {
        switch change {
        case let .feature(feature, enabled) where feature == .clipboardShelf:
            enabled ? startMonitoring() : stopMonitoring()
        case let .general(key) where key == ShelfBarSettingsKey.maxClipboardHistory:
            enforceLimit()
            commit()
        default:
            break
        }
    }

    func startMonitoring() {
        guard timer == nil else {
            bootstrapCurrentPasteboard(reason: "already-monitoring")
            return
        }
        lastChangeCount = NSPasteboard.general.changeCount
        bootstrapCurrentPasteboard(reason: "start-monitoring")
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPasteboard()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard settings.isFeatureEnabled(.clipboardShelf), !isWritingPasteboard else { return }
        guard let item = makeItem(from: pasteboard) else { return }
        insert(item)
    }

    func bootstrapCurrentPasteboard(reason: String = "manual") {
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        guard settings.isFeatureEnabled(.clipboardShelf), !isWritingPasteboard else { return }
        guard let item = makeItem(from: pasteboard) else {
            print("[ClipboardStore] bootstrap skipped empty pasteboard reason=\(reason) changeCount=\(pasteboard.changeCount)")
            return
        }
        print("[ClipboardStore] bootstrap current pasteboard type=\(item.type.rawValue) title=\(item.title) reason=\(reason) changeCount=\(pasteboard.changeCount)")
        insert(item)
    }

    func insert(_ item: ClipboardShelfItem) {
        guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let existing = items.firstIndex(where: { $0.stableKey == item.stableKey }) {
            var updated = items.remove(at: existing)
            updated.copiedAt = Date()
            items.insert(updated, at: 0)
            if item.imageFilename != updated.imageFilename {
                deleteImageIfNeeded(item)
            }
        } else {
            items.insert(item, at: 0)
        }
        enforceLimit()
        commit()
    }

    func remove(id: UUID, clearSystemPasteboardIfCurrent: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        if clearSystemPasteboardIfCurrent, matchesCurrentPasteboard(removed) {
            clearSystemPasteboard()
        }
        deleteImageIfNeeded(removed)
        commit()
    }

    func clear(includePinned: Bool = false, clearSystemPasteboard: Bool = false) {
        let removed = includePinned ? items : items.filter { !$0.pinned }
        if clearSystemPasteboard {
            self.clearSystemPasteboard()
        }
        for item in removed { deleteImageIfNeeded(item) }
        items = includePinned ? [] : items.filter(\.pinned)
        commit()
    }

    func togglePinned(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        sortPinnedFirst()
        commit()
    }

    func item(id: UUID) -> ClipboardShelfItem? {
        items.first { $0.id == id }
    }

    func writeToPasteboard(id: UUID) -> Bool {
        guard let item = item(id: id) else { return false }
        return writeToPasteboard(item)
    }

    @discardableResult
    func writeToPasteboard(_ item: ClipboardShelfItem) -> Bool {
        isWritingPasteboard = true
        defer {
            lastChangeCount = NSPasteboard.general.changeCount
            DispatchQueue.main.async { [weak self] in
                self?.isWritingPasteboard = false
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.type {
        case .text:
            guard let text = item.text else { return false }
            pasteboard.setString(text, forType: .string)
            return true
        case .url:
            guard let value = item.urlString else { return false }
            pasteboard.setString(value, forType: .string)
            pasteboard.setString(value, forType: .URL)
            return true
        case .file:
            guard let value = item.fileURLString, let url = URL(string: value) else { return false }
            pasteboard.writeObjects([url as NSURL])
            return true
        case .image:
            guard let imageFilename = item.imageFilename,
                  let image = NSImage(contentsOf: Self.imageDirectory.appendingPathComponent(imageFilename))
            else { return false }
            pasteboard.writeObjects([image])
            return true
        }
    }

    private func clearSystemPasteboard() {
        isWritingPasteboard = true
        NSPasteboard.general.clearContents()
        lastChangeCount = NSPasteboard.general.changeCount
        DispatchQueue.main.async { [weak self] in
            self?.isWritingPasteboard = false
            self?.lastChangeCount = NSPasteboard.general.changeCount
        }
    }

    private func makeItem(from pasteboard: NSPasteboard) -> ClipboardShelfItem? {
        if settings.captureClipboardFiles,
           let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
           ) as? [URL],
           let url = urls.first {
            return ClipboardShelfItem(
                id: UUID(),
                type: .file,
                title: url.lastPathComponent,
                copiedAt: Date(),
                text: nil,
                urlString: nil,
                fileURLString: url.absoluteString,
                imageFilename: nil,
                pinned: false
            )
        }

        if settings.captureClipboardURLs,
           let url = Self.url(from: pasteboard) {
            return ClipboardShelfItem(
                id: UUID(),
                type: .url,
                title: Self.shortTitle(for: url.absoluteString),
                copiedAt: Date(),
                text: url.absoluteString,
                urlString: url.absoluteString,
                fileURLString: nil,
                imageFilename: nil,
                pinned: false
            )
        }

        if settings.captureClipboardImages,
           let image = NSImage(pasteboard: pasteboard),
           let filename = persist(image: image) {
            return ClipboardShelfItem(
                id: UUID(),
                type: .image,
                title: "Image \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))",
                copiedAt: Date(),
                text: nil,
                urlString: nil,
                fileURLString: nil,
                imageFilename: filename,
                pinned: false
            )
        }

        if settings.captureClipboardText,
           let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           !Self.looksSensitive(text) {
            return ClipboardShelfItem(
                id: UUID(),
                type: .text,
                title: Self.shortTitle(for: text),
                copiedAt: Date(),
                text: text,
                urlString: nil,
                fileURLString: nil,
                imageFilename: nil,
                pinned: false
            )
        }
        return nil
    }

    private func matchesCurrentPasteboard(_ item: ClipboardShelfItem) -> Bool {
        matches(item, pasteboard: .general)
    }

    private func matches(_ item: ClipboardShelfItem, pasteboard: NSPasteboard) -> Bool {
        switch item.type {
        case .text:
            return ClipboardShelfItem.canonicalText(pasteboard.string(forType: .string))
                == ClipboardShelfItem.canonicalText(item.text)
        case .url:
            let currentURL = Self.url(from: pasteboard)?.absoluteString
                ?? pasteboard.string(forType: .URL)
                ?? pasteboard.string(forType: .string)
            return ClipboardShelfItem.canonicalURL(currentURL)
                == ClipboardShelfItem.canonicalURL(item.urlString)
        case .file:
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL]
            let current = urls?.first?.absoluteString
            return ClipboardShelfItem.canonicalFileURL(current)
                == ClipboardShelfItem.canonicalFileURL(item.fileURLString)
        case .image:
            guard let image = NSImage(pasteboard: pasteboard),
                  let currentData = Self.pngData(from: image),
                  let imageFilename = item.imageFilename,
                  let storedData = try? Data(contentsOf: Self.imageDirectory.appendingPathComponent(imageFilename))
            else { return false }
            return ClipboardShelfItem.fnv1a64Hex(currentData) == ClipboardShelfItem.fnv1a64Hex(storedData)
                && currentData.count == storedData.count
        }
    }

    private func persist(image: NSImage) -> String? {
        do {
            try FileManager.default.createDirectory(
                at: Self.imageDirectory,
                withIntermediateDirectories: true
            )
            guard let png = Self.pngData(from: image)
            else { return nil }
            let filename = "\(UUID().uuidString).png"
            try png.write(to: Self.imageDirectory.appendingPathComponent(filename))
            return filename
        } catch {
            print("[ClipboardStore] image persist failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func enforceLimit() {
        sortPinnedFirst()
        let limit = settings.maxClipboardHistory
        let pinned = items.filter(\.pinned)
        var normal = items.filter { !$0.pinned }
        if normal.count > max(limit - pinned.count, 0) {
            let removed = normal.dropFirst(max(limit - pinned.count, 0))
            for item in removed { deleteImageIfNeeded(item) }
            normal = Array(normal.prefix(max(limit - pinned.count, 0)))
        }
        items = pinned + normal
    }

    private func sortPinnedFirst() {
        items.sort {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            return $0.copiedAt > $1.copiedAt
        }
    }

    private func commit() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.storageKey)
        }
        onChange?(items)
    }

    private func deleteImageIfNeeded(_ item: ClipboardShelfItem) {
        guard item.type == .image, let imageFilename = item.imageFilename else { return }
        try? FileManager.default.removeItem(at: Self.imageDirectory.appendingPathComponent(imageFilename))
    }

    private static func shortTitle(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 28 else { return trimmed }
        return String(trimmed.prefix(25)) + "..."
    }

    private static func looksSensitive(_ text: String) -> Bool {
        guard text.count >= 8 else { return false }
        let lower = text.lowercased()
        if lower.contains("password") || lower.contains("secret") || lower.contains("token") {
            return true
        }
        let hasLetter = text.rangeOfCharacter(from: .letters) != nil
        let hasNumber = text.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpace = text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        return !hasSpace && hasLetter && hasNumber && text.count >= 18
    }

    private static func url(from pasteboard: NSPasteboard) -> URL? {
        if let value = pasteboard.string(forType: .URL), let url = URL(string: value), !url.isFileURL {
            return url
        }
        if let value = pasteboard.string(forType: .string),
           let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
           !url.isFileURL,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        return nil
    }
}
