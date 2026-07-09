import AppKit
import QuickLook
import UniformTypeIdentifiers

extension Notification.Name {
    static let shelfBarThumbnailReady = Notification.Name("ShelfBar.thumbnailReady")
}

private func createQuickLookThumbnailImage(for url: URL) -> CGImage? {
    QLThumbnailImageCreate(
        kCFAllocatorDefault,
        url as CFURL,
        CGSize(width: 96, height: 56),
        nil
    )?.takeRetainedValue()
}

struct FileShelfItem {
    let id: UUID
    let url: URL
    let filename: String
    let kind: ShelfItemKind
    let originalSourceDescription: String
    let originalFileURL: URL?
    let localURL: URL?
    let displayImage: NSImage

    init(
        id: UUID = UUID(),
        url: URL,
        filename: String,
        kind: ShelfItemKind = .file,
        originalSourceDescription: String = "File URL",
        originalFileURL: URL? = nil,
        localURL: URL? = nil,
        displayImage: NSImage
    ) {
        self.id = id
        self.url = url
        self.filename = filename
        self.kind = kind
        self.originalSourceDescription = originalSourceDescription
        self.originalFileURL = originalFileURL
        self.localURL = localURL
        self.displayImage = displayImage
    }
}

enum ShelfItemKind: String, Codable {
    case file
    case image
    case text
    case url
    case richText
    case stack
    case unknown
}

struct ShelfImport {
    let url: URL
    let displayName: String
    let kind: ShelfItemKind
    let originalSourceDescription: String
    let originalFileURL: URL?
    let localURL: URL?

    static func file(_ url: URL, source: String = "File URL") -> ShelfImport {
        ShelfImport(
            url: url,
            displayName: url.lastPathComponent,
            kind: .file,
            originalSourceDescription: source,
            originalFileURL: url,
            localURL: nil
        )
    }
}

private struct StoredShelfItem: Codable {
    let id: UUID
    let urlString: String
    let displayName: String
    let kind: ShelfItemKind
    let originalSourceDescription: String
    let originalFileURLString: String?
    let localURLString: String?
}

@MainActor
final class FileShelfModel {
    private static let storedURLsKey = "FileShelf.v2.storedURLs"
    private static let storedItemsKey = "ShelfBar.items.v3"
    private static let maxThumbnailWidth: CGFloat = 48
    private static let maxThumbnailHeight: CGFloat = 28
    private static var thumbnailCache: [URL: NSImage] = [:]
    private static var pendingThumbnails: Set<URL> = []

    private(set) var items: [FileShelfItem]
    var onChange: (([FileShelfItem]) -> Void)?
    var onThumbnailChange: ((IndexSet) -> Void)?
    private var thumbnailObserver: NSObjectProtocol?

    init() {
        items = Self.itemsFromStorage()
        thumbnailObserver = NotificationCenter.default.addObserver(
            forName: .shelfBarThumbnailReady,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor [weak self] in
                self?.refreshThumbnail(for: url)
            }
        }
    }

    func add(urls: [URL]) {
        add(imports: urls.map { ShelfImport.file($0) })
    }

    func add(imports: [ShelfImport]) {
        let newItems = imports.map { Self.makeItem(import: $0) }
        guard !newItems.isEmpty else { return }
        items.append(contentsOf: newItems)
        commitChange()
    }

    func add(existingItems: [FileShelfItem]) {
        guard !existingItems.isEmpty else { return }
        items.append(contentsOf: existingItems)
        commitChange()
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        commitChange()
    }

    func remove(ids: Set<UUID>) {
        let previousCount = items.count
        items.removeAll { ids.contains($0.id) }
        guard items.count != previousCount else { return }
        commitChange()
    }

    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        commitChange()
    }

    func reloadFromDisk() {
        items = Self.itemsFromStorage()
        onChange?(items)
    }

    func move(id: UUID, to destinationIndex: Int) {
        guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: sourceIndex)
        var adjusted = destinationIndex
        if sourceIndex < adjusted { adjusted -= 1 }
        adjusted = min(max(adjusted, 0), items.count)
        items.insert(item, at: adjusted)
        commitChange()
    }

    private func commitChange() {
        let stored = items.map {
            StoredShelfItem(
                id: $0.id,
                urlString: $0.url.absoluteString,
                displayName: $0.filename,
                kind: $0.kind,
                originalSourceDescription: $0.originalSourceDescription,
                originalFileURLString: $0.originalFileURL?.absoluteString,
                localURLString: $0.localURL?.absoluteString
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storedItemsKey)
        }
        UserDefaults.standard.set(
            items.map { $0.url.absoluteString },
            forKey: Self.storedURLsKey
        )
        onChange?(items)
    }

    private static func itemsFromStorage() -> [FileShelfItem] {
        if let data = UserDefaults.standard.data(forKey: storedItemsKey),
           let stored = try? JSONDecoder().decode([StoredShelfItem].self, from: data) {
            return stored.compactMap { value in
                guard let url = URL(string: value.urlString), url.isFileURL else { return nil }
                return makeItem(
                    url: url,
                    id: value.id,
                    displayName: value.displayName,
                    kind: value.kind,
                    originalSourceDescription: value.originalSourceDescription,
                    originalFileURL: value.originalFileURLString.flatMap(URL.init(string:)),
                    localURL: value.localURLString.flatMap(URL.init(string:))
                )
            }
        }
        let strings = UserDefaults.standard.stringArray(forKey: storedURLsKey) ?? []
        return strings.compactMap(URL.init(string:)).filter(\.isFileURL).map { makeItem(url: $0) }
    }

    static func makeItem(url: URL, id: UUID = UUID()) -> FileShelfItem {
        let kind = inferredKind(for: url)
        return makeItem(
            url: url,
            id: id,
            displayName: url.lastPathComponent,
            kind: kind,
            originalSourceDescription: "File URL or legacy URL-only persistence",
            originalFileURL: url,
            localURL: nil
        )
    }

    static func makeItem(import value: ShelfImport, id: UUID = UUID()) -> FileShelfItem {
        makeItem(
            url: value.url,
            id: id,
            displayName: value.displayName,
            kind: value.kind,
            originalSourceDescription: value.originalSourceDescription,
            originalFileURL: value.originalFileURL,
            localURL: value.localURL
        )
    }

    static func makeItem(
        url: URL,
        id: UUID,
        displayName: String,
        kind: ShelfItemKind,
        originalSourceDescription: String,
        originalFileURL: URL?,
        localURL: URL?
    ) -> FileShelfItem {
        FileShelfItem(
            id: id,
            url: url,
            filename: displayName,
            kind: kind,
            originalSourceDescription: originalSourceDescription,
            originalFileURL: originalFileURL,
            localURL: localURL,
            displayImage: displayImage(for: url)
        )
    }

    private static func inferredKind(for url: URL) -> ShelfItemKind {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "tiff", "tif", "heic", "gif", "webp": .image
        case "txt": .text
        case "webloc", "url": .url
        case "rtf", "html", "htm": .richText
        default: .file
        }
    }

    private static func displayImage(for url: URL) -> NSImage {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        if values?.isDirectory != true,
           (values?.contentType?.conforms(to: .image) == true
                || values?.contentType?.conforms(to: .movie) == true) {
            if let thumbnail = thumbnailCache[url] {
                return thumbnail
            }
            scheduleQuickLookThumbnail(for: url)
        }

        let workspaceIcon = NSWorkspace.shared.icon(forFile: url.path)
        let icon = (workspaceIcon.copy() as? NSImage) ?? workspaceIcon
        icon.size = NSSize(width: 24, height: 24)
        return icon
    }

    private static func scheduleQuickLookThumbnail(for url: URL) {
        guard !pendingThumbnails.contains(url) else { return }
        pendingThumbnails.insert(url)
        DispatchQueue.global(qos: .userInitiated).async {
            let cgImage = createQuickLookThumbnailImage(for: url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    pendingThumbnails.remove(url)
                    if let cgImage {
                        let image = NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height)
                        )
                        thumbnailCache[url] = aspectFit(
                            image,
                            maxWidth: maxThumbnailWidth,
                            maxHeight: maxThumbnailHeight
                        )
                        NotificationCenter.default.post(
                            name: .shelfBarThumbnailReady,
                            object: url
                        )
                    }
                }
            }
        }
    }

    private func refreshThumbnail(for url: URL) {
        var changed = IndexSet()
        for index in items.indices where items[index].url == url {
            let existing = items[index]
            items[index] = Self.makeItem(
                url: url,
                id: existing.id,
                displayName: existing.filename,
                kind: existing.kind,
                originalSourceDescription: existing.originalSourceDescription,
                originalFileURL: existing.originalFileURL,
                localURL: existing.localURL
            )
            changed.insert(index)
        }
        if !changed.isEmpty {
            onThumbnailChange?(changed)
        }
    }

    static func aspectFit(_ image: NSImage, maxWidth: CGFloat, maxHeight: CGFloat) -> NSImage {
        let sourceWidth = image.size.width
        let sourceHeight = image.size.height
        guard sourceWidth > 0, sourceHeight > 0 else { return image }
        let scale = min(
            1,
            maxWidth / sourceWidth,
            maxHeight / sourceHeight
        )
        let fittedSize = NSSize(
            width: sourceWidth * scale,
            height: sourceHeight * scale
        )
        guard fittedSize != image.size else { return image }
        let fitted = NSImage(size: fittedSize)
        fitted.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: fittedSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        fitted.unlockFocus()
        return fitted
    }
}
