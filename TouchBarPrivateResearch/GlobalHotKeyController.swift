import Carbon
import AppKit
import Foundation

@MainActor
final class GlobalHotKeyController {
    private static var activeController: GlobalHotKeyController?
    private let settings: AppSettingsStore
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var registeredShortcut: ShelfBarKeyboardShortcut?
    var onOpenShelf: (() -> Void)?

    init(settings: AppSettingsStore) {
        self.settings = settings
        Self.activeController = self
    }

    func start() {
        installHandlerIfNeeded()
        registerFromSettings(restorePreviousOnFailure: false)
    }

    func settingsDidChange(_ change: AppSettingsStore.Change) {
        guard case let .general(key) = change,
              key == ShelfBarSettingsKey.openShelfShortcutKeyCode
        else { return }
        registerFromSettings(restorePreviousOnFailure: true)
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard id.signature == GlobalHotKeyController.signature else { return noErr }
                Task { @MainActor in
                    GlobalHotKeyController.activeController?.onOpenShelf?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
        if status != noErr {
            print("[ShelfBar.HotKey] InstallEventHandler failed status=\(status)")
        }
    }

    private func registerFromSettings(restorePreviousOnFailure: Bool) {
        let shortcut = settings.openShelfShortcut
        let previous = registeredShortcut
        unregister()
        guard !shortcut.isEmpty else {
            registeredShortcut = nil
            print("[ShelfBar.HotKey] Open Shelf shortcut cleared")
            return
        }

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            print("[ShelfBar.HotKey] Register failed shortcut=\(shortcut.displayText) status=\(status)")
            if restorePreviousOnFailure, let previous {
                settings.setOpenShelfShortcut(previous)
            }
            showConflictAlert(shortcut: shortcut)
            return
        }
        hotKeyRef = ref
        registeredShortcut = shortcut
        print("[ShelfBar.HotKey] Registered Open Shelf shortcut=\(shortcut.displayText)")
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func showConflictAlert(shortcut: ShelfBarKeyboardShortcut) {
        let alert = NSAlert()
        alert.messageText = "Shortcut unavailable"
        alert.informativeText = "\(shortcut.displayText) is already in use or could not be registered. ShelfBar kept the previous shortcut."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static let signature: OSType = {
        "ShFB".utf8.reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }()
}
