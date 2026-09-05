import Carbon
import Foundation

enum ShelfBarFeature: CaseIterable, Hashable {
    case clipboardShelf
    case shelfClipboardSwitcher
    case clipboardPasteButton
    case dropCounter
    case touchBarSearch
    case quickActions
    case pinFavorites
    case recentFiles
    case airDrop

    var title: String {
        switch self {
        case .clipboardShelf: "Clipboard Shelf"
        case .shelfClipboardSwitcher: "Shelf/Clipboard Switcher"
        case .clipboardPasteButton: "Clipboard Paste Button"
        case .dropCounter: "Drop Counter"
        case .touchBarSearch: "Touch Bar Search"
        case .quickActions: "Quick Actions"
        case .pinFavorites: "Pin Favorites"
        case .recentFiles: "Recent Files"
        case .airDrop: "AirDrop"
        }
    }

    var defaultsKey: String {
        switch self {
        case .clipboardShelf: "ShelfBar.features.clipboardShelf"
        case .shelfClipboardSwitcher: "ShelfBar.features.shelfClipboardSwitcher"
        case .clipboardPasteButton: "ShelfBar.features.clipboardPasteButton"
        case .dropCounter: "ShelfBar.features.dropCounter"
        case .touchBarSearch: "ShelfBar.features.touchBarSearch"
        case .quickActions: "ShelfBar.features.quickActions"
        case .pinFavorites: "ShelfBar.features.pinFavorites"
        case .recentFiles: "ShelfBar.features.recentFiles"
        case .airDrop: "ShelfBar.features.airDrop"
        }
    }

    var defaultValue: Bool {
        true
    }

    var isImplemented: Bool {
        true
    }

    var phaseStatusNote: String {
        switch self {
        case .airDrop:
            "Implemented. Turning this off immediately removes the AirDrop zone from the Touch Bar drop target."
        case .clipboardShelf:
            "Captures recent clipboard text, links, images and file URLs into a second Touch Bar shelf."
        case .shelfClipboardSwitcher:
            "Shows a Touch Bar mode button for switching between File Shelf and Clipboard Shelf."
        case .clipboardPasteButton:
            "Shows Paste for selected Clipboard Shelf items. Paste requires Accessibility permission for automatic Command-V."
        case .dropCounter:
            "Shows live item counts for File Shelf and Clipboard Shelf."
        case .touchBarSearch:
            "Shows a magnifying glass button that opens Search directly on the Touch Bar."
        case .quickActions:
            "Adds contextual actions such as Open, Reveal, Copy, Share, Pin and Remove."
        case .pinFavorites:
            "Allows File Shelf and Clipboard Shelf items to stay pinned across clears and restarts."
        case .recentFiles:
            "Records ShelfBar activity so recent items can be searched and reopened."
        }
    }
}

struct ShelfBarFeatureSettings: Equatable {
    let clipboardShelf: Bool
    let shelfClipboardSwitcher: Bool
    let clipboardPasteButton: Bool
    let dropCounter: Bool
    let touchBarSearch: Bool
    let quickActions: Bool
    let pinFavorites: Bool
    let recentFiles: Bool
    let airDrop: Bool

    func isEnabled(_ feature: ShelfBarFeature) -> Bool {
        switch feature {
        case .clipboardShelf: clipboardShelf
        case .shelfClipboardSwitcher: shelfClipboardSwitcher
        case .clipboardPasteButton: clipboardPasteButton
        case .dropCounter: dropCounter
        case .touchBarSearch: touchBarSearch
        case .quickActions: quickActions
        case .pinFavorites: pinFavorites
        case .recentFiles: recentFiles
        case .airDrop: airDrop
        }
    }
}

enum ShelfBarSettingsKey {
    static let showFloatingAfterClose = "ShelfBar.showFloatingAfterClose"
    static let autoDissolveSingleItemStack = "ShelfBar.autoDissolveSingleItemStack"
    static let showInDock = "ShelfBar.showInDock"
    static let floatingOpenAnimation = "ShelfBar.floatingOpenAnimation"
    static let theme = "ShelfBar.theme"
    static let iconTheme = ShelfBarIconTheme.defaultsKey
    static let showDeveloperTab = "ShelfBar.showDeveloperTab"
    static let legacyEnableAirDropZone = "ShelfBar.enableAirDropZone"
    static let airDropFeatureMigrationComplete = "ShelfBar.migrations.airDropFeature.v1"
    static let maxClipboardHistory = "ShelfBar.clipboard.maxHistory"
    static let captureClipboardText = "ShelfBar.clipboard.captureText"
    static let captureClipboardURLs = "ShelfBar.clipboard.captureURLs"
    static let captureClipboardImages = "ShelfBar.clipboard.captureImages"
    static let captureClipboardFiles = "ShelfBar.clipboard.captureFiles"
    static let showDropCounterTotalSize = "ShelfBar.dropCounter.showTotalSize"
    static let recentFilesLimit = "ShelfBar.recent.limit"
    static let openShelfShortcutKeyCode = "ShelfBar.shortcut.openShelf.keyCode"
    static let openShelfShortcutModifiers = "ShelfBar.shortcut.openShelf.modifiers"
}

struct ShelfBarKeyboardShortcut: Equatable {
    static let defaultKeyCode: UInt32 = 8
    static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)

    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = ShelfBarKeyboardShortcut(
        keyCode: defaultKeyCode,
        modifiers: defaultModifiers
    )

    var isEmpty: Bool {
        keyCode == 0 && modifiers == 0
    }

    var displayText: String {
        guard !isEmpty else { return "None" }
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.displayName(for: keyCode))
        return parts.joined()
    }

    static func displayName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        default: return "Key \(keyCode)"
        }
    }
}

@MainActor
final class AppSettingsStore {
    enum Change {
        case feature(ShelfBarFeature, Bool)
        case general(String)
    }

    private let defaults: UserDefaults
    var onChange: ((Change) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateLegacySettings()
        registerDefaults()
    }

    var features: ShelfBarFeatureSettings {
        ShelfBarFeatureSettings(
            clipboardShelf: isFeatureEnabled(.clipboardShelf),
            shelfClipboardSwitcher: isFeatureEnabled(.shelfClipboardSwitcher),
            clipboardPasteButton: isFeatureEnabled(.clipboardPasteButton),
            dropCounter: isFeatureEnabled(.dropCounter),
            touchBarSearch: isFeatureEnabled(.touchBarSearch),
            quickActions: isFeatureEnabled(.quickActions),
            pinFavorites: isFeatureEnabled(.pinFavorites),
            recentFiles: isFeatureEnabled(.recentFiles),
            airDrop: isFeatureEnabled(.airDrop)
        )
    }

    var showFloatingAfterClose: Bool {
        bool(forKey: ShelfBarSettingsKey.showFloatingAfterClose, defaultValue: true)
    }

    var autoDissolveSingleItemStack: Bool {
        bool(forKey: ShelfBarSettingsKey.autoDissolveSingleItemStack, defaultValue: true)
    }

    var showInDock: Bool {
        bool(forKey: ShelfBarSettingsKey.showInDock, defaultValue: false)
    }

    var maxClipboardHistory: Int {
        int(forKey: ShelfBarSettingsKey.maxClipboardHistory, defaultValue: 20, allowed: [10, 20, 50, 100])
    }

    var captureClipboardText: Bool {
        bool(forKey: ShelfBarSettingsKey.captureClipboardText, defaultValue: true)
    }

    var captureClipboardURLs: Bool {
        bool(forKey: ShelfBarSettingsKey.captureClipboardURLs, defaultValue: true)
    }

    var captureClipboardImages: Bool {
        bool(forKey: ShelfBarSettingsKey.captureClipboardImages, defaultValue: true)
    }

    var captureClipboardFiles: Bool {
        bool(forKey: ShelfBarSettingsKey.captureClipboardFiles, defaultValue: true)
    }

    var showDropCounterTotalSize: Bool {
        bool(forKey: ShelfBarSettingsKey.showDropCounterTotalSize, defaultValue: false)
    }

    var recentFilesLimit: Int {
        int(forKey: ShelfBarSettingsKey.recentFilesLimit, defaultValue: 10, allowed: [5, 10, 20, 50])
    }

    var openShelfShortcut: ShelfBarKeyboardShortcut {
        let keyCode = defaults.object(forKey: ShelfBarSettingsKey.openShelfShortcutKeyCode) as? Int
            ?? Int(ShelfBarKeyboardShortcut.defaultKeyCode)
        let modifiers = defaults.object(forKey: ShelfBarSettingsKey.openShelfShortcutModifiers) as? Int
            ?? Int(ShelfBarKeyboardShortcut.defaultModifiers)
        return ShelfBarKeyboardShortcut(keyCode: UInt32(max(keyCode, 0)), modifiers: UInt32(max(modifiers, 0)))
    }

    func isFeatureEnabled(_ feature: ShelfBarFeature) -> Bool {
        bool(forKey: feature.defaultsKey, defaultValue: feature.defaultValue)
    }

    func setFeature(_ feature: ShelfBarFeature, enabled: Bool) {
        guard isFeatureEnabled(feature) != enabled else { return }
        defaults.set(enabled, forKey: feature.defaultsKey)
        if feature == .airDrop {
            defaults.set(enabled, forKey: ShelfBarSettingsKey.legacyEnableAirDropZone)
        }
        onChange?(.feature(feature, enabled))
    }

    func setShowFloatingAfterClose(_ enabled: Bool) {
        setBool(enabled, forKey: ShelfBarSettingsKey.showFloatingAfterClose)
    }

    func setAutoDissolveSingleItemStack(_ enabled: Bool) {
        setBool(enabled, forKey: ShelfBarSettingsKey.autoDissolveSingleItemStack)
    }

    func setShowInDock(_ enabled: Bool) {
        setBool(enabled, forKey: ShelfBarSettingsKey.showInDock)
    }

    func setMaxClipboardHistory(_ value: Int) {
        setInt(value, forKey: ShelfBarSettingsKey.maxClipboardHistory)
    }

    func setCaptureClipboardText(_ enabled: Bool) {
        setBool(enabled, forKey: ShelfBarSettingsKey.captureClipboardText)
    }

    func setCaptureClipboardURLs(_ enabled: Bool) {
        setBool(enabled, forKey: ShelfBarSettingsKey.captureClipboardURLs)
    }

    func setCaptureClipboardImages(_ enabled: Bool) {
        setBool(enabled, forKey: ShelfBarSettingsKey.captureClipboardImages)
    }

    func setCaptureClipboardFiles(_ enabled: Bool) {
        setBool(enabled, forKey: ShelfBarSettingsKey.captureClipboardFiles)
    }

    func setShowDropCounterTotalSize(_ enabled: Bool) {
        setBool(enabled, forKey: ShelfBarSettingsKey.showDropCounterTotalSize)
    }

    func setRecentFilesLimit(_ value: Int) {
        setInt(value, forKey: ShelfBarSettingsKey.recentFilesLimit)
    }

    func setOpenShelfShortcut(_ shortcut: ShelfBarKeyboardShortcut) {
        let old = openShelfShortcut
        guard old != shortcut else { return }
        defaults.set(Int(shortcut.keyCode), forKey: ShelfBarSettingsKey.openShelfShortcutKeyCode)
        defaults.set(Int(shortcut.modifiers), forKey: ShelfBarSettingsKey.openShelfShortcutModifiers)
        onChange?(.general(ShelfBarSettingsKey.openShelfShortcutKeyCode))
    }

    func restoreDefaultOpenShelfShortcut() {
        setOpenShelfShortcut(.default)
    }

    func clearOpenShelfShortcut() {
        setOpenShelfShortcut(ShelfBarKeyboardShortcut(keyCode: 0, modifiers: 0))
    }

    func setFloatingOpenAnimationInstant() {
        defaults.set("instant", forKey: ShelfBarSettingsKey.floatingOpenAnimation)
        onChange?(.general(ShelfBarSettingsKey.floatingOpenAnimation))
    }

    func setShowDeveloperTab(_ visible: Bool) {
        setBool(visible, forKey: ShelfBarSettingsKey.showDeveloperTab)
    }

    private func setBool(_ enabled: Bool, forKey key: String) {
        guard bool(forKey: key, defaultValue: false) != enabled else { return }
        defaults.set(enabled, forKey: key)
        onChange?(.general(key))
    }

    private func setInt(_ value: Int, forKey key: String) {
        guard defaults.integer(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        onChange?(.general(key))
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func int(forKey key: String, defaultValue: Int, allowed: Set<Int>) -> Int {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        let value = defaults.integer(forKey: key)
        return allowed.contains(value) ? value : defaultValue
    }

    private func registerDefaults() {
        var registration: [String: Any] = [
            ShelfBarSettingsKey.showFloatingAfterClose: true,
            ShelfBarSettingsKey.autoDissolveSingleItemStack: true,
            ShelfBarSettingsKey.showInDock: false,
            ShelfBarSettingsKey.floatingOpenAnimation: "instant",
            ShelfBarSettingsKey.theme: "auto",
            ShelfBarSettingsKey.iconTheme: ShelfBarIconTheme.default.rawValue,
            ShelfBarSettingsKey.showDeveloperTab: false,
            ShelfBarSettingsKey.legacyEnableAirDropZone: true,
            ShelfBarSettingsKey.maxClipboardHistory: 20,
            ShelfBarSettingsKey.captureClipboardText: true,
            ShelfBarSettingsKey.captureClipboardURLs: true,
            ShelfBarSettingsKey.captureClipboardImages: true,
            ShelfBarSettingsKey.captureClipboardFiles: true,
            ShelfBarSettingsKey.showDropCounterTotalSize: false,
            ShelfBarSettingsKey.recentFilesLimit: 10
        ]
        for feature in ShelfBarFeature.allCases {
            registration[feature.defaultsKey] = feature.defaultValue
        }
        defaults.register(defaults: registration)
    }

    private func migrateLegacySettings() {
        guard !defaults.bool(forKey: ShelfBarSettingsKey.airDropFeatureMigrationComplete) else {
            return
        }
        if defaults.object(forKey: ShelfBarSettingsKey.legacyEnableAirDropZone) != nil {
            defaults.set(
                defaults.bool(forKey: ShelfBarSettingsKey.legacyEnableAirDropZone),
                forKey: ShelfBarFeature.airDrop.defaultsKey
            )
        }
        defaults.set(true, forKey: ShelfBarSettingsKey.airDropFeatureMigrationComplete)
    }

}
