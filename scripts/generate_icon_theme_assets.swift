import AppKit
import CoreGraphics
import Foundation

struct ThemeInput {
    let stem: String
    let lightSource: String
    let darkSource: String
}

let projectRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let externalRoot = URL(fileURLWithPath: CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "/Users/seannb/Documents/Codex/2026-07-22/referenced-chatgpt-conversation-this-is-untrusted/outputs/ShelfBar_Icon_Themes")

let outputLightDark = projectRoot
    .appendingPathComponent("TouchBarPrivateResearch/Resources/IconThemes/LightDark")
let outputSplit = projectRoot
    .appendingPathComponent("TouchBarPrivateResearch/Resources/IconThemes/SplitPreviews")
let outputMenuBar = projectRoot
    .appendingPathComponent("TouchBarPrivateResearch/Resources/IconThemes/MenuBar")
try FileManager.default.createDirectory(at: outputLightDark, withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: outputSplit.path) {
    try FileManager.default.removeItem(at: outputSplit)
}
if FileManager.default.fileExists(atPath: outputMenuBar.path) {
    try FileManager.default.removeItem(at: outputMenuBar)
}
try FileManager.default.createDirectory(at: outputSplit, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outputMenuBar, withIntermediateDirectories: true)

let themes = [
    ThemeInput(
        stem: "Default",
        lightSource: projectRoot.appendingPathComponent("TouchBarPrivateResearch/Resources/ShelfBarLight.png").path,
        darkSource: projectRoot.appendingPathComponent("TouchBarPrivateResearch/Resources/ShelfBarDark.png").path
    ),
    ThemeInput(stem: "TouchBar", lightSource: "TouchBar-Light.png", darkSource: "TouchBar-Dark.png"),
    ThemeInput(stem: "Folders", lightSource: "Folders-Light.png", darkSource: "Folders-Dark.png"),
    ThemeInput(stem: "Layers", lightSource: "Layers-Light.png", darkSource: "Layers-Dark.png"),
    ThemeInput(stem: "PhotoShelf", lightSource: "PhotoShelf-Light.png", darkSource: "PhotoShelf-Dark.png"),
    ThemeInput(stem: "Minimal", lightSource: "Minimal-Light.png", darkSource: "Minimal-Dark.png")
]

let canvasSize = 1024
let targetVisibleBounds = 880.0
let alphaThreshold: UInt8 = 8
let splitTopIntersectionX = 1024.0 * 0.67
let splitBottomIntersectionX = 1024.0 * 0.33
let regenerateAppIcons = ProcessInfo.processInfo.environment["REGENERATE_APP_ICONS"] == "1"

struct Bitmap {
    let image: CGImage
    let width: Int
    let height: Int
    let bytes: [UInt8]
}

func sourceURL(_ source: String) -> URL {
    if source.hasPrefix("/") {
        return URL(fileURLWithPath: source)
    }
    return externalRoot
        .appendingPathComponent("PNG/LightDark")
        .appendingPathComponent(source)
}

func existingLightDarkURL(stem: String, suffix: String, fallbackSource: String) -> URL {
    let existing = outputLightDark.appendingPathComponent("\(stem)-\(suffix).png")
    if FileManager.default.fileExists(atPath: existing.path) {
        return existing
    }
    return sourceURL(fallbackSource)
}

func loadImage(_ url: URL) throws -> CGImage {
    guard let nsImage = NSImage(contentsOf: url) else {
        throw NSError(domain: "IconThemeGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot load \(url.path)"])
    }
    var rect = NSRect(origin: .zero, size: nsImage.size)
    guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        throw NSError(domain: "IconThemeGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot decode \(url.path)"])
    }
    return cgImage
}

func bitmap(_ image: CGImage) throws -> Bitmap {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "IconThemeGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create bitmap context"])
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return Bitmap(image: image, width: width, height: height, bytes: bytes)
}

func alphaBounds(_ bitmap: Bitmap) -> CGRect? {
    var minX = bitmap.width
    var minY = bitmap.height
    var maxX = -1
    var maxY = -1
    for y in 0..<bitmap.height {
        for x in 0..<bitmap.width {
            let alpha = bitmap.bytes[(y * bitmap.width + x) * 4 + 3]
            if alpha > alphaThreshold {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func union(_ a: CGRect, _ b: CGRect) -> CGRect {
    a.union(b)
}

func normalizedImage(from image: CGImage, cropRect: CGRect, scale: CGFloat) throws -> CGImage {
    guard let crop = image.cropping(to: cropRect.integral) else {
        throw NSError(domain: "IconThemeGenerator", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot crop image"])
    }
    var bytes = [UInt8](repeating: 0, count: canvasSize * canvasSize * 4)
    guard let context = CGContext(
        data: &bytes,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "IconThemeGenerator", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot create output context"])
    }
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    let drawWidth = CGFloat(crop.width) * scale
    let drawHeight = CGFloat(crop.height) * scale
    let drawRect = CGRect(
        x: (CGFloat(canvasSize) - drawWidth) / 2,
        y: (CGFloat(canvasSize) - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    )
    context.draw(crop, in: drawRect)
    guard let output = context.makeImage() else {
        throw NSError(domain: "IconThemeGenerator", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot finalize output image"])
    }
    return output
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let bitmapRep = NSBitmapImageRep(cgImage: image)
    guard let data = bitmapRep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconThemeGenerator", code: 7, userInfo: [NSLocalizedDescriptionKey: "Cannot encode \(url.path)"])
    }
    try data.write(to: url, options: .atomic)
}

func validatedNonBlank(_ image: CGImage, label: String) throws {
    let bmp = try bitmap(image)
    guard let bounds = alphaBounds(bmp), bounds.width > 16, bounds.height > 16 else {
        throw NSError(domain: "IconThemeGenerator", code: 8, userInfo: [NSLocalizedDescriptionKey: "\(label) is transparent or blank"])
    }
}

func splitPreview(light: CGImage, dark: CGImage) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: canvasSize * canvasSize * 4)
    guard let context = CGContext(
        data: &bytes,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "IconThemeGenerator", code: 9, userInfo: [NSLocalizedDescriptionKey: "Cannot create split context"])
    }
    let full = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    context.interpolationQuality = .high
    context.clear(full)
    context.setBlendMode(.copy)
    context.draw(dark, in: full)
    context.saveGState()
    context.beginPath()
    context.move(to: CGPoint(x: 0.0, y: 0.0))
    context.addLine(to: CGPoint(x: 0.0, y: Double(canvasSize)))
    context.addLine(to: CGPoint(x: splitTopIntersectionX, y: Double(canvasSize)))
    context.addLine(to: CGPoint(x: splitBottomIntersectionX, y: 0.0))
    context.closePath()
    context.clip()
    context.setBlendMode(.copy)
    context.draw(light, in: full)
    context.restoreGState()
    guard let output = context.makeImage() else {
        throw NSError(domain: "IconThemeGenerator", code: 10, userInfo: [NSLocalizedDescriptionKey: "Cannot finalize split image"])
    }
    return output
}

func statusBarTemplate(sizePixels: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: sizePixels * sizePixels * 4)
    guard let context = CGContext(
        data: &bytes,
        width: sizePixels,
        height: sizePixels,
        bitsPerComponent: 8,
        bytesPerRow: sizePixels * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "IconThemeGenerator", code: 12, userInfo: [NSLocalizedDescriptionKey: "Cannot create menu bar template context"])
    }
    let scale = CGFloat(sizePixels) / 18.0
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }
    context.clear(CGRect(x: 0, y: 0, width: sizePixels, height: sizePixels))
    context.setFillColor(CGColor(gray: 0.0, alpha: 1.0))
    context.addPath(CGPath(
        roundedRect: rect(6.2, 7.1, 7.6, 7.2),
        cornerWidth: 1.6 * scale,
        cornerHeight: 1.6 * scale,
        transform: nil
    ))
    context.fillPath()
    context.addPath(CGPath(
        roundedRect: rect(3.8, 5.1, 7.8, 7.2),
        cornerWidth: 1.6 * scale,
        cornerHeight: 1.6 * scale,
        transform: nil
    ))
    context.fillPath()
    context.addPath(CGPath(
        roundedRect: rect(2.0, 2.4, 14.0, 2.8),
        cornerWidth: 1.4 * scale,
        cornerHeight: 1.4 * scale,
        transform: nil
    ))
    context.fillPath()
    guard let output = context.makeImage() else {
        throw NSError(domain: "IconThemeGenerator", code: 13, userInfo: [NSLocalizedDescriptionKey: "Cannot finalize menu bar template image"])
    }
    return output
}

func normalizedForPreview(_ image: CGImage) throws -> CGImage {
    if image.width == canvasSize, image.height == canvasSize {
        return image
    }
    let imageBitmap = try bitmap(image)
    guard let bounds = alphaBounds(imageBitmap) else {
        throw NSError(domain: "IconThemeGenerator", code: 14, userInfo: [NSLocalizedDescriptionKey: "Preview source is blank"])
    }
    let scale = targetVisibleBounds / max(bounds.width, bounds.height)
    return try normalizedImage(from: image, cropRect: bounds, scale: scale)
}

for theme in themes {
    let lightSourceURL = regenerateAppIcons
        ? sourceURL(theme.lightSource)
        : existingLightDarkURL(stem: theme.stem, suffix: "Light", fallbackSource: theme.lightSource)
    let darkSourceURL = regenerateAppIcons
        ? sourceURL(theme.darkSource)
        : existingLightDarkURL(stem: theme.stem, suffix: "Dark", fallbackSource: theme.darkSource)
    let light = try loadImage(lightSourceURL)
    let dark = try loadImage(darkSourceURL)
    let normalizedLight: CGImage
    let normalizedDark: CGImage

    if regenerateAppIcons {
        let lightBitmap = try bitmap(light)
        let darkBitmap = try bitmap(dark)
        guard let lightBounds = alphaBounds(lightBitmap), let darkBounds = alphaBounds(darkBitmap) else {
            throw NSError(domain: "IconThemeGenerator", code: 11, userInfo: [NSLocalizedDescriptionKey: "\(theme.stem) source is blank"])
        }
        let pairBounds = union(lightBounds, darkBounds)
        let scale = targetVisibleBounds / max(pairBounds.width, pairBounds.height)
        normalizedLight = try normalizedImage(from: light, cropRect: pairBounds, scale: scale)
        normalizedDark = try normalizedImage(from: dark, cropRect: pairBounds, scale: scale)
        try validatedNonBlank(normalizedLight, label: "\(theme.stem)-Light")
        try validatedNonBlank(normalizedDark, label: "\(theme.stem)-Dark")
        try writePNG(normalizedLight, to: outputLightDark.appendingPathComponent("\(theme.stem)-Light.png"))
        try writePNG(normalizedDark, to: outputLightDark.appendingPathComponent("\(theme.stem)-Dark.png"))
        print("[IconThemeGenerator] \(theme.stem) regenerated app icons from \(lightSourceURL.lastPathComponent) / \(darkSourceURL.lastPathComponent)")
    } else {
        normalizedLight = try normalizedForPreview(light)
        normalizedDark = try normalizedForPreview(dark)
        try validatedNonBlank(normalizedLight, label: "\(theme.stem)-Light preview source")
        try validatedNonBlank(normalizedDark, label: "\(theme.stem)-Dark preview source")
    }

    let split = try splitPreview(light: normalizedLight, dark: normalizedDark)
    try validatedNonBlank(split, label: "\(theme.stem)-Split")
    try writePNG(split, to: outputSplit.appendingPathComponent("\(theme.stem)-Split.png"))
    print("[IconThemeGenerator] \(theme.stem) split from \(lightSourceURL.path) + \(darkSourceURL.path)")
}

let status18 = try statusBarTemplate(sizePixels: 36)
let status36 = try statusBarTemplate(sizePixels: 72)
try validatedNonBlank(status18, label: "ShelfBarStatusTemplate-18@2x")
try validatedNonBlank(status36, label: "ShelfBarStatusTemplate-36@2x")
try writePNG(status18, to: outputMenuBar.appendingPathComponent("ShelfBarStatusTemplate-18@2x.png"))
try writePNG(status36, to: outputMenuBar.appendingPathComponent("ShelfBarStatusTemplate-36@2x.png"))
print("[IconThemeGenerator] Menu bar template assets generated in \(outputMenuBar.path)")
