import AppKit

struct ShelfBarIconThemeDescriptor {
    let theme: ShelfBarIconTheme
    let displayName: String
    let lightResourceName: String
    let darkResourceName: String
    let previewResourceName: String
}

enum ShelfBarIconTheme: String, CaseIterable {
    case `default` = "default"
    case touchBar = "touchBar"
    case folders = "folders"
    case layers = "layers"
    case photoShelf = "photoShelf"
    case minimal = "minimal"

    static let defaultsKey = "ShelfBar.iconTheme"
    static let didChangeNotification = Notification.Name("ShelfBar.iconTheme.didChange")
    private static var imageCache: [String: NSImage] = [:]
    private static var lastAppliedAppIconKey: String?

    var descriptor: ShelfBarIconThemeDescriptor {
        switch self {
        case .default:
            ShelfBarIconThemeDescriptor(
                theme: self,
                displayName: "Default",
                lightResourceName: "Default-Light",
                darkResourceName: "Default-Dark",
                previewResourceName: "Default-Split"
            )
        case .touchBar:
            ShelfBarIconThemeDescriptor(
                theme: self,
                displayName: "Touch Bar",
                lightResourceName: "TouchBar-Light",
                darkResourceName: "TouchBar-Dark",
                previewResourceName: "TouchBar-Split"
            )
        case .folders:
            ShelfBarIconThemeDescriptor(
                theme: self,
                displayName: "Folders",
                lightResourceName: "Folders-Light",
                darkResourceName: "Folders-Dark",
                previewResourceName: "Folders-Split"
            )
        case .layers:
            ShelfBarIconThemeDescriptor(
                theme: self,
                displayName: "Layers",
                lightResourceName: "Layers-Light",
                darkResourceName: "Layers-Dark",
                previewResourceName: "Layers-Split"
            )
        case .photoShelf:
            ShelfBarIconThemeDescriptor(
                theme: self,
                displayName: "Photo Shelf",
                lightResourceName: "PhotoShelf-Light",
                darkResourceName: "PhotoShelf-Dark",
                previewResourceName: "PhotoShelf-Split"
            )
        case .minimal:
            ShelfBarIconThemeDescriptor(
                theme: self,
                displayName: "Minimal",
                lightResourceName: "Minimal-Light",
                darkResourceName: "Minimal-Dark",
                previewResourceName: "Minimal-Split"
            )
        }
    }

    var displayName: String {
        descriptor.displayName
    }

    static var current: ShelfBarIconTheme {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ShelfBarIconTheme.default.rawValue
        return ShelfBarIconTheme(rawValue: raw) ?? .default
    }

    static func setCurrent(_ theme: ShelfBarIconTheme) {
        guard current != theme else {
            return
        }
        UserDefaults.standard.set(theme.rawValue, forKey: defaultsKey)
        updateApplicationIcon()
        NotificationCenter.default.post(name: didChangeNotification, object: theme)
    }

    static func image(for appearance: NSAppearance) -> NSImage? {
        current.appImage(for: appearance)
    }

    static func updateApplicationIcon() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let iconKey = "\(current.rawValue):\(dark ? "dark" : "light")"
        guard lastAppliedAppIconKey != iconKey else { return }
        guard let image = resolvedAppImage(for: current, appearance: NSApp.effectiveAppearance) else {
            print("[IconTheme] No valid app icon resolved; keeping current applicationIconImage")
            return
        }
        image.isTemplate = false
        NSApp.dockTile.contentView = nil
        NSApp.applicationIconImage = image
        NSApp.dockTile.display()
        lastAppliedAppIconKey = iconKey
        print("[IconTheme] Applied \(current.displayName) icon size=\(image.size)")
    }

    static func statusBarTemplateImage() -> NSImage {
        if let image = loadStatusBarTemplateResource() {
            return image
        }
        return fallbackTemplateIcon(size: NSSize(width: 18, height: 18))
    }

    func appImage(for appearance: NSAppearance) -> NSImage? {
        Self.resolvedAppImage(for: self, appearance: appearance)
    }

    func splitPreviewImage() -> NSImage? {
        Self.loadImage(
            named: descriptor.previewResourceName,
            subdirectory: "IconThemes/SplitPreviews",
            allowsSplit: true,
            purpose: "preview"
        ) ?? appImage(for: NSApp.effectiveAppearance)
    }

    private static func loadStatusBarTemplateResource() -> NSImage? {
        let names = [
            "ShelfBarStatusTemplate-18@2x",
            "ShelfBarStatusTemplate-36@2x"
        ]
        for name in names {
            let cacheKey = "menu:\(name)"
            if let cached = imageCache[cacheKey] {
                return cached
            }
            guard let url = Bundle.main.url(
                forResource: name,
                withExtension: "png",
                subdirectory: "IconThemes/MenuBar"
            ),
                let image = NSImage(contentsOf: url)
            else {
                continue
            }
            var rect = NSRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                  containsVisiblePixels(cgImage)
            else {
                print("[IconTheme] Rejected blank menu bar template \(name).png")
                continue
            }
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            imageCache[cacheKey] = image
            print("[IconTheme] Loaded menu bar template \(name).png")
            return image
        }
        print("[IconTheme] Missing menu bar template resource, using vector fallback")
        return nil
    }

    private static func resolvedAppImage(
        for theme: ShelfBarIconTheme,
        appearance: NSAppearance
    ) -> NSImage? {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let descriptor = theme.descriptor
        let resourceName = dark ? descriptor.darkResourceName : descriptor.lightResourceName
        let cacheKey = "app:\(resourceName)"
        if let cached = imageCache[cacheKey] {
            return cached
        }
        if let image = loadImage(
            named: resourceName,
            subdirectory: "IconThemes/LightDark",
            allowsSplit: false,
            purpose: "app icon"
        ) {
            print("[IconTheme] Loaded \(resourceName).png")
            imageCache[cacheKey] = image
            return image
        }

        if theme != .default {
            print("[IconTheme] Missing or invalid \(resourceName).png, falling back to Default")
            return resolvedAppImage(for: .default, appearance: appearance)
        }

        let legacyName = dark ? "ShelfBarDark" : "ShelfBarLight"
        if let image = loadBundleImage(named: legacyName, purpose: "legacy default") {
            print("[IconTheme] Loaded legacy \(legacyName)")
            return image
        }

        if let bundleIcon = loadBundleImage(named: "ShelfBar", purpose: "CFBundleIconFile") {
            print("[IconTheme] Loaded CFBundleIconFile ShelfBar")
            return bundleIcon
        }

        print("[IconTheme] Default fallback failed")
        return nil
    }

    private static func loadImage(
        named name: String,
        subdirectory: String,
        allowsSplit: Bool,
        purpose: String
    ) -> NSImage? {
        let cacheKey = "\(purpose):\(subdirectory)/\(name)"
        if let cached = imageCache[cacheKey] {
            return cached
        }
        if !allowsSplit && name.localizedCaseInsensitiveContains("split") {
            print("[IconTheme] Rejected Split resource for app icon: \(name)")
            return nil
        }
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: subdirectory
        ) else {
            print("[IconTheme] Missing resource \(subdirectory)/\(name).png")
            return nil
        }
        guard let image = NSImage(contentsOf: url) else {
            print("[IconTheme] Cannot decode \(name).png")
            return nil
        }
        guard let validated = validated(image: image, label: "\(name).png", purpose: purpose) else {
            return nil
        }
        imageCache[cacheKey] = validated
        return validated
    }

    private static func loadBundleImage(named name: String, purpose: String) -> NSImage? {
        let cacheKey = "\(purpose):bundle/\(name)"
        if let cached = imageCache[cacheKey] {
            return cached
        }
        guard let image = Bundle.main.image(forResource: name) else {
            print("[IconTheme] Missing bundle image \(name)")
            return nil
        }
        guard let validated = validated(image: image, label: name, purpose: purpose) else {
            return nil
        }
        imageCache[cacheKey] = validated
        return validated
    }

    private static func validated(image: NSImage, label: String, purpose: String) -> NSImage? {
        guard image.size.width > 0,
              image.size.height > 0,
              !image.representations.isEmpty
        else {
            print("[IconTheme] Rejected invalid image \(label) purpose=\(purpose)")
            return nil
        }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              cgImage.width > 0,
              cgImage.height > 0
        else {
            print("[IconTheme] Rejected undecodable image \(label) purpose=\(purpose)")
            return nil
        }
        guard containsVisiblePixels(cgImage) else {
            print("[IconTheme] Rejected transparent/blank image \(label) purpose=\(purpose)")
            return nil
        }
        image.isTemplate = false
        return image
    }

    private static func containsVisiblePixels(_ cgImage: CGImage) -> Bool {
        let sampleWidth = min(cgImage.width, 256)
        let sampleHeight = min(cgImage.height, 256)
        var bytes = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        guard let context = CGContext(
            data: &bytes,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        var visibleCount = 0
        var minX = sampleWidth
        var minY = sampleHeight
        var maxX = -1
        var maxY = -1
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let alpha = bytes[(y * sampleWidth + x) * 4 + 3]
                if alpha > 8 {
                    visibleCount += 1
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard visibleCount > 128,
              maxX > minX,
              maxY > minY
        else {
            return false
        }
        return (maxX - minX) > 8 && (maxY - minY) > 8
    }

    private static func fallbackTemplateIcon(size: NSSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let scaleX = rect.width / 18
            let scaleY = rect.height / 18
            func scaled(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
                NSRect(
                    x: x * scaleX,
                    y: y * scaleY,
                    width: width * scaleX,
                    height: height * scaleY
                )
            }
            let back = NSBezierPath(
                roundedRect: scaled(6.2, 7.1, 7.6, 7.2),
                xRadius: 1.6 * scaleX,
                yRadius: 1.6 * scaleY
            )
            back.fill()
            let front = NSBezierPath(
                roundedRect: scaled(3.8, 5.1, 7.8, 7.2),
                xRadius: 1.6 * scaleX,
                yRadius: 1.6 * scaleY
            )
            front.fill()
            let bar = NSBezierPath(
                roundedRect: scaled(2.0, 2.4, 14.0, 2.8),
                xRadius: 1.4 * scaleX,
                yRadius: 1.4 * scaleY
            )
            bar.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
