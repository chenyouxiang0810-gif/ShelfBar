import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shelf = FileShelfModel()
    private let stacks = ShelfStackModel()
    private lazy var privateTouchBarController = PrivateTouchBarController(shelf: shelf, stacks: stacks)
    private let mouseBridgeResearchController = MouseBridgeResearchController()
    private var debugWindowController: DebugWindowController?
    private var overlayController: ScreenEdgeDropOverlayController?
    private var finderDragMonitor: FinderDragMonitor?
    private var menuBarController: MenuBarController?
    private var floatingShelfButtonController: FloatingShelfButtonController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "ShelfBar.showFloatingAfterClose": true,
            "ShelfBar.autoDissolveSingleItemStack": true,
            "ShelfBar.enableAirDropZone": true,
            "ShelfBar.floatingOpenAnimation": "instant"
        ])
        let recoveredStackItems = stacks.normalize(
            autoDissolveSingle: UserDefaults.standard.bool(
                forKey: "ShelfBar.autoDissolveSingleItemStack"
            )
        )
        if !recoveredStackItems.isEmpty {
            shelf.add(existingItems: recoveredStackItems)
        }
        let showInDock = UserDefaults.standard.bool(forKey: "ShelfBar.showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if let icon = shelfBarBrandImage(for: NSApp.effectiveAppearance) {
            NSApp.applicationIconImage = icon
        }
        let overlayController = ScreenEdgeDropOverlayController(
            delegate: privateTouchBarController
        )
        privateTouchBarController.setMouseBridgeHeightInPixels(
            overlayController.heightInPixels
        )
        let debugWindowController = DebugWindowController(
            touchBarController: privateTouchBarController,
            overlayController: overlayController,
            mouseBridgeResearchController: mouseBridgeResearchController,
            stacks: stacks
        )
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
            windowController: debugWindowController
        )
        self.menuBarController = menuBarController
        let floatingShelfButtonController = FloatingShelfButtonController()
        floatingShelfButtonController.onPresentShelf = { [weak privateTouchBarController] in
            privateTouchBarController?.presentSystemModal()
        }
        floatingShelfButtonController.onShowApp = { [weak debugWindowController] in
            debugWindowController?.openPreferences(page: 0)
        }
        privateTouchBarController.onUserClosedShelf = { [weak floatingShelfButtonController] in
            guard UserDefaults.standard.bool(forKey: "ShelfBar.showFloatingAfterClose") else {
                return
            }
            floatingShelfButtonController?.show()
        }
        privateTouchBarController.onShelfPresented = { [weak floatingShelfButtonController] in
            floatingShelfButtonController?.hide()
        }
        debugWindowController.onFloatingButtonPreferenceChange = {
            [weak floatingShelfButtonController] enabled in
            if !enabled {
                floatingShelfButtonController?.hide()
            }
        }
        self.floatingShelfButtonController = floatingShelfButtonController
        debugWindowController.onDockPreferenceChange = { [weak self] enabled in
            self?.setDockVisibility(enabled)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseBridgeResearchController.onModeChange = nil
        mouseBridgeResearchController.setEnabled(false)
        finderDragMonitor?.stop()
        floatingShelfButtonController?.hide()
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
}
