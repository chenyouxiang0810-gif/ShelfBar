import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettingsStore()
    private let shelf = FileShelfModel()
    private let stacks = ShelfStackModel()
    private lazy var clipboardStore = ClipboardStore(settings: settings)
    private lazy var favoritesStore = FavoritesStore()
    private lazy var recentItemsStore = RecentItemsStore(settings: settings)
    private lazy var privateTouchBarController = PrivateTouchBarController(
        shelf: shelf,
        stacks: stacks,
        settings: settings,
        clipboardStore: clipboardStore,
        favoritesStore: favoritesStore,
        recentItemsStore: recentItemsStore
    )
    private let mouseBridgeResearchController = MouseBridgeResearchController()
    private var debugWindowController: DebugWindowController?
    private var overlayController: ScreenEdgeDropOverlayController?
    private var finderDragMonitor: FinderDragMonitor?
    private var menuBarController: MenuBarController?
    private var globalHotKeyController: GlobalHotKeyController?
    private var appearanceObservation: NSKeyValueObservation?
    private var lastAppearanceRefreshKey: String?
    private var workspaceNotificationTokens: [NSObjectProtocol] = []
    private var commandFMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let recoveredStackItems = stacks.normalize(
            autoDissolveSingle: settings.autoDissolveSingleItemStack
        )
        if !recoveredStackItems.isEmpty {
            shelf.add(existingItems: recoveredStackItems)
        }
        let showInDock = settings.showInDock
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        ShelfBarIconTheme.updateApplicationIcon()
        let overlayController = ScreenEdgeDropOverlayController(
            delegate: privateTouchBarController
        )
        overlayController.isAirDropEnabledProvider = { [weak settings] in
            settings?.isFeatureEnabled(.airDrop) ?? true
        }
        privateTouchBarController.setMouseBridgeHeightInPixels(
            overlayController.heightInPixels
        )
        let debugWindowController = DebugWindowController(
            touchBarController: privateTouchBarController,
            overlayController: overlayController,
            mouseBridgeResearchController: mouseBridgeResearchController,
            stacks: stacks,
            settings: settings,
            clipboardStore: clipboardStore,
            favoritesStore: favoritesStore,
            recentItemsStore: recentItemsStore
        )
        settings.onChange = { [weak self, weak privateTouchBarController, weak debugWindowController] change in
            privateTouchBarController?.settingsDidChange(change)
            debugWindowController?.settingsDidChange(change)
            self?.menuBarController?.settingsDidChange(change)
            self?.clipboardStore.settingsDidChange(change)
            self?.recentItemsStore.settingsDidChange(change)
            self?.globalHotKeyController?.settingsDidChange(change)
        }
        clipboardStore.bootstrapCurrentPasteboard(reason: "app-launch")
        let finderDragMonitor = FinderDragMonitor(overlayController: overlayController)
        finderDragMonitor.onFileDragDetected = { [weak privateTouchBarController] in
            privateTouchBarController?.finderFileDragDetected()
        }
        finderDragMonitor.onFileDragEnded = { [weak privateTouchBarController] in
            privateTouchBarController?.finderFileDragEnded()
        }
        self.overlayController = overlayController
        self.debugWindowController = debugWindowController
        self.finderDragMonitor = finderDragMonitor
        let menuBarController = MenuBarController(
            shelfController: privateTouchBarController,
            overlayController: overlayController,
            windowController: debugWindowController,
            settings: settings
        )
        self.menuBarController = menuBarController
        let globalHotKeyController = GlobalHotKeyController(settings: settings)
        globalHotKeyController.onOpenShelf = { [weak privateTouchBarController] in
            privateTouchBarController?.presentSystemModalFromShortcut()
        }
        globalHotKeyController.start()
        self.globalHotKeyController = globalHotKeyController
        debugWindowController.onDockPreferenceChange = { [weak self] enabled in
            self?.setDockVisibility(enabled)
        }

        commandFMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak privateTouchBarController] event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                privateTouchBarController?.beginSearch()
                return nil
            }
            return event
        }

        mouseBridgeResearchController.fileURLProvider = { [weak shelf] in
            shelf?.items.first?.url
        }
        mouseBridgeResearchController.onModeChange = {
            [weak finderDragMonitor, weak privateTouchBarController] enabled in
            if enabled {
                finderDragMonitor?.stop()
                privateTouchBarController?.dismissSystemModal()
            } else {
                finderDragMonitor?.start()
            }
        }

        finderDragMonitor.start()
        if showInDock {
            debugWindowController.openPreferences(page: 0)
        }
        configureAppearanceObservation()
        configureSessionNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseBridgeResearchController.onModeChange = nil
        mouseBridgeResearchController.setEnabled(false)
        finderDragMonitor?.stop()
        if let commandFMonitor {
            NSEvent.removeMonitor(commandFMonitor)
            self.commandFMonitor = nil
        }
        appearanceObservation?.invalidate()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceNotificationTokens.forEach { workspaceCenter.removeObserver($0) }
        workspaceNotificationTokens.removeAll()
        privateTouchBarController.dismissSystemModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setDockVisibility(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible {
            debugWindowController?.openPreferences(page: 0)
        }
    }

    private func configureAppearanceObservation() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshResolvedAppearance(reason: "effectiveAppearance")
            }
        }
    }

    private func refreshResolvedAppearance(reason: String) {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let themeMode = UserDefaults.standard.string(forKey: ShelfBarSettingsKey.theme) ?? "auto"
        let key = "\(themeMode):\(ShelfBarIconTheme.current.rawValue):\(dark ? "dark" : "light")"
        guard lastAppearanceRefreshKey != key else { return }
        lastAppearanceRefreshKey = key
        print("[ShelfBar] appearance refresh reason=\(reason) key=\(key)")
        ShelfBarIconTheme.updateApplicationIcon()
        menuBarController?.appearanceDidChange()
        debugWindowController?.appearanceDidChange()
        privateTouchBarController.appearanceDidChange()
    }

    private func configureSessionNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        let resign = center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.privateTouchBarController.setSessionActive(
                    false,
                    reason: notification.name.rawValue
                )
            }
        }
        let become = center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.privateTouchBarController.setSessionActive(
                    true,
                    reason: notification.name.rawValue
                )
            }
        }
        workspaceNotificationTokens = [resign, become]
    }
}
