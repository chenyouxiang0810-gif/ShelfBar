import AppKit

struct DropPayloadInspection {
    let pasteboardTypes: [String]
    let imports: [ShelfImport]
    let urls: [URL]
    let detectedKinds: [ShelfItemKind]
    let successfulReaders: [String]
    let failureReasons: [String]
}

enum ShelfDropZone: String {
    case none
    case airDrop
    case shelf
    case gap
}

struct ShelfDropZoneSnapshot {
    let zone: ShelfDropZone
    let locationX: CGFloat
    let airDropRect: NSRect
    let shelfRect: NSRect
    let gapRect: NSRect
}

@MainActor
protocol OverlayDropDelegate: AnyObject {
    func overlayDragEntered(snapshot: ShelfDropZoneSnapshot)
    func overlayDragUpdated(snapshot: ShelfDropZoneSnapshot)
    func overlayDragExited()
    func overlayDragEnded()
    func overlayDidReceive(imports: [ShelfImport])
    func overlayDidRequestAirDrop(imports: [ShelfImport], inspection: DropPayloadInspection)
    func overlayDropDidFail(_ inspection: DropPayloadInspection)
}

enum FileDropReader {
    static let legacyURLType = NSPasteboard.PasteboardType("NSURLPboardType")
    static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    static let imageType = NSPasteboard.PasteboardType("public.image")
    static let pngType = NSPasteboard.PasteboardType("public.png")
    static let jpegType = NSPasteboard.PasteboardType("public.jpeg")
    static let plainTextType = NSPasteboard.PasteboardType("public.plain-text")
    static let utf8TextType = NSPasteboard.PasteboardType("public.utf8-plain-text")
    static let legacyStringType = NSPasteboard.PasteboardType("NSStringPboardType")
    static let urlNameType = NSPasteboard.PasteboardType("public.url-name")
    static let registeredTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        legacyURLType,
        legacyFilenamesType,
        imageType,
        pngType,
        jpegType,
        .tiff,
        .string,
        plainTextType,
        utf8TextType,
        legacyStringType,
        .rtf,
        .html
    ]

    static func supports(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        return !Set(types).isDisjoint(with: Set(registeredTypes))
    }

    static func inspect(_ pasteboard: NSPasteboard) -> DropPayloadInspection {
        let pasteboardTypes = (pasteboard.types ?? []).map(\.rawValue)
        var urls: [URL] = []
        var imports: [ShelfImport] = []
        var detectedKinds: [ShelfItemKind] = []
        var successfulReaders: [String] = []
        var failureReasons: [String] = []

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let modernURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL]) ?? []
        if modernURLs.isEmpty {
            failureReasons.append(".fileURL/NSURL readObjects returned no file URLs")
        } else {
            urls.append(contentsOf: modernURLs)
            successfulReaders.append(".fileURL readObjects")
        }

        if let value = pasteboard.string(forType: legacyURLType),
           let url = URL(string: value),
           url.isFileURL {
            urls.append(url)
            successfulReaders.append("NSURLPboardType")
        } else {
            failureReasons.append("NSURLPboardType was absent or not a file URL")
        }

        if let value = pasteboard.string(forType: .URL),
           let url = URL(string: value),
           url.isFileURL {
            urls.append(url)
            successfulReaders.append("public.url")
        } else {
            failureReasons.append("public.url was absent or not a file URL")
        }

        if let filenames = pasteboard.propertyList(forType: legacyFilenamesType) as? [String],
           !filenames.isEmpty {
            urls.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
            successfulReaders.append("NSFilenamesPboardType")
        } else {
            failureReasons.append("NSFilenamesPboardType was absent or contained no filenames")
        }

        var seenPaths = Set<String>()
        let uniqueURLs = urls.filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
        if !uniqueURLs.isEmpty {
            imports = uniqueURLs.map {
                ShelfImport.file($0, source: "Pasteboard: \(pasteboardTypes.joined(separator: ", "))")
            }
            detectedKinds = Array(repeating: .file, count: imports.count)
        } else if let materialized = materializeNonFileContent(
            from: pasteboard,
            pasteboardTypes: pasteboardTypes
        ) {
            imports = [materialized]
            detectedKinds = [materialized.kind]
            successfulReaders.append("materialized \(materialized.kind.rawValue)")
        } else if supports(pasteboard) {
            failureReasons.append("A supported pasteboard type was advertised, but no readable representation could be materialized")
        }

        if imports.isEmpty && pasteboardTypes.isEmpty {
            failureReasons.append("pasteboard.types was empty")
        }

        return DropPayloadInspection(
            pasteboardTypes: pasteboardTypes,
            imports: imports,
            urls: imports.map(\.url),
            detectedKinds: detectedKinds,
            successfulReaders: successfulReaders,
            failureReasons: failureReasons
        )
    }

    private static func materializeNonFileContent(
        from pasteboard: NSPasteboard,
        pasteboardTypes: [String]
    ) -> ShelfImport? {
        let source = "Pasteboard: \(pasteboardTypes.joined(separator: ", "))"

        if let image = imageFromPasteboard(pasteboard),
           let data = pngData(for: image),
           let url = write(data: data, prefix: "ShelfBar_Image", extension: "png") {
            return ShelfImport(
                url: url,
                displayName: url.lastPathComponent,
                kind: .image,
                originalSourceDescription: "\(source); selected image because an image representation was readable",
                originalFileURL: nil,
                localURL: url
            )
        }

        if let text = explicitPlainText(from: pasteboard),
           !isExplicitURLText(text, on: pasteboard),
           let textImport = materializeText(text, source: source, reason: "explicit plain-text representation takes priority over URL") {
            return textImport
        }

        if let data = pasteboard.data(forType: .rtf),
           let url = write(data: data, prefix: "ShelfBar_RichText", extension: "rtf") {
            return ShelfImport(
                url: url,
                displayName: url.lastPathComponent,
                kind: .richText,
                originalSourceDescription: "\(source); selected richText because RTF data was readable after image/plain text",
                originalFileURL: nil,
                localURL: url
            )
        }

        let htmlData = pasteboard.data(forType: .html)
            ?? pasteboard.string(forType: .html)?.data(using: .utf8)
        if let data = htmlData,
           let url = write(data: data, prefix: "ShelfBar_HTML", extension: "html") {
            return ShelfImport(
                url: url,
                displayName: url.lastPathComponent,
                kind: .richText,
                originalSourceDescription: "\(source); selected richText because HTML data was readable after image/plain text",
                originalFileURL: nil,
                localURL: url
            )
        }

        if let urlValue = nonFileURL(from: pasteboard) {
            let urlReason: String
            if let text = explicitPlainText(from: pasteboard), isExplicitURLText(text, on: pasteboard) {
                urlReason = "plain text matched the advertised URL/link name"
            } else {
                urlReason = "no higher-priority file/image/plain-text/rich-text payload was selected"
            }
            let title = pasteboard.string(forType: urlNameType)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayBase = title?.isEmpty == false
                ? title!
                : (urlValue.host?.isEmpty == false ? urlValue.host! : urlValue.absoluteString)
            let plist: [String: Any] = ["URL": urlValue.absoluteString]
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            ), let localURL = write(
                data: data,
                prefix: safeFilename(displayBase),
                extension: "webloc"
            ) {
                return ShelfImport(
                    url: localURL,
                    displayName: "\(displayBase).webloc",
                    kind: .url,
                    originalSourceDescription: "\(source); selected URL because \(urlReason)",
                    originalFileURL: nil,
                    localURL: localURL
                )
            }
        }

        if let text = pasteboard.string(forType: .string),
           let textImport = materializeText(text, source: source, reason: "fallback string was not selected as a URL") {
            return textImport
        }
        return nil
    }

    private static func explicitPlainText(from pasteboard: NSPasteboard) -> String? {
        pasteboard.string(forType: utf8TextType)
            ?? pasteboard.string(forType: plainTextType)
            ?? pasteboard.string(forType: legacyStringType)
    }

    private static func isExplicitURLText(_ text: String, on pasteboard: NSPasteboard) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let textURL = URL(string: trimmed), textURL.scheme != nil, !textURL.isFileURL,
              let advertisedURL = nonFileURL(from: pasteboard)
        else {
            let linkName = pasteboard.string(forType: urlNameType)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return linkName?.isEmpty == false && linkName == trimmed
                && nonFileURL(from: pasteboard) != nil
        }
        return textURL.absoluteString == advertisedURL.absoluteString
    }

    private static func materializeText(
        _ text: String,
        source: String,
        reason: String
    ) -> ShelfImport? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = text.data(using: .utf8) else { return nil }
        let singleLine = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let preview = String(singleLine.prefix(18))
        guard let url = write(data: data, prefix: safeFilename(preview), extension: "txt") else {
            return nil
        }
        return ShelfImport(
            url: url,
            displayName: "\(preview).txt",
            kind: .text,
            originalSourceDescription: "\(source); selected text because \(reason)",
            originalFileURL: nil,
            localURL: url
        )
    }

    private static func imageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        if let data = pasteboard.data(forType: pngType), let image = NSImage(data: data) {
            return image
        }
        if let data = pasteboard.data(forType: jpegType), let image = NSImage(data: data) {
            return image
        }
        if let data = pasteboard.data(forType: .tiff), let image = NSImage(data: data) {
            return image
        }
        return NSImage(pasteboard: pasteboard)
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func nonFileURL(from pasteboard: NSPasteboard) -> URL? {
        let values = [
            pasteboard.string(forType: .URL),
            pasteboard.string(forType: legacyURLType),
            pasteboard.string(forType: .string)
        ]
        return values.compactMap { $0 }.compactMap(URL.init(string:)).first { !$0.isFileURL }
    }

    private static func write(data: Data, prefix: String, extension ext: String) -> URL? {
        let manager = FileManager.default
        guard let applicationSupport = manager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = applicationSupport
            .appendingPathComponent("ShelfBar", isDirectory: true)
            .appendingPathComponent("Items", isDirectory: true)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let name = "\(safeFilename(prefix))_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6)).\(ext)"
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>\n\r\t")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "ShelfBar_Item" : cleaned).prefix(48))
    }
}
