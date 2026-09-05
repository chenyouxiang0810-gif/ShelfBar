import AppKit
import ApplicationServices

@MainActor
final class CenterExpandPillView: NSView {
    private var widthConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        layer?.shadowColor = NSColor.controlAccentColor.cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius = 8
        layer?.shadowOffset = .zero

        widthConstraint = widthAnchor.constraint(equalToConstant: 34)
        NSLayoutConstraint.activate([
            widthConstraint,
            heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func expand(completion: @escaping () -> Void) {
        layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            widthConstraint.animator().constant = 520
            layer?.shadowOpacity = 0.30
            layoutSubtreeIfNeeded()
        } completionHandler: {
            DispatchQueue.main.async(execute: completion)
        }
    }
}

@MainActor
private final class NativeTouchBarButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class MainShelfLayoutProbeView: NSView {
    enum Event: String {
        case movedToWindow = "viewDidMoveToWindow"
        case firstLayoutPass = "first-layout-pass"
    }

    let route: String
    let serial: Int
    private var didLogFirstLayout = false
    private let handler: (Event, MainShelfLayoutProbeView) -> Void

    init(route: String, serial: Int, handler: @escaping (Event, MainShelfLayoutProbeView) -> Void) {
        self.route = route
        self.serial = serial
        self.handler = handler
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        handler(.movedToWindow, self)
    }

    override func layout() {
        super.layout()
        guard !didLogFirstLayout else { return }
        didLogFirstLayout = true
        handler(.firstLayoutPass, self)
    }
}

@MainActor
private final class ShelfInteractionCoordinator {
    enum Target: Equatable {
        case shelf
        case action
        case inactive
    }

    struct Request {
        let target: Target
        let mode: String
        let reason: String
    }

    private let shelfBridge: ShelfMouseBridgeController
    private let actionBridge: ActionMenuMouseBridgeController
    private let resetVisibleState: (String) -> Void
    private let parentView: () -> NSView?
    private let log: (String) -> Void
    private var activeTarget: Target = .inactive
    private var syncCount = 0

    init(
        shelfBridge: ShelfMouseBridgeController,
        actionBridge: ActionMenuMouseBridgeController,
        resetVisibleState: @escaping (String) -> Void,
        parentView: @escaping () -> NSView?,
        log: @escaping (String) -> Void
    ) {
        self.shelfBridge = shelfBridge
        self.actionBridge = actionBridge
        self.resetVisibleState = resetVisibleState
        self.parentView = parentView
        self.log = log
    }

    func synchronize(_ request: Request) {
        syncCount += 1
        let changedTarget = request.target != activeTarget
        if changedTarget {
            resetVisibleState("target-change:\(activeTarget)->\(request.target):\(request.reason)")
        }
        switch request.target {
        case .shelf:
            actionBridge.dismiss()
            shelfBridge.present(mode: request.mode)
        case .action:
            shelfBridge.dismiss()
            actionBridge.present()
        case .inactive:
            shelfBridge.dismiss()
            actionBridge.dismiss()
        }
        activeTarget = request.target
        logCounters(reason: request.reason, mode: request.mode, changedTarget: changedTarget)
    }

    func resetForTouchBarRebuild(reason: String) {
        resetVisibleState("rebuild:\(reason)")
        shelfBridge.resetTransientInteractionState(reason: "rebuild:\(reason)")
        actionBridge.resetTransientInteractionState(reason: "rebuild:\(reason)")
    }

    func dumpState(reason: String, mode: String) {
        logCounters(reason: reason, mode: mode, changedTarget: false)
    }

    private func logCounters(reason: String, mode: String, changedTarget: Bool) {
        let parent = parentView()
        log(
            "InteractionCoordinator sync=\(syncCount) target=\(activeTarget) "
                + "mode=\(mode) changedTarget=\(changedTarget) reason=\(reason) "
                + shelfBridge.debugStateSummary(parentView: parent) + " | "
                + actionBridge.debugStateSummary(parentView: parent)
        )
    }
}

@MainActor
final class PrivateTouchBarController: NSObject,
    NSTouchBarDelegate,
    NSScrubberDataSource,
    NSScrubberDelegate,
    NSSearchFieldDelegate,
    OverlayDropDelegate,
    ShelfScrubberItemViewTouchReorderDelegate,
    ShelfMouseBridgeDelegate {

    enum AutoDropStatus: String {
        case idle = "Idle"
        case dragDetected = "Drag detected"
        case dropReady = "Drop ready"
        case dropSuccess = "Drop success"
        case shelfActive = "Shelf active"
    }

    private enum ItemID {
        static let dropHere = NSTouchBarItem.Identifier("com.prototype.TouchBarPrivateResearch.dropHere")
        static let shelf = NSTouchBarItem.Identifier("com.prototype.TouchBarPrivateResearch.shelf")
        static let stackShelf = NSTouchBarItem.Identifier("com.shelfbar.stackShelf")
        static let clear = NSTouchBarItem.Identifier("com.prototype.TouchBarPrivateResearch.clear")
        static let close = NSTouchBarItem.Identifier("com.prototype.TouchBarPrivateResearch.close")
        static let operationActions = NSTouchBarItem.Identifier("com.shelfbar.operationActions")
        static let stackBack = NSTouchBarItem.Identifier("com.shelfbar.stackBack")
        static let stackTitle = NSTouchBarItem.Identifier("com.shelfbar.stackTitle")
        static let centerExpand = NSTouchBarItem.Identifier("com.shelfbar.centerExpand")
        static let modeSwitcher = NSTouchBarItem.Identifier("com.shelfbar.modeSwitcher")
        static let counter = NSTouchBarItem.Identifier("com.shelfbar.counter")
        static let recent = NSTouchBarItem.Identifier("com.shelfbar.recent")
        static let search = NSTouchBarItem.Identifier("com.shelfbar.search")
        static let searchField = NSTouchBarItem.Identifier("com.shelfbar.searchField")
        static let searchCancel = NSTouchBarItem.Identifier("com.shelfbar.searchCancel")
        static let searchClear = NSTouchBarItem.Identifier("com.shelfbar.searchClear")
        static let mainLayout = NSTouchBarItem.Identifier("com.shelfbar.mainLayout")
        static let stackRename = NSTouchBarItem.Identifier("com.shelfbar.stackRename")
        static let stackUnstack = NSTouchBarItem.Identifier("com.shelfbar.stackUnstack")
        static let renameCancel = NSTouchBarItem.Identifier("com.shelfbar.renameCancel")
        static let renameField = NSTouchBarItem.Identifier("com.shelfbar.renameField")
        static let renameSave = NSTouchBarItem.Identifier("com.shelfbar.renameSave")
    }

    private enum ShelfMode {
        case file
        case clipboard
        case recent
    }

    private enum TouchBarMetrics {
        static let rowHeight: CGFloat = 30
        static let maxImageHeight: CGFloat = 28
    }

    private enum RootDisplayEntry {
        case file(FileShelfItem)
        case stack(ShelfStack)
        case pinDivider

        var id: UUID {
            switch self {
            case let .file(item): item.id
            case let .stack(stack): stack.id
            case .pinDivider: UUID(uuidString: "00000000-0000-4000-8000-000000000013")!
            }
        }

        var orderKey: String {
            switch self {
            case let .file(item): "file:\(item.id.uuidString)"
            case let .stack(stack): "stack:\(stack.id.uuidString)"
            case .pinDivider: "pin-divider"
            }
        }

        var isDivider: Bool {
            if case .pinDivider = self { return true }
            return false
        }
    }

    private enum StackDisplayEntry {
        case file(FileShelfItem)
        case stack(ShelfStack)

        var id: UUID {
            switch self {
            case let .file(item): item.id
            case let .stack(stack): stack.id
            }
        }
    }

    private static let scrubberItemIdentifier = NSUserInterfaceItemIdentifier(
        "com.prototype.TouchBarPrivateResearch.shelfItem"
    )
    private static let rootItemOrderKey = "ShelfBar.rootItemOrder.v1"

    let touchBar = NSTouchBar()
    let shelf: FileShelfModel
    let stacks: ShelfStackModel
    private let settings: AppSettingsStore
    private let clipboardStore: ClipboardStore
    private let favoritesStore: FavoritesStore
    private let recentItemsStore: RecentItemsStore
    var onShelfChange: (([FileShelfItem]) -> Void)?
    var onStacksChange: (([ShelfStack]) -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onDeveloperLogEntry: ((String) -> Void)?
    var onUserClosedShelf: (() -> Void)?
    var onShelfPresented: (() -> Void)?
    var onShelfScrollOffsetChange: ((CGFloat) -> Void)?

    private weak var scrubber: NSScrubber?
    private weak var operationIconImageView: NSImageView?
    private lazy var shelfMouseBridgeController = ShelfMouseBridgeController(delegate: self)
    private lazy var actionMenuMouseBridgeController = ActionMenuMouseBridgeController {
        [weak self] message in
        self?.shelfMouseBridgeDidLog(message)
    }
    private lazy var interactionCoordinator = ShelfInteractionCoordinator(
        shelfBridge: shelfMouseBridgeController,
        actionBridge: actionMenuMouseBridgeController,
        resetVisibleState: { [weak self] reason in
            self?.resetVisibleInteractionState(reason: reason)
        },
        parentView: {
            NSFunctionRow._topLevelViews().last
        },
        log: { [weak self] message in
            self?.shelfMouseBridgeDidLog(message)
        }
    )
    private var selectedOperationItemID: UUID?
    private var selectedClipboardOperationItemID: UUID?
    private(set) var currentStackID: UUID?
    private var stackNavigationPath: [UUID] = []
    private var renderedStackItemIDs: Set<UUID> = []
    private var isShowingDropTarget = false
    private var currentDragDidDrop = false
    private var pendingDragDismiss: DispatchWorkItem?
    private var contentRefreshWorkItem: DispatchWorkItem?
    private var thumbnailObserver: NSObjectProtocol?
    private var fallbackShelfScrollOffset: CGFloat = 0
    private var activeDropZone: ShelfDropZone = .none
    private var isCenterExpandOpening = false
    private var shelfMode: ShelfMode = .file
    private var isSearchMode = false
    private var searchQuery = ""
    private var searchResults: [ShelfSearchResult] = []
    private weak var activeSearchDisplay: NSTextField?
    private var detailReturnToSearch = false
    private var searchReturnAnchorResultID: UUID?
    private var searchReturnStackID: UUID?
    private var searchReturnStackNavigationPath: [UUID] = []
    private var transientOperationItem: FileShelfItem?
    private var transientClipboardOperationItem: ClipboardShelfItem?
    private lazy var searchInputHost: SearchInputHost = {
        let host = SearchInputHost()
        host.onChange = { [weak self] query in
            self?.applySearchQuery(query)
        }
        return host
    }()
    private var isRenamingStack = false
    private var renameStackID: UUID?
    private var renameDraft = ""
    private weak var activeRenameDisplay: NSTextField?
    private lazy var renameInputHost: SearchInputHost = {
        let host = SearchInputHost()
        host.onChange = { [weak self] value in
            self?.applyRenameDraft(value)
        }
        host.onCommand = { [weak self] selector in
            if selector == #selector(NSResponder.insertNewline(_:)) {
                self?.saveStackRenamePressed()
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                self?.cancelStackRenamePressed()
                return true
            }
            return false
        }
        return host
    }()
    private var shelfModeBeforeSearch: ShelfMode = .file
    private(set) var isPresented = false
    private(set) var currentStatus = AutoDropStatus.idle.rawValue
    private var isSessionActive = true
    private var shouldRestoreAfterSessionActive = false
    private var pendingMainAttachRoute: String?
    private var hasRenderedRootMainLayout = false
    private var mainLayoutRenderSerial = 0
    private var mainLayoutRenderStartTimes: [Int: TimeInterval] = [:]
    private var lastMainLayoutFirstPassDescription = "none"
    private weak var shelfScrollView: NSScrollView?
    private var isTouchReorderGestureInProgress = false
    private var suppressNativeSelectionUntil: TimeInterval = 0

    init(
        shelf: FileShelfModel,
        stacks: ShelfStackModel,
        settings: AppSettingsStore,
        clipboardStore: ClipboardStore,
        favoritesStore: FavoritesStore,
        recentItemsStore: RecentItemsStore
    ) {
        self.shelf = shelf
        self.stacks = stacks
        self.settings = settings
        self.clipboardStore = clipboardStore
        self.favoritesStore = favoritesStore
        self.recentItemsStore = recentItemsStore
        super.init()
        touchBar.delegate = self
        refreshTouchBarItems()
        shelf.onChange = { [weak self] items in
            self?.shelfDidChange(items)
        }
        shelf.onThumbnailChange = { [weak self] indexes in
            self?.shelfThumbnailDidChange(indexes: indexes)
        }
        stacks.onChange = { [weak self] stacks in
            self?.stacksDidChange(stacks)
        }
        clipboardStore.onChange = { [weak self] _ in
            self?.clipboardDidChange()
        }
        favoritesStore.onChange = { [weak self] in
            self?.favoritesDidChange()
        }
        recentItemsStore.onChange = { [weak self] _ in
            self?.recentDidChange()
        }
        thumbnailObserver = NotificationCenter.default.addObserver(
            forName: .shelfBarThumbnailReady,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor [weak self] in
                self?.stackThumbnailDidChange(url: url)
            }
        }
    }

    func presentSystemModal() {
        guard isSessionActive else {
            shelfMouseBridgeDidLog("present ignored | reason=session inactive")
            return
        }
        isCenterExpandOpening = false
        currentStackID = nil
        stackNavigationPath.removeAll()
        renderedStackItemIDs.removeAll()
        isShowingDropTarget = false
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        clearTransientDetail()
        detailReturnToSearch = false
        isSearchMode = false
        searchInputHost.end()
        endStackRename()
        pendingMainAttachRoute = hasRenderedRootMainLayout ? "root-main-reopen" : "first-root-main-render"
        refreshTouchBarItems()
        ensureSystemModalPresented()
        updateMouseBridgeState()
        schedulePostRenderMouseBridgeRefresh(reason: "present main shelf")
        setStatus(mainItemCount == 0 ? .dropReady : .shelfActive)
    }

    func presentSystemModalFromShortcut() {
        presentSystemModal()
        if mainItemCount == 0, shelfMode == .file {
            shelfMouseBridgeDidLog("empty shortcut Shelf opened and kept visible")
        }
    }

    func presentSystemModalWithCenterExpand() {
        guard isSessionActive else {
            shelfMouseBridgeDidLog("center expand ignored | reason=session inactive")
            return
        }
        pendingDragDismiss?.cancel()
        pendingDragDismiss = nil
        isShowingDropTarget = false
        activeDropZone = .none
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        clearTransientDetail()
        detailReturnToSearch = false
        isSearchMode = false
        searchInputHost.end()
        endStackRename()
        currentStackID = nil
        stackNavigationPath.removeAll()
        renderedStackItemIDs.removeAll()
        isCenterExpandOpening = true
        refreshTouchBarItems()
        ensureSystemModalPresented()
        setStatus(mainItemCount == 0 ? .dropReady : .shelfActive)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let view = self.touchBar.item(forIdentifier: ItemID.centerExpand)?.view
                as? CenterExpandPillView {
                view.expand { [weak self] in
                    self?.finishCenterExpandOpening()
                }
            } else {
                self.finishCenterExpandOpening()
            }
        }
    }

    func dismissSystemModal() {
        pendingDragDismiss?.cancel()
        pendingDragDismiss = nil
        contentRefreshWorkItem?.cancel()
        contentRefreshWorkItem = nil
        isShowingDropTarget = false
        activeDropZone = .none
        isCenterExpandOpening = false
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        clearTransientDetail()
        detailReturnToSearch = false
        isSearchMode = false
        searchInputHost.end()
        endStackRename()
        currentStackID = nil
        stackNavigationPath.removeAll()
        renderedStackItemIDs.removeAll()
        shelfMouseBridgeController.dismiss()
        actionMenuMouseBridgeController.dismiss()
        refreshTouchBarItems()
        if isPresented {
            print("[ShelfBar] dismissing system-modal Touch Bar")
            NSTouchBar.dismissSystemModalTouchBar(touchBar)
            isPresented = false
        }
        setStatus(.idle)
    }

    func closeShelfFromUser() {
        dismissSystemModal()
        onUserClosedShelf?()
    }

    func setSessionActive(_ active: Bool, reason: String) {
        guard isSessionActive != active else {
            shelfMouseBridgeDidLog("session unchanged | active=\(active) reason=\(reason)")
            return
        }
        isSessionActive = active
        shelfMouseBridgeDidLog("session active changed | active=\(active) reason=\(reason)")
        if !active {
            shouldRestoreAfterSessionActive = isPresented
            dismissSystemModal()
            return
        }
        if shouldRestoreAfterSessionActive {
            shouldRestoreAfterSessionActive = false
            presentSystemModal()
        }
    }

    func clearShelf() {
        shelf.clear()
        stacks.clear()
        favoritesStore.clear()
        UserDefaults.standard.removeObject(forKey: Self.rootItemOrderKey)
        shelfMouseBridgeDidLog("CLEAR removed root Shelf items, pinned files, root order, and all Stack/Nested Stack records")
        dismissSystemModal()
    }

    func setMouseBridgeHeightInPixels(_ pixels: Int) {
        shelfMouseBridgeController.setHeightInPixels(pixels)
        actionMenuMouseBridgeController.setHeightInPixels(pixels)
    }

    func settingsDidChange(_ change: AppSettingsStore.Change) {
        if case let .feature(feature, enabled) = change {
            shelfMouseBridgeDidLog("setting changed | feature=\(feature.title) enabled=\(enabled)")
        }
        if !settings.isFeatureEnabled(.airDrop), activeDropZone == .airDrop {
            activeDropZone = .shelf
        }
        if !settings.isFeatureEnabled(.clipboardShelf), shelfMode == .clipboard {
            shelfMode = .file
            selectedClipboardOperationItemID = nil
        }
        if !settings.isFeatureEnabled(.recentFiles), shelfMode == .recent {
            shelfMode = .file
        }
        if !settings.isFeatureEnabled(.touchBarSearch), isSearchMode {
            isSearchMode = false
            searchInputHost.end()
            searchQuery = ""
            searchResults = []
            detailReturnToSearch = false
        }
        if !settings.isFeatureEnabled(.quickActions) {
            selectedOperationItemID = nil
            selectedClipboardOperationItemID = nil
            clearTransientDetail()
            detailReturnToSearch = false
        }
        rebuildTouchBarForCurrentSettings()
    }

    func presentClipboardShelf() {
        guard isSessionActive else {
            shelfMouseBridgeDidLog("present Clipboard Shelf ignored | reason=session inactive")
            return
        }
        guard settings.isFeatureEnabled(.clipboardShelf) else {
            showAlert(
                title: "Clipboard Shelf is disabled",
                message: "Enable Clipboard Shelf in Shelf settings before presenting it."
            )
            return
        }
        shelfMode = .clipboard
        currentStackID = nil
        stackNavigationPath.removeAll()
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        clearTransientDetail()
        detailReturnToSearch = false
        isSearchMode = false
        searchInputHost.end()
        endStackRename()
        refreshTouchBarItems()
        ensureSystemModalPresented()
        updateMouseBridgeState()
        schedulePostRenderMouseBridgeRefresh(reason: "present clipboard shelf")
        setStatus(.shelfActive)
    }

    func beginSearch() {
        guard isSessionActive, settings.isFeatureEnabled(.touchBarSearch), isPresented else { return }
        endStackRename()
        shelfModeBeforeSearch = shelfMode
        isSearchMode = true
        searchQuery = ""
        updateSearchResults()
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        clearTransientDetail()
        detailReturnToSearch = false
        refreshTouchBarItems(forceRebuild: true)
        ensureSystemModalPresented()
        searchInputHost.begin(query: searchQuery)
        updateMouseBridgeState()
    }

    func appearanceDidChange() {
        guard isPresented else { return }
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.03)
    }

    func finderFileDragDetected() {
        guard isSessionActive else { return }
        pendingDragDismiss?.cancel()
        pendingDragDismiss = nil
        currentDragDidDrop = false
        setStatus(.dragDetected)
    }

    func finderFileDragEnded() {
        restoreShelfAfterCancelledDrag(reason: "finder drag ended")
    }

    func overlayDragEntered(snapshot: ShelfDropZoneSnapshot) {
        guard isSessionActive else { return }
        showDropTarget(snapshot: snapshot)
    }

    func overlayDragUpdated(snapshot: ShelfDropZoneSnapshot) {
        guard isSessionActive else { return }
        showDropTarget(snapshot: snapshot)
    }

    func overlayDragExited() {
        activeDropZone = .none
        restoreShelfAfterCancelledDrag(reason: "overlay drag exited")
    }

    func overlayDragEnded() {
        activeDropZone = .none
        restoreShelfAfterCancelledDrag(reason: "overlay drag ended")
    }

    func overlayDidReceive(imports: [ShelfImport]) {
        guard !imports.isEmpty else { return }
        pendingDragDismiss?.cancel()
        pendingDragDismiss = nil
        currentDragDidDrop = true
        isShowingDropTarget = false
        activeDropZone = .none
        selectedOperationItemID = nil
        currentStackID = nil
        stackNavigationPath.removeAll()
        renderedStackItemIDs.removeAll()

        print("[ShelfBar] drop success; adding \(imports.count) item(s)")
        for item in imports {
            shelfMouseBridgeDidLog(
                "selected kind=\(item.kind.rawValue) why=\(item.originalSourceDescription) "
                    + "temp file path=\(item.localURL?.path ?? "original")"
            )
            recentItemsStore.record(fileURL: item.url, title: item.displayName)
        }
        shelf.add(imports: imports)
        refreshTouchBarItems()
        scheduleVisibleContentRefresh(mode: "shelf")
        ensureSystemModalPresented()
        updateMouseBridgeState()
        setStatus(.dropSuccess)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentDragDidDrop else { return }
            self.setStatus(.shelfActive)
        }
    }

    func overlayDidRequestAirDrop(imports: [ShelfImport], inspection: DropPayloadInspection) {
        guard settings.isFeatureEnabled(.airDrop) else {
            shelfMouseBridgeDidLog("AirDrop ignored | reason=feature disabled")
            overlayDropDidFail(inspection)
            return
        }
        pendingDragDismiss?.cancel()
        pendingDragDismiss = nil
        currentDragDidDrop = true
        activeDropZone = .airDrop
        let urls = imports.map(\.url)
        shelfMouseBridgeDidLog("activeDropZone=airDrop")
        shelfMouseBridgeDidLog("AirDrop urls=\(urls.map(\.path))")
        guard !urls.isEmpty else {
            shelfMouseBridgeDidLog("AirDrop failure | reason=no file URLs after inspection")
            overlayDropDidFail(inspection)
            return
        }
        guard let service = NSSharingService(named: NSSharingService.Name.sendViaAirDrop) else {
            shelfMouseBridgeDidLog("AirDrop failure | reason=NSSharingService.sendViaAirDrop unavailable")
            restoreShelfAfterCancelledDrag(reason: "AirDrop unavailable")
            return
        }
        service.perform(withItems: urls)
        shelfMouseBridgeDidLog("AirDrop success | NSSharingService sendViaAirDrop invoked count=\(urls.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.dismissSystemModal()
        }
    }

    func overlayDropDidFail(_ inspection: DropPayloadInspection) {
        print("[ShelfBar] drop failed reasons=\(inspection.failureReasons)")
        restoreShelfAfterCancelledDrag(reason: "drop failed")
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        switch identifier {
        case ItemID.dropHere:
            item.view = TouchBarDropButton(
                activeZone: visibleDropZone(activeDropZone),
                isAirDropEnabled: settings.isFeatureEnabled(.airDrop)
            )
        case ItemID.centerExpand:
            item.view = CenterExpandPillView()
        case ItemID.shelf, ItemID.stackShelf:
            item.view = makeScrubber()
        case ItemID.clear:
            item.view = makeButton(title: "CLEAR", action: #selector(clearPressed), width: 75)
        case ItemID.close:
            item.view = makeButton(title: "CLOSE", action: #selector(closePressed), width: 78)
        case ItemID.operationActions:
            item.view = makeOperationActions()
        case ItemID.stackBack:
            item.view = makeSymbolButton(title: "BACK", symbol: "chevron.left", action: #selector(stackBackPressed), width: 96)
        case ItemID.stackTitle:
            item.view = makeStackTitle()
        case ItemID.modeSwitcher:
            item.view = makeModeSwitcherButton()
        case ItemID.counter:
            item.view = makeCounterLabel()
        case ItemID.recent:
            item.view = makeSymbolButton(title: "RECENT", symbol: "clock", action: #selector(recentPressed), width: 92)
        case ItemID.search:
            item.view = makeSymbolButton(title: "", symbol: "magnifyingglass", action: #selector(searchPressed), width: 46)
        case ItemID.searchField:
            item.view = makeSearchField()
        case ItemID.searchCancel:
            item.view = makeButton(title: "CANCEL", action: #selector(searchCancelPressed), width: 88)
        case ItemID.searchClear:
            item.view = makeButton(title: "CLEAR", action: #selector(searchClearPressed), width: 78)
        case ItemID.mainLayout:
            item.view = isSearchMode ? makeSearchShelfLayout() : makeMainShelfLayout()
        case ItemID.stackRename:
            item.view = makeSymbolButton(title: "RENAME", symbol: "pencil", action: #selector(stackRenamePressed), width: 106)
        case ItemID.stackUnstack:
            item.view = makeSymbolButton(title: "UNSTACK", symbol: "rectangle.stack.badge.minus", action: #selector(stackUnstackPressed), width: 112)
        case ItemID.renameCancel:
            item.view = makeButton(title: "CANCEL", action: #selector(cancelStackRenamePressed), width: 88)
        case ItemID.renameField:
            item.view = makeRenameField()
        case ItemID.renameSave:
            item.view = makeButton(title: "SAVE", action: #selector(saveStackRenamePressed), width: 74)
        default:
            return nil
        }
        return item
    }

    func numberOfItems(for scrubber: NSScrubber) -> Int {
        if isSearchMode {
            return searchResults.count
        }
        if shelfMode == .clipboard {
            return clipboardStore.items.count
        }
        if shelfMode == .recent {
            return recentItemsStore.items.count
        }
        if currentStackID != nil {
            return currentStackDisplayEntries.count
        }
        return rootDisplayEntries.count
    }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        guard let view = scrubber.makeItem(
                withIdentifier: Self.scrubberItemIdentifier,
                owner: self
            ) as? ShelfScrubberItemView
        else { return NSScrubberItemView() }

        if isSearchMode {
            guard searchResults.indices.contains(index) else { return NSScrubberItemView() }
            configure(view, with: searchResults[index])
        } else if shelfMode == .clipboard {
            guard clipboardStore.items.indices.contains(index) else { return NSScrubberItemView() }
            view.configure(with: clipboardStore.items[index])
        } else if shelfMode == .recent {
            guard recentItemsStore.items.indices.contains(index) else { return NSScrubberItemView() }
            configure(view, with: .recent(recentItemsStore.items[index]))
        } else if currentStackID != nil {
            let entries = currentStackDisplayEntries
            guard entries.indices.contains(index) else { return NSScrubberItemView() }
            switch entries[index] {
            case let .file(renderedItem):
                view.configure(with: renderedItem, pinned: isPinned(renderedItem))
                if renderedStackItemIDs.insert(renderedItem.id).inserted {
                    shelfMouseBridgeDidLog("each rendered item filename=\(renderedItem.filename)")
                }
            case let .stack(child):
                view.configure(with: child, itemCount: stacks.directItemCount(in: child.id))
            }
        } else {
            let entries = rootDisplayEntries
            guard entries.indices.contains(index) else { return NSScrubberItemView() }
            switch entries[index] {
            case let .file(item):
                let pinned = isPinned(item)
                view.configure(with: item, pinned: pinned, allowsReorder: !pinned)
            case let .stack(stack):
                view.configure(with: stack, itemCount: stacks.directItemCount(in: stack.id))
            case .pinDivider:
                view.configurePinDivider()
            }
        }
        view.touchReorderDelegate = self
        return view
    }

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt selectedIndex: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !isTouchReorderGestureInProgress, now >= suppressNativeSelectionUntil else {
            shelfMouseBridgeDidLog(
                "StabilityFix6 native selection suppressed for active touch reorder | index=\(selectedIndex)"
            )
            scrubber.selectedIndex = -1
            return
        }
        shelfMouseBridgeDidLog(
            "StabilityFix6 formal NSScrubber native didSelect | index=\(selectedIndex) mode=\(currentTouchBarMode)"
        )
        guard selectedOperationItemID == nil, selectedClipboardOperationItemID == nil else { return }
        if isSearchMode {
            shelfMouseBridgeDidLog("StabilityFix6 native action dispatch | route=search index=\(selectedIndex)")
            handleSearchSelection(at: selectedIndex)
        } else if shelfMode == .clipboard {
            guard settings.isFeatureEnabled(.quickActions),
                  clipboardStore.items.indices.contains(selectedIndex)
            else { return }
            shelfMouseBridgeDidLog("StabilityFix6 native action dispatch | route=clipboard index=\(selectedIndex)")
            selectedClipboardOperationItemID = clipboardStore.items[selectedIndex].id
        } else if shelfMode == .recent {
            shelfMouseBridgeDidLog("StabilityFix6 native action dispatch | route=recent index=\(selectedIndex)")
            handleRecentSelection(at: selectedIndex)
            scrubber.selectedIndex = -1
            return
        } else if currentStackID != nil {
            let entries = currentStackDisplayEntries
            guard entries.indices.contains(selectedIndex) else { return }
            switch entries[selectedIndex] {
            case let .file(item):
                shelfMouseBridgeDidLog("StabilityFix6 native action dispatch | route=stack-file item id=\(item.id)")
                selectOperationItem(item)
            case let .stack(stack):
                shelfMouseBridgeDidLog("StabilityFix6 native action dispatch | route=stack-child stack id=\(stack.id)")
                enterStack(id: stack.id)
                scrubber.selectedIndex = -1
                return
            }
        } else {
            let entries = rootDisplayEntries
            guard entries.indices.contains(selectedIndex) else { return }
            switch entries[selectedIndex] {
            case let .file(item):
                guard settings.isFeatureEnabled(.quickActions) else { return }
                shelfMouseBridgeDidLog("StabilityFix6 native action dispatch | route=root-file item id=\(item.id)")
                selectOperationItem(item)
            case let .stack(stack):
                shelfMouseBridgeDidLog("StabilityFix6 native action dispatch | route=root-stack stack id=\(stack.id)")
                enterStack(id: stack.id)
                scrubber.selectedIndex = -1
                return
            case .pinDivider:
                shelfMouseBridgeDidLog("StabilityFix6 native selection ignored | route=pin-divider index=\(selectedIndex)")
                scrubber.selectedIndex = -1
                return
            }
        }
        scrubber.selectedIndex = -1
        if let selectedOperationItemID {
            shelfMouseBridgeDidLog("action menu opened item id=\(selectedOperationItemID)")
        }
        if let selectedClipboardOperationItemID {
            shelfMouseBridgeDidLog("clipboard action menu opened item id=\(selectedClipboardOperationItemID)")
        }
        refreshTouchBarItems()
        updateMouseBridgeState()
    }

    private func showDropTarget() {
        showDropTarget(zone: .none)
    }

    private func showDropTarget(zone: ShelfDropZone) {
        let snapshot = ShelfDropZoneSnapshot(
            zone: zone,
            locationX: -1,
            airDropRect: .zero,
            shelfRect: .zero,
            gapRect: .zero
        )
        showDropTarget(snapshot: snapshot)
    }

    private func showDropTarget(snapshot: ShelfDropZoneSnapshot) {
        pendingDragDismiss?.cancel()
        pendingDragDismiss = nil
        currentDragDidDrop = false
        isShowingDropTarget = true
        isCenterExpandOpening = false
        let previousZone = activeDropZone
        activeDropZone = visibleDropZone(snapshot.zone)
        shelfMouseBridgeDidLog(
            "activeDropZone=\(activeDropZone.rawValue) "
                + "drag location x=\(String(format: "%.2f", snapshot.locationX)) "
                + "airDrop rect=\(snapshot.airDropRect) "
                + "shelf rect=\(snapshot.shelfRect) "
                + "gap rect=\(snapshot.gapRect)"
        )
        selectedOperationItemID = nil
        currentStackID = nil
        stackNavigationPath.removeAll()
        renderedStackItemIDs.removeAll()
        refreshTouchBarItems()
        if previousZone != activeDropZone,
           let dropView = touchBar.item(forIdentifier: ItemID.dropHere)?.view as? TouchBarDropButton {
            dropView.applyActiveZone(activeDropZone)
            shelfMouseBridgeDidLog("UI active zone applied=\(activeDropZone.rawValue)")
        }
        ensureSystemModalPresented()
        updateMouseBridgeState()
        setStatus(.dropReady)
    }

    private func finishCenterExpandOpening() {
        isCenterExpandOpening = false
        refreshTouchBarItems()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.05)
        ensureSystemModalPresented()
        updateMouseBridgeState()
        scheduleCenterExpandItemFade()
        shelfMouseBridgeDidLog("Floating Button Center Expand finished; Shelf UI restored")
    }

    private func scheduleCenterExpandItemFade() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self,
                  let parent = NSFunctionRow._topLevelViews().last
            else { return }
            let itemViews = self.descendantBridgeViews(of: parent)
                .compactMap { $0 as? ShelfScrubberItemView }
                .sorted { lhs, rhs in
                    let a = lhs.superview?.convert(lhs.frame, to: parent).midX ?? 0
                    let b = rhs.superview?.convert(rhs.frame, to: parent).midX ?? 0
                    return a < b
                }
            guard !itemViews.isEmpty else { return }
            for view in itemViews {
                view.alphaValue = 0
            }
            for (index, view) in itemViews.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.04) {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.16
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        view.animator().alphaValue = 1
                    }
                }
            }
            self.shelfMouseBridgeDidLog(
                "Center Expand item cascade fade applied count=\(itemViews.count) interval=40ms"
            )
        }
    }

    private func restoreShelfAfterCancelledDrag(reason: String) {
        guard !currentDragDidDrop else { return }
        pendingDragDismiss?.cancel()
        pendingDragDismiss = nil
        isShowingDropTarget = false
        activeDropZone = .none
        shelfMouseBridgeDidLog("cancelled drag kept Shelf visible | reason=\(reason)")
        refreshTouchBarItems(forceRebuild: true)
        if isPresented {
            ensureSystemModalPresented()
            updateMouseBridgeState()
            setStatus(mainItemCount == 0 ? .dropReady : .shelfActive)
        }
    }

    private func ensureSystemModalPresented() {
        guard !isPresented else { return }
        print("[ShelfBar] presenting system-modal Touch Bar")
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        NSTouchBar.presentSystemModalTouchBar(
            touchBar,
            placement: 1,
            systemTrayItemIdentifier: nil
        )
        isPresented = true
        onShelfPresented?()
        updateMouseBridgeState()
    }

    private func shelfDidChange(_ items: [FileShelfItem]) {
        if let selectedOperationItemID,
           visibleFileItemForInteraction(id: selectedOperationItemID) == nil {
            self.selectedOperationItemID = nil
        }
        refreshTouchBarItems()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode)
        onShelfChange?(items)
        updateMouseBridgeState()
    }

    private func stacksDidChange(_ stacks: [ShelfStack]) {
        stackNavigationPath.removeAll { id in !stacks.contains(where: { $0.id == id }) }
        if let currentStackID, !stacks.contains(where: { $0.id == currentStackID }) {
            self.currentStackID = stackNavigationPath.last
            renderedStackItemIDs.removeAll()
            selectedOperationItemID = nil
        }
        refreshTouchBarItems()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode)
        onStacksChange?(stacks)
        updateMouseBridgeState()
    }

    private func shelfThumbnailDidChange(indexes: IndexSet) {
        updateOperationIconIfNeeded()
        guard currentStackID == nil else { return }
        if let scrubber {
            scrubber.reloadItems(at: indexes)
        } else {
            refreshTouchBarItems(forceRebuild: true)
        }
        onShelfChange?(shelf.items)
        shelfMouseBridgeController.requestHitRegionRebuild(mode: currentTouchBarMode)
    }

    private func stackThumbnailDidChange(url: URL) {
        updateOperationIconIfNeeded(matching: url)
        if currentStackID != nil {
            let latestItems = currentFileItems
            var changed = IndexSet()
            for index in latestItems.indices where latestItems[index].url == url {
                changed.insert(index)
            }
            if !changed.isEmpty {
                if let scrubber {
                    scrubber.reloadItems(at: changed)
                } else {
                    refreshTouchBarItems(forceRebuild: true)
                }
                onStacksChange?(stacks.stacks)
                shelfMouseBridgeController.requestHitRegionRebuild(mode: currentTouchBarMode)
            }
            return
        }

        var changedStackIndexes = IndexSet()
        for (stackIndex, stack) in stacks.rootStacks.enumerated()
        where stack.entries.first?.url == url {
            changedStackIndexes.insert(shelf.items.count + stackIndex)
        }
        if !changedStackIndexes.isEmpty {
            scrubber?.reloadItems(at: changedStackIndexes)
            onStacksChange?(stacks.stacks)
        }
    }

    private func updateOperationIconIfNeeded(matching url: URL? = nil) {
        guard let item = selectedOperationItem,
              url == nil || item.url == url,
              let imageView = operationIconImageView
        else { return }
        imageView.image = FileShelfModel.makeItem(url: item.url, id: item.id).displayImage
    }

    private func rebuildTouchBarForCurrentSettings() {
        refreshTouchBarItems(forceRebuild: true)
        if isPresented {
            NSTouchBar.dismissSystemModalTouchBar(touchBar)
            isPresented = false
            ensureSystemModalPresented()
        }
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.03)
        updateMouseBridgeState()
    }

    private func clipboardDidChange() {
        if selectedClipboardOperationItemID != nil,
           selectedClipboardOperationItem == nil {
            selectedClipboardOperationItemID = nil
        }
        updateSearchResults()
        if isSearchMode {
            scrubber?.reloadData()
            scheduleVisibleContentRefresh(mode: currentTouchBarMode)
        } else {
            refreshTouchBarItems()
            scheduleVisibleContentRefresh(mode: currentTouchBarMode)
        }
    }

    private func favoritesDidChange() {
        updateSearchResults()
        if isSearchMode {
            scrubber?.reloadData()
        } else {
            refreshTouchBarItems()
        }
        scheduleVisibleContentRefresh(mode: currentTouchBarMode)
        onShelfChange?(shelf.items)
        updateMouseBridgeState()
    }

    private func recentDidChange() {
        updateSearchResults()
        if isSearchMode {
            scrubber?.reloadData()
        } else {
            refreshTouchBarItems()
        }
    }

    private func updateSearchResults() {
        switch shelfModeBeforeSearch {
        case .file:
            let files = currentStackID == nil ? shelf.items : []
            let favorites: [FileShelfItem]
            if currentStackID == nil && settings.isFeatureEnabled(.pinFavorites) {
                favorites = favoritesStore.pinnedFileItems()
            } else {
                favorites = []
            }
            searchResults = SearchController.results(
                query: searchQuery,
                files: files,
                favorites: favorites,
                stacks: stacks.searchScopeStacks(currentStackID: currentStackID),
                clipboard: [],
                recent: []
            )
        case .clipboard:
            searchResults = SearchController.results(
                query: searchQuery,
                files: [],
                favorites: [],
                stacks: [],
                clipboard: clipboardStore.items,
                recent: []
            )
        case .recent:
            searchResults = SearchController.results(
                query: searchQuery,
                files: [],
                favorites: [],
                stacks: [],
                clipboard: [],
                recent: recentItemsStore.items
            )
        }
    }

    private func endSearchMode() {
        isSearchMode = false
        searchInputHost.end()
        searchQuery = ""
        searchResults = []
        detailReturnToSearch = false
        searchReturnAnchorResultID = nil
        searchReturnStackID = nil
        searchReturnStackNavigationPath = []
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        clearTransientDetail()
        if shelfMode == .recent, shelfModeBeforeSearch != .recent {
            shelfMode = shelfModeBeforeSearch
        }
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
    }

    private func handleSearchSelection(at index: Int) {
        guard searchResults.indices.contains(index) else { return }
        prepareReturnToSearch(anchor: searchResults[index].id)
        switch searchResults[index] {
        case let .file(item):
            transientOperationItem = item
            transientClipboardOperationItem = nil
            selectedOperationItemID = item.id
            selectedClipboardOperationItemID = nil
        case let .stack(stack):
            transientOperationItem = nil
            transientClipboardOperationItem = nil
            selectedOperationItemID = nil
            selectedClipboardOperationItemID = nil
            searchInputHost.end()
            enterStack(id: stack.id)
            detailReturnToSearch = true
            searchReturnAnchorResultID = stack.id
            updateMouseBridgeState()
            return
        case let .stackFile(stackID, _, entry):
            guard let item = entry.fileItem else { return }
            searchInputHost.end()
            enterStack(id: stackID)
            transientOperationItem = item
            transientClipboardOperationItem = nil
            selectedOperationItemID = item.id
            selectedClipboardOperationItemID = nil
            detailReturnToSearch = true
            searchReturnAnchorResultID = entry.id
            refreshTouchBarItems(forceRebuild: true)
            updateMouseBridgeState()
            return
        case let .clipboard(item):
            transientOperationItem = nil
            transientClipboardOperationItem = item
            selectedOperationItemID = nil
            selectedClipboardOperationItemID = item.id
        case let .recent(item):
            if let fileItem = fileItem(from: item) {
                transientOperationItem = fileItem
                transientClipboardOperationItem = nil
                selectedOperationItemID = fileItem.id
                selectedClipboardOperationItemID = nil
            } else {
                let clip = clipboardItem(from: item)
                transientOperationItem = nil
                transientClipboardOperationItem = clip
                selectedOperationItemID = nil
                selectedClipboardOperationItemID = clip.id
            }
        }
        searchInputHost.end()
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState()
    }

    private func prepareReturnToSearch(anchor: UUID) {
        detailReturnToSearch = true
        searchReturnAnchorResultID = anchor
        searchReturnStackID = currentStackID
        searchReturnStackNavigationPath = stackNavigationPath
    }

    private func handleRecentSelection(at index: Int) {
        guard recentItemsStore.items.indices.contains(index) else { return }
        let item = recentItemsStore.items[index]
        if let fileItem = fileItem(from: item) {
            transientOperationItem = fileItem
            selectedOperationItemID = fileItem.id
            selectedClipboardOperationItemID = nil
            transientClipboardOperationItem = nil
        } else {
            let clip = clipboardItem(from: item)
            transientClipboardOperationItem = clip
            selectedClipboardOperationItemID = clip.id
            selectedOperationItemID = nil
            transientOperationItem = nil
        }
        detailReturnToSearch = false
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState()
    }

    private func fileItem(from item: RecentShelfItem) -> FileShelfItem? {
        guard item.type == .file,
              let urlString = item.urlString,
              let url = URL(string: urlString)
        else { return nil }
        return FileShelfModel.makeItem(
            url: url,
            id: item.id,
            displayName: item.title,
            kind: .file,
            originalSourceDescription: "Recent",
            originalFileURL: url,
            localURL: nil
        )
    }

    private func clipboardItem(from item: RecentShelfItem) -> ClipboardShelfItem {
        let url = item.urlString.flatMap(URL.init(string:))
        if let url, url.isFileURL {
            return ClipboardShelfItem(
                id: item.id,
                type: .file,
                title: item.title,
                copiedAt: item.touchedAt,
                text: nil,
                urlString: nil,
                fileURLString: url.absoluteString,
                imageFilename: nil,
                pinned: false
            )
        }
        if let url {
            return ClipboardShelfItem(
                id: item.id,
                type: .url,
                title: item.title,
                copiedAt: item.touchedAt,
                text: url.absoluteString,
                urlString: url.absoluteString,
                fileURLString: nil,
                imageFilename: nil,
                pinned: false
            )
        }
        return ClipboardShelfItem(
            id: item.id,
            type: .text,
            title: item.title,
            copiedAt: item.touchedAt,
            text: item.title,
            urlString: nil,
            fileURLString: nil,
            imageFilename: nil,
            pinned: false
        )
    }

    private func clearTransientDetail() {
        transientOperationItem = nil
        transientClipboardOperationItem = nil
    }

    private func endStackRename() {
        isRenamingStack = false
        renameStackID = nil
        renameDraft = ""
        activeRenameDisplay = nil
        renameInputHost.end()
    }

    private func fileShelfSizeText() -> String {
        let bytes = displayedRootFileItems.reduce(Int64(0)) { partial, item in
            let values = try? item.url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard values?.isDirectory != true else { return partial }
            return partial + Int64(values?.fileSize ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func sendCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func accessibilityTrustedForPaste(reason: String) -> Bool {
        let trusted = AXIsProcessTrusted()
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let appPath = Bundle.main.bundleURL.path
        print("[Accessibility] reason=\(reason) trusted=\(trusted) bundleID=\(bundleID) appPath=\(appPath)")
        return trusted
    }

    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission required"
        alert.informativeText = "The item was copied to the pasteboard. Enable ShelfBar in System Settings > Privacy & Security > Accessibility to paste automatically."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func refreshTouchBarItems(forceRebuild: Bool = false) {
        let shouldForceRebuild = forceRebuild
            || touchBar.defaultItemIdentifiers == [ItemID.mainLayout]
            || touchBar.defaultItemIdentifiers == [ItemID.operationActions]
        if shouldForceRebuild {
            interactionCoordinator.resetForTouchBarRebuild(reason: "refreshTouchBarItems")
            scrubber = nil
            shelfScrollView = nil
            activeSearchDisplay = nil
            activeRenameDisplay = nil
        }
        let identifiers: [NSTouchBarItem.Identifier]
        let principal: NSTouchBarItem.Identifier
        if isCenterExpandOpening {
            identifiers = [ItemID.centerExpand]
            principal = ItemID.centerExpand
        } else if isRenamingStack {
            identifiers = [ItemID.renameCancel, ItemID.renameField, ItemID.renameSave]
            principal = ItemID.renameField
        } else if selectedOperationItem != nil || selectedClipboardOperationItem != nil {
            identifiers = [ItemID.operationActions]
            principal = ItemID.operationActions
        } else if isSearchMode {
            identifiers = [ItemID.mainLayout]
            principal = ItemID.mainLayout
        } else if isShowingDropTarget {
            identifiers = [ItemID.dropHere]
            principal = ItemID.dropHere
        } else if currentStackID != nil {
            identifiers = [ItemID.mainLayout]
            principal = ItemID.mainLayout
        } else if shelfMode == .clipboard {
            identifiers = [ItemID.mainLayout]
            principal = ItemID.mainLayout
        } else if shelfMode == .recent {
            identifiers = [ItemID.mainLayout]
            principal = ItemID.mainLayout
        } else if mainItemCount == 0 {
            identifiers = [ItemID.mainLayout]
            principal = ItemID.mainLayout
        } else {
            identifiers = [ItemID.mainLayout]
            principal = ItemID.mainLayout
        }
        if shouldForceRebuild {
            touchBar.defaultItemIdentifiers = []
            touchBar.principalItemIdentifier = nil
        }
        if touchBar.defaultItemIdentifiers != identifiers {
            touchBar.defaultItemIdentifiers = identifiers
        }
        if touchBar.principalItemIdentifier != principal {
            touchBar.principalItemIdentifier = principal
        }
    }

    private func resetVisibleInteractionState(reason: String) {
        let roots = touchBar.defaultItemIdentifiers.compactMap {
            touchBar.item(forIdentifier: $0)?.view
        } + NSFunctionRow._topLevelViews()
        var visited = Set<ObjectIdentifier>()
        var resetCount = 0
        for root in roots {
            for itemView in descendantShelfItemViews(of: root) {
                let id = ObjectIdentifier(itemView)
                guard visited.insert(id).inserted else { continue }
                itemView.resetTransientInteractionState()
                resetCount += 1
            }
        }
        shelfMouseBridgeDidLog(
            "Interaction visible state reset | reason=\(reason) itemViews=\(resetCount)"
        )
    }

    private func descendantShelfItemViews(of view: NSView) -> [ShelfScrubberItemView] {
        var result: [ShelfScrubberItemView] = []
        for subview in view.subviews {
            if let itemView = subview as? ShelfScrubberItemView {
                result.append(itemView)
            }
            result.append(contentsOf: descendantShelfItemViews(of: subview))
        }
        return result
    }

    private func controlItems(prefix: Bool) -> [NSTouchBarItem.Identifier] {
        if prefix {
            var items: [NSTouchBarItem.Identifier] = []
            if settings.isFeatureEnabled(.clipboardShelf),
               settings.isFeatureEnabled(.shelfClipboardSwitcher) {
                items.append(ItemID.modeSwitcher)
            }
            if settings.isFeatureEnabled(.touchBarSearch) {
                items.append(ItemID.search)
            }
            if shelfMode == .file,
               currentStackID == nil,
               settings.isFeatureEnabled(.recentFiles) {
                items.append(ItemID.recent)
            }
            return items
        }
        return settings.isFeatureEnabled(.dropCounter) ? [ItemID.counter] : []
    }

    private func makeMainShelfLayout() -> NSView {
        if currentStackID != nil {
            return makeStackDetailLayout()
        }

        mainLayoutRenderSerial += 1
        let serial = mainLayoutRenderSerial
        let route = pendingMainAttachRoute
            ?? (hasRenderedRootMainLayout ? "root-main-rerender" : "first-root-main-render")
        pendingMainAttachRoute = nil
        hasRenderedRootMainLayout = true
        mainLayoutRenderStartTimes[serial] = ProcessInfo.processInfo.systemUptime
        shelfMouseBridgeDidLog(
            "BugFix18 main layout render start | route=\(route) serial=\(serial) "
                + "mode=\(currentTouchBarMode) pinned=\(rootPinnedEntryCount) "
                + "divider=\(rootDisplayEntries.contains { $0.isDivider }) items=\(rootDisplayEntries.count)"
        )

        let container = MainShelfLayoutProbeView(route: route, serial: serial) { [weak self] event, view in
            self?.mainLayoutProbeEvent(event, view: view)
        }
        container.translatesAutoresizingMaskIntoConstraints = false

        let leftButtons = mainLeftControls()
        let leftStack = NSStackView(views: leftButtons)
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 6
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let middleView: NSView
        if shelfMode == .clipboard, clipboardStore.items.isEmpty {
            middleView = makeStackTitle()
        } else if shelfMode == .file, mainItemCount == 0 {
            middleView = makeEmptyShelfView()
        } else {
            middleView = makeShelfScrollStrip(width: 430)
        }
        middleView.translatesAutoresizingMaskIntoConstraints = false

        let clear = makeButton(title: "CLEAR", action: #selector(clearPressed), width: 86)
        let close = makeButton(title: "CLOSE", action: #selector(closePressed), width: 88)
        let rightStack = NSStackView(views: [clear, close])
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 7
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(leftStack)
        container.addSubview(middleView)
        container.addSubview(rightStack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 940),
            container.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight),
            leftStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leftStack.widthAnchor.constraint(lessThanOrEqualToConstant: 290),
            middleView.leadingAnchor.constraint(equalTo: leftStack.trailingAnchor, constant: 8),
            middleView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            middleView.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -10),
            rightStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            rightStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeSearchShelfLayout() -> NSView {
        mainLayoutRenderSerial += 1
        let serial = mainLayoutRenderSerial
        mainLayoutRenderStartTimes[serial] = ProcessInfo.processInfo.systemUptime
        let container = MainShelfLayoutProbeView(route: "search-main-render", serial: serial) { [weak self] event, view in
            self?.mainLayoutProbeEvent(event, view: view)
        }
        container.translatesAutoresizingMaskIntoConstraints = false

        let cancel = makeButton(title: "CANCEL", action: #selector(searchCancelPressed), width: 88)
        let field = makeSearchField(width: 360)
        let resultWidth: CGFloat = 260
        let trailingSafetyInset: CGFloat = 28
        let actionWidth: CGFloat = 78 + 7 + 82

        let middleView: NSView = searchResults.isEmpty
            ? makeSearchResultsPlaceholder(width: resultWidth)
            : makeShelfScrollStrip(width: resultWidth)
        middleView.translatesAutoresizingMaskIntoConstraints = false

        let clear = makeButton(title: "CLEAR", action: #selector(searchClearPressed), width: 78)
        clear.isEnabled = !searchQuery.isEmpty
        let close = makeButton(title: "CLOSE", action: #selector(closePressed), width: 82)
        let rightStack = NSStackView(views: [clear, close])
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 7
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(cancel)
        container.addSubview(field)
        container.addSubview(middleView)
        container.addSubview(rightStack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 940),
            container.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight),
            cancel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            cancel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: cancel.trailingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            middleView.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 8),
            middleView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            middleView.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -10),
            rightStack.widthAnchor.constraint(equalToConstant: actionWidth),
            rightStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -trailingSafetyInset),
            rightStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        shelfMouseBridgeDidLog(
            "search layout uses shared shelf scroll host | results=\(searchResults.count)"
        )
        return container
    }

    private func mainLayoutProbeEvent(
        _ event: MainShelfLayoutProbeView.Event,
        view: MainShelfLayoutProbeView
    ) {
        let elapsed = mainLayoutRenderStartTimes[view.serial].map {
            String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - $0) * 1000)
        } ?? "n/a"
        let top = NSFunctionRow._topLevelViews().last
        let summary = "route=\(view.route) serial=\(view.serial) elapsedMs=\(elapsed) "
            + "viewWindow=\(view.window != nil) frame=\(debugFrame(view.frame)) "
            + "bounds=\(debugFrame(view.bounds)) topWindow=\(top?.window != nil) "
            + "topFrame=\(top.map { debugFrame($0.frame) } ?? "nil")"
        shelfMouseBridgeDidLog("BugFix18 main layout \(event.rawValue) | \(summary)")
        guard event == .firstLayoutPass else { return }
        lastMainLayoutFirstPassDescription = "\(view.route)#\(view.serial) elapsedMs=\(elapsed)"
        shelfMouseBridgeController.requestReadyAttach(
            mode: currentTouchBarMode,
            reason: "main-layout-first-pass:\(view.route)"
        )
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresented else { return }
            self.shelfMouseBridgeController.requestReadyAttach(
                mode: self.currentTouchBarMode,
                reason: "main-layout-async-ready:\(view.route)"
            )
        }
    }

    private func makeStackDetailLayout() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let back = makeSymbolButton(
            title: "BACK",
            symbol: "chevron.left",
            action: #selector(stackBackPressed),
            width: 86
        )
        let title = makeStackTitle()
        let leftStack = NSStackView(views: [back, title])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 6
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let middleView: NSView = currentStackDisplayEntries.isEmpty
            ? makeStackTitle()
            : makeShelfScrollStrip(width: 405)
        middleView.translatesAutoresizingMaskIntoConstraints = false

        let rename = makeSymbolButton(
            title: "RENAME",
            symbol: "pencil",
            action: #selector(stackRenamePressed),
            width: 102
        )
        let unstack = makeSymbolButton(
            title: "UNSTACK",
            symbol: "rectangle.stack.badge.minus",
            action: #selector(stackUnstackPressed),
            width: 108
        )
        let close = makeButton(title: "CLOSE", action: #selector(closePressed), width: 82)
        let rightStack = NSStackView(views: [rename, unstack, close])
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 6
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(leftStack)
        container.addSubview(middleView)
        container.addSubview(rightStack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 1000),
            container.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight),
            leftStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            leftStack.widthAnchor.constraint(equalToConstant: 228),
            middleView.leadingAnchor.constraint(equalTo: leftStack.trailingAnchor, constant: 8),
            middleView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            middleView.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),
            rightStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            rightStack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        shelfMouseBridgeDidLog(
            "stack detail layout | stackID=\(currentStackID?.uuidString ?? "nil") entries=\(currentStackDisplayEntries.count)"
        )
        return container
    }

    private func mainLeftControls() -> [NSView] {
        var controls: [NSView] = []
        if shelfMode == .recent {
            controls.append(makeSymbolButton(title: "BACK", symbol: "chevron.left", action: #selector(stackBackPressed), width: 86))
        }
        if settings.isFeatureEnabled(.clipboardShelf),
           settings.isFeatureEnabled(.shelfClipboardSwitcher) {
            controls.append(makeModeSwitcherButton())
        }
        if settings.isFeatureEnabled(.touchBarSearch) {
            controls.append(makeSymbolButton(title: "", symbol: "magnifyingglass", action: #selector(searchPressed), width: 46))
        }
        if shelfMode == .file,
           currentStackID == nil,
           settings.isFeatureEnabled(.recentFiles) {
            controls.append(makeSymbolButton(title: "RECENT", symbol: "clock", action: #selector(recentPressed), width: 92))
        }
        if settings.isFeatureEnabled(.dropCounter) {
            controls.append(makeCounterLabel())
        }
        return controls
    }

    private func visibleDropZone(_ zone: ShelfDropZone) -> ShelfDropZone {
        if zone == .airDrop, !settings.isFeatureEnabled(.airDrop) {
            return .shelf
        }
        return zone
    }

    private func makeShelfScrollStrip(width: CGFloat) -> NSScrubber {
        let scrubber = makeScrubber(width: width)
        shelfScrollView = nil
        shelfMouseBridgeDidLog(
            "StabilityFix6 shelf strip uses formal NSScrubber native tap path | mode=\(currentTouchBarMode) "
                + "items=\(numberOfShelfStripItems()) viewport=\(String(format: "%.1f", width))"
        )
        return scrubber
    }

    private func numberOfShelfStripItems() -> Int {
        if isSearchMode {
            return searchResults.count
        }
        if shelfMode == .clipboard {
            return clipboardStore.items.count
        }
        if shelfMode == .recent {
            return recentItemsStore.items.count
        }
        if currentStackID != nil {
            return currentStackDisplayEntries.count
        }
        return rootDisplayEntries.count
    }

    private func configureShelfStripItemView(_ view: ShelfScrubberItemView, at index: Int) {
        if isSearchMode {
            guard searchResults.indices.contains(index) else { return }
            configure(view, with: searchResults[index])
        } else if shelfMode == .clipboard {
            guard clipboardStore.items.indices.contains(index) else { return }
            view.configure(with: clipboardStore.items[index])
        } else if shelfMode == .recent {
            guard recentItemsStore.items.indices.contains(index) else { return }
            configure(view, with: .recent(recentItemsStore.items[index]))
        } else if currentStackID != nil {
            let entries = currentStackDisplayEntries
            guard entries.indices.contains(index) else { return }
            switch entries[index] {
            case let .file(renderedItem):
                view.configure(with: renderedItem, pinned: isPinned(renderedItem))
                if renderedStackItemIDs.insert(renderedItem.id).inserted {
                    shelfMouseBridgeDidLog("each rendered item filename=\(renderedItem.filename)")
                }
            case let .stack(child):
                view.configure(with: child, itemCount: stacks.directItemCount(in: child.id))
            }
        } else {
            let entries = rootDisplayEntries
            guard entries.indices.contains(index) else { return }
            switch entries[index] {
            case let .file(item):
                let pinned = isPinned(item)
                view.configure(with: item, pinned: pinned, allowsReorder: !pinned)
            case let .stack(stack):
                view.configure(with: stack, itemCount: stacks.directItemCount(in: stack.id))
            case .pinDivider:
                view.configurePinDivider()
            }
        }
    }

    private func makeScrubber(width explicitWidth: CGFloat? = nil) -> NSScrubber {
        let scrubber = NSScrubber()
        scrubber.dataSource = self
        scrubber.delegate = self
        scrubber.mode = .free
        scrubber.showsArrowButtons = false
        scrubber.register(
            ShelfScrubberItemView.self,
            forItemIdentifier: Self.scrubberItemIdentifier
        )
        let layout = NSScrubberFlowLayout()
        layout.itemSize = NSSize(width: 88, height: TouchBarMetrics.rowHeight)
        layout.itemSpacing = 8
        scrubber.scrubberLayout = layout
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        let width = explicitWidth ?? (isSearchMode ? 560 : (currentStackID == nil ? 720 : 560))
        NSLayoutConstraint.activate([
            scrubber.widthAnchor.constraint(equalToConstant: width),
            scrubber.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight),
            scrubber.heightAnchor.constraint(lessThanOrEqualToConstant: TouchBarMetrics.rowHeight)
        ])
        self.scrubber = scrubber
        return scrubber
    }

    private var selectedOperationItem: FileShelfItem? {
        guard let selectedOperationItemID else { return nil }
        if transientOperationItem?.id == selectedOperationItemID {
            return transientOperationItem
        }
        return visibleFileItemForInteraction(id: selectedOperationItemID)
    }

    private func selectOperationItem(_ item: FileShelfItem) {
        let resolved = visibleFileItemForInteraction(matching: item)
        selectedOperationItemID = resolved.id
        transientOperationItem = resolved
    }

    private var selectedClipboardOperationItem: ClipboardShelfItem? {
        guard let selectedClipboardOperationItemID else { return nil }
        if transientClipboardOperationItem?.id == selectedClipboardOperationItemID {
            return transientClipboardOperationItem
        }
        return clipboardStore.item(id: selectedClipboardOperationItemID)
    }

    private var currentFileItems: [FileShelfItem] {
        guard let currentStackID else { return shelf.items }
        return stacks.fileItems(in: currentStackID)
    }

    private var displayedRootFileItems: [FileShelfItem] {
        guard currentStackID == nil,
              settings.isFeatureEnabled(.pinFavorites)
        else { return shelf.items }
        let favoriteItems = favoritesStore.pinnedFileItems()
        let favoritePaths = Set(favoriteItems.map { $0.url.standardizedFileURL.path })
        return favoriteItems + shelf.items.filter {
            !favoritePaths.contains($0.url.standardizedFileURL.path)
        }
    }

    private var rootOrderedEntries: [RootDisplayEntry] {
        let baseEntries = displayedRootFileItems.map(RootDisplayEntry.file)
            + stacks.rootStacks.map(RootDisplayEntry.stack)
        let storedOrder = UserDefaults.standard.stringArray(forKey: Self.rootItemOrderKey) ?? []
        guard !storedOrder.isEmpty else { return pinnedFirstRootEntries(baseEntries) }

        var remaining = baseEntries
        var ordered: [RootDisplayEntry] = []
        for key in storedOrder {
            guard let index = remaining.firstIndex(where: { $0.orderKey == key }) else { continue }
            ordered.append(remaining.remove(at: index))
        }
        ordered.append(contentsOf: remaining)
        ordered = pinnedFirstRootEntries(ordered)
        let normalized = ordered.map(\.orderKey)
        if normalized != storedOrder {
            UserDefaults.standard.set(normalized, forKey: Self.rootItemOrderKey)
        }
        return ordered
    }

    private var rootDisplayEntries: [RootDisplayEntry] {
        entriesWithPinDivider(rootOrderedEntries)
    }

    private func saveRootDisplayOrder(_ entries: [RootDisplayEntry]) {
        let persisted = entries.filter { !$0.isDivider }
        UserDefaults.standard.set(pinnedFirstRootEntries(persisted).map(\.orderKey), forKey: Self.rootItemOrderKey)
    }

    private func rootEntriesByMoving(id: UUID, to destinationIndex: Int) -> [RootDisplayEntry]? {
        var entries = rootOrderedEntries
        guard let sourceIndex = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = entries.remove(at: sourceIndex)
        var adjusted = destinationIndex
        if sourceIndex < adjusted { adjusted -= 1 }
        adjusted = min(max(adjusted, 0), entries.count)
        let pinnedCountAfterRemoval = entries.filter(isPinnedRootEntry).count
        if isPinnedRootEntry(entry) {
            adjusted = min(adjusted, pinnedCountAfterRemoval)
        } else {
            adjusted = max(adjusted, pinnedCountAfterRemoval)
        }
        entries.insert(entry, at: adjusted)
        return pinnedFirstRootEntries(entries)
    }

    private func entriesWithPinDivider(_ entries: [RootDisplayEntry]) -> [RootDisplayEntry] {
        let pinnedCount = entries.filter(isPinnedRootEntry).count
        guard pinnedCount > 0, pinnedCount < entries.count else { return entries }
        var displayEntries = entries
        displayEntries.insert(.pinDivider, at: pinnedCount)
        return displayEntries
    }

    private func pinnedFirstRootEntries(_ entries: [RootDisplayEntry]) -> [RootDisplayEntry] {
        let content = entries.filter { !$0.isDivider }
        let pinned = content.filter(isPinnedRootEntry)
        let unpinned = content.filter { !isPinnedRootEntry($0) }
        return pinned + unpinned
    }

    private func isPinnedRootEntry(_ entry: RootDisplayEntry) -> Bool {
        if case let .file(item) = entry {
            return isPinned(item)
        }
        return false
    }

    private var rootPinnedEntryCount: Int {
        rootOrderedEntries.filter(isPinnedRootEntry).count
    }

    private func isPinnedRootItem(_ item: FileShelfItem) -> Bool {
        currentStackID == nil && isPinned(item)
    }

    private func rootReorderDestinationIndex(fromGeneralInsertionIndex index: Int) -> Int {
        rootPinnedEntryCount + max(index, 0)
    }

    private func replaceRootOrderEntry(_ oldKey: String, with newKeys: [String]) {
        var order = UserDefaults.standard.stringArray(forKey: Self.rootItemOrderKey)
            ?? rootOrderedEntries.map(\.orderKey)
        if let index = order.firstIndex(of: oldKey) {
            order.remove(at: index)
            order.insert(contentsOf: newKeys, at: index)
        } else {
            order.append(contentsOf: newKeys)
        }
        UserDefaults.standard.set(order, forKey: Self.rootItemOrderKey)
    }

    private var currentChildStacks: [ShelfStack] {
        guard let currentStackID else { return stacks.rootStacks }
        return stacks.childStacks(of: currentStackID)
    }

    private var currentStackDisplayEntries: [StackDisplayEntry] {
        guard let currentStackID,
              let stack = stacks.stack(id: currentStackID)
        else { return [] }
        let files = stack.entries.compactMap(\.fileItem).map(StackDisplayEntry.file)
        let children = stacks.childStacks(of: currentStackID).map(StackDisplayEntry.stack)
        return files + children
    }

    private func isPinned(_ item: FileShelfItem) -> Bool {
        settings.isFeatureEnabled(.pinFavorites) && favoritesStore.isPinned(fileURL: item.url)
    }

    private func fileURLKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func visibleFileItemsForCurrentContainer() -> [FileShelfItem] {
        currentStackID == nil ? displayedRootFileItems : currentFileItems
    }

    private func visibleFileItemForInteraction(id: UUID) -> FileShelfItem? {
        let visible = visibleFileItemsForCurrentContainer()
        if let exact = visible.first(where: { $0.id == id }) {
            return exact
        }
        let fallbackItems: [FileShelfItem]
        if currentStackID == nil {
            fallbackItems = shelf.items + (transientOperationItem.map { [$0] } ?? [])
        } else {
            fallbackItems = currentFileItems + (transientOperationItem.map { [$0] } ?? [])
        }
        guard let stale = fallbackItems.first(where: { $0.id == id }) else {
            return nil
        }
        let key = fileURLKey(stale.url)
        return visible.first { fileURLKey($0.url) == key } ?? stale
    }

    private func visibleFileItemForInteraction(matching item: FileShelfItem) -> FileShelfItem {
        visibleFileItemForInteraction(id: item.id)
            ?? visibleFileItemsForCurrentContainer().first { fileURLKey($0.url) == fileURLKey(item.url) }
            ?? item
    }

    private var currentContainerItemCount: Int {
        currentStackID == nil
            ? rootOrderedEntries.count
            : currentStackDisplayEntries.count
    }

    private var mainItemCount: Int {
        rootOrderedEntries.count
    }

    private var currentTouchBarMode: String {
        if isShowingDropTarget { return "dropHere" }
        if isRenamingStack { return "rename" }
        if selectedOperationItemID != nil || selectedClipboardOperationItemID != nil { return "actionMenu" }
        if isSearchMode { return "search" }
        if let currentStackID { return "stack:\(currentStackID.uuidString)" }
        if shelfMode == .clipboard { return "clipboard" }
        if shelfMode == .recent { return "recent" }
        return mainItemCount == 0 ? "empty" : "shelf"
    }

    private var searchPlaceholderText: String {
        "Type to search ShelfBar"
    }

    private var autoDissolveSingleItemStack: Bool {
        settings.autoDissolveSingleItemStack
    }

    private func scheduleVisibleContentRefresh(mode: String, delay: TimeInterval = 0.07) {
        contentRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let scrubberIdentifier = self.currentStackID == nil ? ItemID.shelf : ItemID.stackShelf
            let visibleScrubber = (self.touchBar.item(forIdentifier: scrubberIdentifier)?.view
                as? NSScrubber)
                ?? self.touchBar.item(forIdentifier: ItemID.mainLayout)?.view
                    .flatMap { self.descendantScrubber(of: $0) }
            if let visibleScrubber {
                self.scrubber = visibleScrubber
                visibleScrubber.reloadData()
                visibleScrubber.layoutSubtreeIfNeeded()
                if let currentStackID = self.currentStackID {
                    let latestItems = self.stacks.fileItems(in: currentStackID)
                    let displayEntries = self.currentStackDisplayEntries
                    let visibleCount = displayEntries.count
                    let rawEntryCount = self.stacks.stack(id: currentStackID)?.entries.count ?? 0
                    let childStackCount = self.stacks.childStacks(of: currentStackID).count
                    for index in 0..<visibleCount {
                        visibleScrubber.scrollItem(at: index, to: .none)
                        visibleScrubber.layoutSubtreeIfNeeded()
                        _ = visibleScrubber.itemViewForItem(at: index)
                    }
                    if visibleCount > 0 {
                        visibleScrubber.scrollItem(at: 0, to: .leading)
                        visibleScrubber.layoutSubtreeIfNeeded()
                    }
                    let renderedCount = self.renderedStackItemIDs.count
                    self.shelfMouseBridgeDidLog("enter stack id=\(currentStackID)")
                    self.shelfMouseBridgeDidLog(
                        "stack display count=\(displayEntries.count) fileItems=\(latestItems.count) rawEntries=\(rawEntryCount) childStacks=\(childStackCount)"
                    )
                    self.shelfMouseBridgeDidLog("rendered stack item count=\(renderedCount)")
                    if !displayEntries.isEmpty, renderedCount == 0 {
                        self.shelfMouseBridgeDidLog(
                            "ERROR stack display count > 0 but rendered stack item count = 0"
                        )
                    }
                    if rawEntryCount > 0, displayEntries.isEmpty {
                        self.shelfMouseBridgeDidLog(
                            "ERROR stack raw entries exist but no display entries; check bookmark/url resolution"
                        )
                    }
                }
            }
            NSFunctionRow._topLevelViews().last?.layoutSubtreeIfNeeded()
            self.shelfMouseBridgeController.requestReadyAttach(
                mode: mode,
                reason: "visible-content-refresh"
            )
            self.shelfMouseBridgeDidLog(
                "Touch Bar content refresh | current mode=\(mode) delay=\(Int(delay * 1000))ms"
            )
        }
        contentRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func schedulePostRenderMouseBridgeRefresh(reason: String) {
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresented else { return }
            NSFunctionRow._topLevelViews().last?.layoutSubtreeIfNeeded()
            self.shelfMouseBridgeController.requestReadyAttach(
                mode: self.currentTouchBarMode,
                reason: "post-render:\(reason)"
            )
            self.shelfMouseBridgeDidLog("post-render mouse bridge refresh | reason=\(reason)")
        }
    }

    func removeStackItem(id: UUID, from stackID: UUID) {
        let removedItem = stacks.fileItems(in: stackID).first { $0.id == id }
        let outcome = stacks.removeFile(
            id: id,
            from: stackID,
            autoDissolveSingle: autoDissolveSingleItemStack
        )
        if let removedItem {
            favoritesStore.remove(fileURL: removedItem.url)
            logExplicitRemoval(of: removedItem, container: "stack:\(stackID.uuidString)")
            deleteGeneratedFileIfNeeded(for: removedItem)
        }
        switch outcome {
        case .kept:
            break
        case .removedEmpty:
            shelfMouseBridgeDidLog("Stack auto removed | stackID=\(stackID) reason=empty")
        case let .dissolved(remainingItem):
            shelf.add(existingItems: [remainingItem])
            shelfMouseBridgeDidLog(
                "Stack auto dissolved | stackID=\(stackID) remaining=\(remainingItem.url.absoluteString)"
            )
        }
    }

    func removeShelfItem(id: UUID) {
        guard let item = shelf.items.first(where: { $0.id == id }) else { return }
        shelf.remove(id: id)
        favoritesStore.remove(fileURL: item.url)
        logExplicitRemoval(of: item, container: "root")
        deleteGeneratedFileIfNeeded(for: item)
    }

    private func removeRootFileReference(_ item: FileShelfItem) {
        favoritesStore.remove(fileURL: item.url)
        let path = fileURLKey(item.url)
        let shelfIDs = Set(shelf.items.filter { fileURLKey($0.url) == path }.map(\.id))
        if !shelfIDs.isEmpty {
            shelf.remove(ids: shelfIDs)
        }
        logExplicitRemoval(of: item, container: "root")
        deleteGeneratedFileIfNeeded(for: item)
    }

    private func logExplicitRemoval(of item: FileShelfItem, container: String) {
        shelfMouseBridgeDidLog(
            "remove shelf item | id=\(item.id) kind=\(item.kind.rawValue) container=\(container)"
        )
    }

    private func deleteGeneratedFileIfNeeded(for item: FileShelfItem) {
        if let originalURL = item.originalFileURL {
            shelfMouseBridgeDidLog(
                "keep original file | id=\(item.id) path=\(originalURL.path)"
            )
            return
        }
        guard let localURL = item.localURL else {
            shelfMouseBridgeDidLog(
                "keep original file | id=\(item.id) reason=no ShelfBar localURL"
            )
            return
        }
        do {
            try FileManager.default.removeItem(at: localURL)
            shelfMouseBridgeDidLog(
                "delete temp file success | id=\(item.id) path=\(localURL.path)"
            )
        } catch {
            shelfMouseBridgeDidLog(
                "delete temp file failed | id=\(item.id) path=\(localURL.path) error=\(error.localizedDescription)"
            )
        }
    }

    func normalizeStacksForCurrentPreference() {
        let recovered = stacks.normalize(autoDissolveSingle: autoDissolveSingleItemStack)
        if !recovered.isEmpty {
            shelf.add(existingItems: recovered)
        }
    }

    private func makeOperationPrompt() -> NSTextField {
        let filename = NSTextField(
            labelWithString: selectedOperationItem?.filename ?? selectedClipboardOperationItem?.title ?? ""
        )
        filename.alignment = .center
        filename.font = .systemFont(ofSize: 11, weight: .semibold)
        filename.lineBreakMode = .byTruncatingMiddle
        filename.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            filename.widthAnchor.constraint(equalToConstant: 190),
            filename.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight)
        ])
        return filename
    }

    private func makeOperationIcon() -> NSImageView {
        let imageView = NSImageView()
        imageView.image = selectedOperationItem?.displayImage ?? selectedClipboardOperationItem?.displayImage
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 34),
            imageView.heightAnchor.constraint(equalToConstant: TouchBarMetrics.maxImageHeight),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: TouchBarMetrics.maxImageHeight)
        ])
        operationIconImageView = imageView
        return imageView
    }

    private func makeOperationActions() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let icon = makeOperationIcon()
        let filename = makeOperationPrompt()
        let back = makeSymbolButton(title: "BACK", symbol: "chevron.left", action: #selector(backPressed), width: 96)
        let actionButtons: [NSView]
        if let clip = selectedClipboardOperationItem {
            let paste = makeButton(title: "PASTE", action: #selector(clipboardPastePressed), width: 72)
            paste.isEnabled = settings.isFeatureEnabled(.clipboardPasteButton)
            let copy = makeButton(title: "COPY", action: #selector(clipboardCopyPressed), width: 68)
            let open = makeButton(title: "OPEN", action: #selector(clipboardOpenPressed), width: 68)
            let pin = makeSymbolButton(
                title: selectedClipboardOperationItem?.pinned == true ? "UNPIN" : "PIN",
                symbol: selectedClipboardOperationItem?.pinned == true ? "pin.slash" : "pin",
                action: #selector(clipboardPinPressed),
                width: 92
            )
            pin.isEnabled = settings.isFeatureEnabled(.pinFavorites)
            let remove = makeSymbolButton(title: "REMOVE", symbol: "trash", action: #selector(clipboardDeletePressed), width: 96)
            actionButtons = canOpenClipboardItem(clip)
                ? [paste, copy, open, pin, remove]
                : [paste, copy, pin, remove]
        } else {
            let open = makeButton(title: "OPEN", action: #selector(openPressed), width: 62)
            let reveal = makeSymbolButton(title: "REVEAL", symbol: "finder", action: #selector(revealPressed), width: 96)
            let copy = makeSymbolButton(title: "COPY PATH", symbol: "doc.on.doc", action: #selector(copyPathPressed), width: 118)
            let share = makeSymbolButton(title: "SHARE", symbol: "square.and.arrow.up", action: #selector(sharePressed), width: 100)
            let pin = makeSymbolButton(
                title: selectedOperationItem.map { favoritesStore.isPinned(fileURL: $0.url) } == true ? "UNPIN" : "PIN",
                symbol: selectedOperationItem.map { favoritesStore.isPinned(fileURL: $0.url) } == true ? "pin.slash" : "pin",
                action: #selector(pinPressed),
                width: 92
            )
            pin.isEnabled = settings.isFeatureEnabled(.pinFavorites)
            let remove = makeSymbolButton(title: "REMOVE", symbol: "trash", action: #selector(removePressed), width: 96)
            actionButtons = [open, reveal, copy, share, pin, remove]
        }
        let actionStack = NSStackView(views: actionButtons)
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let actionDocument = NSView()
        actionDocument.translatesAutoresizingMaskIntoConstraints = false
        actionDocument.addSubview(actionStack)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = actionDocument
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [back, icon, filename, scrollView])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 1040),
            container.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            scrollView.widthAnchor.constraint(equalToConstant: operationActionViewportWidth),
            scrollView.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight),
            actionDocument.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
            actionDocument.widthAnchor.constraint(equalToConstant: operationActionDocumentWidth),
            actionStack.leadingAnchor.constraint(equalTo: actionDocument.leadingAnchor),
            actionStack.trailingAnchor.constraint(equalTo: actionDocument.trailingAnchor),
            actionStack.centerYAnchor.constraint(equalTo: actionDocument.centerYAnchor)
        ])
        return container
    }

    private var operationActionDocumentWidth: CGFloat {
        if let clip = selectedClipboardOperationItem {
            return canOpenClipboardItem(clip) ? 560 : 470
        }
        return 720
    }

    private var operationActionViewportWidth: CGFloat {
        selectedClipboardOperationItem != nil ? 380 : 440
    }

    private func makeButton(title: String, action: Selector, width: CGFloat) -> NSButton {
        let button = NativeTouchBarButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.alphaValue = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight),
            button.heightAnchor.constraint(lessThanOrEqualToConstant: TouchBarMetrics.rowHeight)
        ])
        return button
    }

    private func makeSymbolButton(
        title: String,
        symbol: String,
        action: Selector,
        width: CGFloat
    ) -> NSButton {
        let button = makeButton(title: title, action: action, width: width)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        return button
    }

    private func makeStackTitle() -> NSView {
        let stack = currentStackID.flatMap(stacks.stack(id:))
        let text: String
        if isSearchMode {
            text = searchQuery.isEmpty ? "Type to search ShelfBar" : "No Results"
        } else if shelfMode == .clipboard {
            text = "Empty Clipboard Shelf"
        } else if shelfMode == .recent {
            text = "No Recent Files"
        } else {
            text = stack?.name ?? "Stack"
        }
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let width: CGFloat
        if isSearchMode || shelfMode == .clipboard || shelfMode == .recent {
            width = 420
        } else {
            width = currentContainerItemCount == 0 ? 420 : 140
        }
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: width),
            label.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight)
        ])
        return label
    }

    private func makeSearchResultsPlaceholder(width: CGFloat = 236) -> NSView {
        let label = NSTextField(labelWithString: searchQuery.isEmpty ? searchPlaceholderText : "No Results")
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: width),
            label.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight)
        ])
        return label
    }

    private func makeEmptyShelfView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: TouchBarDropButton.drawerImage() ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "No Files")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.alignment = .left
        title.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: settings.isFeatureEnabled(.airDrop) ? "Drop files here or use AirDrop" : "Drop files here")
        hint.font = .systemFont(ofSize: 10, weight: .regular)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .left
        hint.lineBreakMode = .byTruncatingTail
        hint.translatesAutoresizingMaskIntoConstraints = false

        let text = NSStackView(views: [title, hint])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        text.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 340),
            container.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func makeModeSwitcherButton() -> NSButton {
        let title = shelfMode == .clipboard ? "FILES" : "CLIPS"
        let symbol = shelfMode == .clipboard ? "folder" : "doc.on.clipboard"
        return makeSymbolButton(title: title, symbol: symbol, action: #selector(toggleShelfModePressed), width: 90)
    }

    private func makeCounterLabel() -> NSTextField {
        let count: String
        if shelfMode == .clipboard {
            count = "\(clipboardStore.items.count) clip\(clipboardStore.items.count == 1 ? "" : "s")"
        } else if shelfMode == .recent {
            count = "\(recentItemsStore.items.count) recent"
        } else {
            let fileCount = displayedRootFileItems.count + stacks.rootStacks.count
            if settings.showDropCounterTotalSize {
                count = "\(fileCount) item\(fileCount == 1 ? "" : "s") · \(fileShelfSizeText())"
            } else {
                count = "\(fileCount) item\(fileCount == 1 ? "" : "s")"
            }
        }
        let label = NSTextField(labelWithString: count)
        label.alignment = .center
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: settings.showDropCounterTotalSize ? 150 : 92),
            label.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight)
        ])
        return label
    }

    private func makeSearchField(width: CGFloat = 410) -> NSTextField {
        let field = NSTextField(labelWithString: searchQuery.isEmpty ? searchPlaceholderText : searchQuery)
        field.alignment = .left
        field.font = .systemFont(ofSize: 15, weight: .medium)
        field.lineBreakMode = .byTruncatingMiddle
        field.textColor = searchQuery.isEmpty ? .secondaryLabelColor : .labelColor
        field.usesSingleLineMode = true
        field.wantsLayer = true
        field.layer?.cornerRadius = 7
        field.layer?.cornerCurve = .continuous
        field.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.82).cgColor
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: width),
            field.heightAnchor.constraint(equalToConstant: 28)
        ])
        activeSearchDisplay = field
        return field
    }

    private func makeRenameField() -> NSTextField {
        let field = NSTextField(labelWithString: renameDraft.isEmpty ? "Stack name" : renameDraft)
        field.alignment = .left
        field.font = .systemFont(ofSize: 15, weight: .semibold)
        field.lineBreakMode = .byTruncatingMiddle
        field.textColor = renameDraft.isEmpty ? .secondaryLabelColor : .labelColor
        field.usesSingleLineMode = true
        field.wantsLayer = true
        field.layer?.cornerRadius = 7
        field.layer?.cornerCurve = .continuous
        field.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.82).cgColor
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 430),
            field.heightAnchor.constraint(equalToConstant: TouchBarMetrics.rowHeight)
        ])
        activeRenameDisplay = field
        return field
    }

    private func configure(_ view: ShelfScrubberItemView, with result: ShelfSearchResult) {
        switch result {
        case let .file(item):
            view.configure(with: item, pinned: isPinned(item), allowsReorder: false)
        case let .stack(stack):
            view.configure(with: stack, itemCount: stacks.directItemCount(in: stack.id), allowsReorder: false)
        case let .stackFile(stackID, stackName, entry):
            if let item = entry.fileItem {
                view.configure(with: item, pinned: isPinned(item), allowsReorder: false)
                view.toolTip = "\(stackName) / \(item.url.path)"
            } else if let stack = stacks.stack(id: stackID) {
                view.configure(with: stack, itemCount: stacks.directItemCount(in: stack.id), allowsReorder: false)
            }
        case let .clipboard(item):
            view.configure(with: item)
        case let .recent(item):
            if let urlString = item.urlString,
               let url = URL(string: urlString),
               url.isFileURL {
                let fileItem = FileShelfModel.makeItem(
                    url: url,
                    id: item.id,
                    displayName: item.title,
                    kind: .file,
                    originalSourceDescription: "Recent",
                    originalFileURL: url,
                    localURL: nil
                )
                view.configure(with: fileItem, pinned: isPinned(fileItem), allowsReorder: false)
            } else {
                view.configure(with: ClipboardShelfItem(
                    id: item.id,
                    type: .text,
                    title: item.title,
                    copiedAt: item.touchedAt,
                    text: item.title,
                    urlString: item.urlString,
                    fileURLString: nil,
                    imageFilename: nil,
                    pinned: false
                ))
            }
        }
    }

    private func setStatus(_ status: AutoDropStatus) {
        guard currentStatus != status.rawValue else { return }
        currentStatus = status.rawValue
        print("[ShelfBar] status=\(status.rawValue)")
        onStatusChange?(status.rawValue)
    }

    private func updateMouseBridgeState(reason: String = #function) {
        interactionCoordinator.synchronize(
            ShelfInteractionCoordinator.Request(
                target: interactionTargetForCurrentState,
                mode: currentTouchBarMode,
                reason: reason
            )
        )
    }

    private var interactionTargetForCurrentState: ShelfInteractionCoordinator.Target {
        guard isPresented, !isShowingDropTarget else { return .inactive }
        if isRenamingStack || selectedOperationItemID != nil || selectedClipboardOperationItemID != nil {
            return .action
        }
        guard settings.isFeatureEnabled(.clipboardShelf) || shelfMode != .clipboard else {
            return .inactive
        }
        return .shelf
    }

    func dumpInteractionDebugState(reason: String = "manual") {
        interactionCoordinator.dumpState(reason: "debug-dump:\(reason)", mode: currentTouchBarMode)
    }

    func runInteractionStabilityStressTest(iterations: Int = 200) {
        let savedMode = shelfMode
        let savedSearchMode = isSearchMode
        let savedSearchQuery = searchQuery
        let savedStackID = currentStackID
        let savedStackPath = stackNavigationPath
        let savedSelectedOperationID = selectedOperationItemID
        let savedSelectedClipboardOperationID = selectedClipboardOperationItemID
        let savedRenameState = (isRenamingStack, renameStackID, renameDraft)
        let stackIDs = stacks.rootStacks.map(\.id)

        interactionCoordinator.dumpState(reason: "stress-before", mode: currentTouchBarMode)
        for index in 0..<iterations {
            selectedOperationItemID = nil
            selectedClipboardOperationItemID = nil
            transientOperationItem = nil
            transientClipboardOperationItem = nil
            isRenamingStack = false
            renameStackID = nil
            switch index % 8 {
            case 0:
                shelfMode = .file
                isSearchMode = false
                currentStackID = nil
                stackNavigationPath.removeAll()
            case 1:
                shelfMode = .clipboard
                isSearchMode = false
                currentStackID = nil
                stackNavigationPath.removeAll()
            case 2:
                shelfMode = .file
                shelfModeBeforeSearch = .file
                isSearchMode = true
                searchQuery = index.isMultiple(of: 2) ? "" : "stress"
                currentStackID = nil
                stackNavigationPath.removeAll()
                updateSearchResults()
            case 3:
                shelfMode = .recent
                isSearchMode = false
                currentStackID = nil
                stackNavigationPath.removeAll()
            case 4:
                if let id = stackIDs.first {
                    shelfMode = .file
                    isSearchMode = false
                    currentStackID = id
                    stackNavigationPath = [id]
                }
            case 5:
                if let item = shelf.items.first {
                    shelfMode = .file
                    isSearchMode = false
                    currentStackID = nil
                    stackNavigationPath.removeAll()
                    selectedOperationItemID = item.id
                    transientOperationItem = item
                }
            case 6:
                if let clip = clipboardStore.items.first {
                    shelfMode = .clipboard
                    isSearchMode = false
                    currentStackID = nil
                    stackNavigationPath.removeAll()
                    selectedClipboardOperationItemID = clip.id
                }
            default:
                if let id = stackIDs.first {
                    shelfMode = .file
                    isSearchMode = false
                    currentStackID = id
                    stackNavigationPath = [id]
                    isRenamingStack = true
                    renameStackID = id
                    renameDraft = stacks.stack(id: id)?.name ?? ""
                }
            }
            refreshTouchBarItems(forceRebuild: true)
            updateMouseBridgeState(reason: "stress-loop-\(index)")
        }

        shelfMode = savedMode
        isSearchMode = savedSearchMode
        searchQuery = savedSearchQuery
        currentStackID = savedStackID
        stackNavigationPath = savedStackPath
        selectedOperationItemID = savedSelectedOperationID
        selectedClipboardOperationItemID = savedSelectedClipboardOperationID
        isRenamingStack = savedRenameState.0
        renameStackID = savedRenameState.1
        renameDraft = savedRenameState.2
        updateSearchResults()
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState(reason: "stress-restore")
        interactionCoordinator.dumpState(reason: "stress-after iterations=\(iterations)", mode: currentTouchBarMode)
        let health = interactionStabilityHealthForTests()
        shelfMouseBridgeDidLog(
            "Interaction stress health | iterations=\(iterations) tapResolvable=\(health.tapResolvable) neutral=\(health.gestureNeutral)"
        )
    }

    func interactionStabilityHealthForTests() -> (tapResolvable: Bool, gestureNeutral: Bool) {
        (
            tapResolvable: hasDataBackedTapTargetForCurrentMode(),
            gestureNeutral: shelfMouseBridgeController.isGestureNeutralForDebug()
                && actionMenuMouseBridgeController.isGestureNeutralForDebug()
        )
    }

    private func hasDataBackedTapTargetForCurrentMode() -> Bool {
        if isRenamingStack { return true }
        if selectedOperationItemID != nil || selectedClipboardOperationItemID != nil { return true }
        if isSearchMode { return !searchResults.isEmpty }
        if shelfMode == .recent { return !recentItemsStore.items.isEmpty }
        if shelfMode == .clipboard { return !clipboardStore.items.isEmpty }
        if currentStackID != nil { return !currentStackDisplayEntries.isEmpty }
        return rootDisplayEntries.contains { !$0.isDivider }
    }

    @objc private func clearPressed() {
        if isSearchMode {
            endSearchMode()
        } else if shelfMode == .clipboard {
            clipboardStore.clear(includePinned: true, clearSystemPasteboard: true)
            refreshTouchBarItems(forceRebuild: true)
            updateMouseBridgeState()
        } else if shelfMode == .recent {
            recentItemsStore.clear()
            refreshTouchBarItems(forceRebuild: true)
            updateMouseBridgeState()
        } else {
            clearShelf()
        }
    }

    @objc private func closePressed() {
        closeShelfFromUser()
    }

    @objc private func openPressed() {
        guard let item = selectedOperationItem else { return }
        NSWorkspace.shared.open(item.url)
        recentItemsStore.record(fileURL: item.url, title: item.filename)
        backPressed()
    }

    @objc private func removePressed() {
        guard let id = selectedOperationItemID else { return }
        let item = selectedOperationItem
        let removesRecentOnly = shelfMode == .recent
            || (detailReturnToSearch && shelfModeBeforeSearch == .recent)
        selectedOperationItemID = nil
        if let currentStackID {
            removeStackItem(id: id, from: currentStackID)
        } else if removesRecentOnly {
            transientOperationItem = nil
            recentItemsStore.remove(id: id)
        } else if let item {
            removeRootFileReference(item)
            transientOperationItem = nil
        } else {
            removeShelfItem(id: id)
        }
        if detailReturnToSearch {
            updateSearchResults()
        }
        returnFromActionMenu(forceRebuild: true)
    }

    @objc private func backPressed() {
        returnFromActionMenu(forceRebuild: false)
    }

    private func returnFromActionMenu(forceRebuild: Bool) {
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        clearTransientDetail()
        if detailReturnToSearch {
            detailReturnToSearch = false
            currentStackID = searchReturnStackID
            stackNavigationPath = searchReturnStackNavigationPath
            renderedStackItemIDs.removeAll()
            isSearchMode = true
            updateSearchResults()
            refreshTouchBarItems(forceRebuild: true)
            ensureSystemModalPresented()
            searchInputHost.begin(query: searchQuery)
            updateMouseBridgeState()
            restoreSearchAnchorIfNeeded()
            scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
            searchReturnStackID = nil
            searchReturnStackNavigationPath = []
            return
        }
        refreshTouchBarItems(forceRebuild: forceRebuild)
        updateMouseBridgeState()
        setStatus(.shelfActive)
    }

    @objc private func revealPressed() {
        guard let item = selectedOperationItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        recentItemsStore.record(fileURL: item.url, title: item.filename)
        backPressed()
    }

    @objc private func copyPathPressed() {
        guard let item = selectedOperationItem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
        recentItemsStore.record(fileURL: item.url, title: item.filename)
        backPressed()
    }

    @objc private func sharePressed() {
        guard let item = selectedOperationItem else { return }
        NSSharingServicePicker(items: [item.url]).show(
            relativeTo: .zero,
            of: NSFunctionRow._topLevelViews().last ?? NSView(),
            preferredEdge: .maxY
        )
        recentItemsStore.record(fileURL: item.url, title: item.filename)
    }

    @objc private func pinPressed() {
        guard let item = selectedOperationItem else { return }
        let selectedURL = item.url
        favoritesStore.toggle(fileURL: item.url)
        rebindSelectedOperationItem(afterPinChangeFor: selectedURL)
        refreshTouchBarItems(forceRebuild: true)
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
        updateMouseBridgeState()
    }

    private func rebindSelectedOperationItem(afterPinChangeFor url: URL) {
        let key = fileURLKey(url)
        if let item = visibleFileItemsForCurrentContainer().first(where: { fileURLKey($0.url) == key }) {
            selectedOperationItemID = item.id
            transientOperationItem = item
        } else if let transientOperationItem,
                  fileURLKey(transientOperationItem.url) == key {
            selectedOperationItemID = transientOperationItem.id
        } else {
            selectedOperationItemID = nil
            transientOperationItem = nil
        }
    }

    @objc private func clipboardPastePressed() {
        guard let item = selectedClipboardOperationItem else { return }
        guard clipboardStore.writeToPasteboard(item) else {
            showAlert(title: "Paste failed", message: "ShelfBar could not write this clipboard item back to the pasteboard.")
            return
        }
        recentItemsStore.record(clipboard: item)
        guard accessibilityTrustedForPaste(reason: "paste-initial") else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else { return }
                if self.accessibilityTrustedForPaste(reason: "paste-retry") {
                    self.sendCommandV()
                    self.backPressed()
                } else {
                    self.showAccessibilityPermissionAlert()
                    self.backPressed()
                }
            }
            return
        }
        sendCommandV()
        backPressed()
    }

    @objc private func clipboardCopyPressed() {
        guard let item = selectedClipboardOperationItem else { return }
        _ = clipboardStore.writeToPasteboard(item)
        recentItemsStore.record(clipboard: item)
        backPressed()
    }

    @objc private func clipboardOpenPressed() {
        guard let item = selectedClipboardOperationItem,
              let url = openURL(for: item)
        else { return }
        NSWorkspace.shared.open(url)
        recentItemsStore.record(clipboard: item)
        backPressed()
    }

    @objc private func clipboardPinPressed() {
        guard let id = selectedClipboardOperationItemID else { return }
        clipboardStore.togglePinned(id: id)
        selectedClipboardOperationItemID = id
        refreshTouchBarItems(forceRebuild: true)
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
        updateMouseBridgeState()
    }

    @objc private func clipboardDeletePressed() {
        guard let id = selectedClipboardOperationItemID else { return }
        selectedClipboardOperationItemID = nil
        if transientClipboardOperationItem?.id == id {
            transientClipboardOperationItem = nil
        }
        clipboardStore.remove(id: id, clearSystemPasteboardIfCurrent: true)
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState()
    }

    private func canOpenClipboardItem(_ item: ClipboardShelfItem) -> Bool {
        openURL(for: item) != nil
    }

    private func openURL(for item: ClipboardShelfItem) -> URL? {
        switch item.type {
        case .url:
            return item.urlString.flatMap(URL.init(string:))
        case .file:
            return item.fileURLString.flatMap(URL.init(string:))
        case .image:
            guard let imageFilename = item.imageFilename else { return nil }
            return ClipboardStore.imageDirectory.appendingPathComponent(imageFilename)
        case .text:
            guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: text),
                  url.scheme != nil
            else { return nil }
            return url
        }
    }

    @objc private func toggleShelfModePressed() {
        if shelfMode == .file {
            guard settings.isFeatureEnabled(.clipboardShelf) else { return }
            shelfMode = .clipboard
            currentStackID = nil
            stackNavigationPath.removeAll()
        } else {
            shelfMode = .file
        }
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        isSearchMode = false
        searchInputHost.end()
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode)
    }

    @objc private func recentPressed() {
        guard settings.isFeatureEnabled(.recentFiles) else { return }
        shelfMode = shelfMode == .recent ? .file : .recent
        currentStackID = nil
        stackNavigationPath.removeAll()
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        isSearchMode = false
        searchInputHost.end()
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode)
    }

    @objc private func searchPressed() {
        beginSearch()
    }

    @objc private func searchCancelPressed() {
        endSearchMode()
    }

    @objc private func searchClearPressed() {
        searchQuery = ""
        searchResults = []
        activeSearchDisplay?.stringValue = searchPlaceholderText
        searchInputHost.update(query: "")
        refreshTouchBarItems(forceRebuild: true)
        ensureSystemModalPresented()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
        updateMouseBridgeState(reason: "search-clear")
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        applySearchQuery(sender.stringValue)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        applySearchQuery(field.stringValue)
    }

    private func applySearchQuery(_ query: String) {
        searchQuery = query
        activeSearchDisplay?.stringValue = query.isEmpty ? searchPlaceholderText : query
        activeSearchDisplay?.textColor = query.isEmpty ? .secondaryLabelColor : .labelColor
        updateSearchResults()
        refreshTouchBarItems(forceRebuild: true)
        ensureSystemModalPresented()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
        updateMouseBridgeState(reason: "search-query-update")
    }

    private func restoreSearchAnchorIfNeeded() {
        guard let anchor = searchReturnAnchorResultID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self,
                  self.isSearchMode,
                  let index = self.searchResults.firstIndex(where: { $0.id == anchor })
            else { return }
            self.scrubber?.scrollItem(at: index, to: .center)
            self.shelfMouseBridgeController.requestHitRegionRebuild(mode: self.currentTouchBarMode)
        }
    }

    @objc private func stackRenamePressed() {
        guard let currentStackID,
              let stack = stacks.stack(id: currentStackID)
        else { return }
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        clearTransientDetail()
        isSearchMode = false
        detailReturnToSearch = false
        searchInputHost.end()
        isRenamingStack = true
        renameStackID = currentStackID
        renameDraft = stack.name
        refreshTouchBarItems(forceRebuild: true)
        ensureSystemModalPresented()
        renameInputHost.begin(query: renameDraft)
        updateMouseBridgeState()
    }

    @objc private func stackUnstackPressed() {
        guard let stackID = currentStackID,
              let stack = stacks.stack(id: stackID)
        else { return }
        let stackOrderKey = RootDisplayEntry.stack(stack).orderKey
        let recoveredItems = stack.entries.compactMap(\.fileItem)
        let childStacks = stacks.childStacks(of: stackID)
        let replacementKeys = recoveredItems.map { RootDisplayEntry.file($0).orderKey }
            + childStacks.map { RootDisplayEntry.stack($0).orderKey }

        currentStackID = nil
        stackNavigationPath.removeAll()
        renderedStackItemIDs.removeAll()
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        clearTransientDetail()
        detailReturnToSearch = false
        endStackRename()

        _ = stacks.dissolveToRoot(id: stackID)
        if !recoveredItems.isEmpty {
            shelf.add(existingItems: recoveredItems)
        }
        replaceRootOrderEntry(stackOrderKey, with: replacementKeys)
        updateSearchResults()
        refreshTouchBarItems(forceRebuild: true)
        ensureSystemModalPresented()
        updateMouseBridgeState()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
        shelfMouseBridgeDidLog(
            "Stack unstacked | stackID=\(stackID) files=\(recoveredItems.count) childStacks=\(childStacks.count)"
        )
    }

    @objc private func cancelStackRenamePressed() {
        endStackRename()
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
    }

    @objc private func saveStackRenamePressed() {
        guard let stackID = renameStackID else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showAlert(title: "Name required", message: "Enter a stack name before saving.")
            return
        }
        stacks.rename(id: stackID, name: trimmed)
        updateSearchResults()
        endStackRename()
        currentStackID = stackID
        refreshTouchBarItems(forceRebuild: true)
        updateMouseBridgeState()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
    }

    private func applyRenameDraft(_ value: String) {
        renameDraft = value
        activeRenameDisplay?.stringValue = value.isEmpty ? "Stack name" : value
        activeRenameDisplay?.textColor = value.isEmpty ? .secondaryLabelColor : .labelColor
    }

    @objc private func stackBackPressed() {
        if isRenamingStack {
            cancelStackRenamePressed()
            return
        }
        if detailReturnToSearch {
            backPressed()
            return
        }
        if shelfMode == .recent {
            shelfMode = .file
            selectedOperationItemID = nil
            selectedClipboardOperationItemID = nil
            refreshTouchBarItems(forceRebuild: true)
            scheduleVisibleContentRefresh(mode: currentTouchBarMode)
            updateMouseBridgeState()
            return
        }
        leaveStack()
    }

    func enterStack(id: UUID) {
        guard let stack = stacks.stack(id: id) else { return }
        if stack.parentStackID == currentStackID {
            stackNavigationPath.append(id)
        } else if currentStackID != id {
            var ancestry: [UUID] = []
            var cursor: ShelfStack? = stack
            var visited: Set<UUID> = []
            while let value = cursor, visited.insert(value.id).inserted {
                ancestry.append(value.id)
                cursor = value.parentStackID.flatMap(stacks.stack(id:))
            }
            stackNavigationPath = ancestry.reversed()
        }
        let loadedItems = stacks.fileItems(in: id)
        shelfMouseBridgeDidLog("stack enter | stackID=\(id)")
        shelfMouseBridgeDidLog("enter stack id=\(id)")
        shelfMouseBridgeDidLog("stack item count=\(stack.entries.count)")
        shelfMouseBridgeDidLog("nested stack count=\(stacks.childStacks(of: id).count)")
        for item in loadedItems {
            shelfMouseBridgeDidLog("stack model item filename=\(item.filename)")
        }
        renderedStackItemIDs.removeAll()
        currentStackID = id
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        refreshTouchBarItems()
        scheduleVisibleContentRefresh(mode: "stack:\(id.uuidString)")
        updateMouseBridgeState()
    }

    func leaveStack() {
        if let currentStackID {
            shelfMouseBridgeDidLog("stack back | stackID=\(currentStackID)")
        }
        if !stackNavigationPath.isEmpty {
            stackNavigationPath.removeLast()
        }
        currentStackID = stackNavigationPath.last
        renderedStackItemIDs.removeAll()
        selectedOperationItemID = nil
        selectedClipboardOperationItemID = nil
        if currentStackID == nil {
            pendingMainAttachRoute = "back-to-root-main-render"
        }
        refreshTouchBarItems()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode)
        updateMouseBridgeState()
    }

    func shelfScrubberItemView(
        _ view: ShelfScrubberItemView,
        didBeginTouchReorderAt point: NSPoint
    ) -> Bool {
        guard view.allowsInternalReorder,
              let itemID = reorderID(for: view),
              let parent = touchReorderParent(for: view)
        else { return false }
        if currentStackID == nil,
           let item = view.representedItem,
           isPinnedRootItem(item) {
            shelfMouseBridgeDidLog("StabilityFix6 touch reorder rejected pinned root item id=\(item.id)")
            return false
        }

        parent.layoutSubtreeIfNeeded()
        let touchPoint = view.convert(point, to: parent)
        let began = shelfMouseBridgeController.beginDirectTouchDrag(
            sourceView: view,
            itemID: itemID,
            at: touchPoint,
            in: parent
        )
        guard began else { return false }
        isTouchReorderGestureInProgress = true
        suppressNativeSelectionUntil = ProcessInfo.processInfo.systemUptime + 0.25
        shelfMouseBridgeController.updateDirectTouchDrag(itemID: itemID, at: touchPoint, in: parent)
        shelfMouseBridgeDidLog("StabilityFix6 touch reorder long press began | item id=\(itemID)")
        return true
    }

    func shelfScrubberItemView(
        _ view: ShelfScrubberItemView,
        didUpdateTouchReorderAt point: NSPoint
    ) {
        guard isTouchReorderGestureInProgress,
              let itemID = reorderID(for: view),
              let parent = touchReorderParent(for: view)
        else { return }
        shelfMouseBridgeController.updateDirectTouchDrag(
            itemID: itemID,
            at: view.convert(point, to: parent),
            in: parent
        )
    }

    func shelfScrubberItemView(
        _ view: ShelfScrubberItemView,
        didEndTouchReorderAt point: NSPoint,
        cancelled: Bool
    ) {
        guard isTouchReorderGestureInProgress,
              let itemID = reorderID(for: view),
              let parent = touchReorderParent(for: view)
        else {
            isTouchReorderGestureInProgress = false
            suppressNativeSelectionUntil = ProcessInfo.processInfo.systemUptime + 0.25
            shelfMouseBridgeController.resetTransientInteractionState(reason: "touch-reorder-end-without-parent")
            return
        }
        shelfMouseBridgeController.endDirectTouchDrag(
            itemID: itemID,
            at: view.convert(point, to: parent),
            in: parent,
            cancelled: cancelled
        )
        isTouchReorderGestureInProgress = false
        suppressNativeSelectionUntil = ProcessInfo.processInfo.systemUptime + 0.25
    }

    private func touchReorderParent(for view: ShelfScrubberItemView) -> NSView? {
        let candidates = [
            NSFunctionRow._topLevelViews().last,
            touchBar.item(forIdentifier: ItemID.mainLayout)?.view
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            if view === candidate || view.isDescendant(of: candidate) {
                return candidate
            }
        }

        var root: NSView = view
        while let superview = root.superview {
            root = superview
        }
        return root.bounds.isEmpty ? nil : root
    }

    func shelfMouseBridgeHit(
        atTouchBarPoint point: NSPoint,
        in parentView: NSView
    ) -> ShelfBridgeHit? {
        if let button = shelfMouseBridgeButtonHit(at: point, in: parentView) {
            return ShelfBridgeHit(
                id: button.title.uppercased(),
                item: nil,
                stackID: nil,
                view: button
            )
        }

        var candidate = parentView.hitTest(point)
        while let view = candidate, view !== parentView {
            if shelfMode == .recent,
               let itemView = view as? ShelfScrubberItemView,
               let recent = recentItem(for: itemView) {
                return ShelfBridgeHit(id: "recent:\(recent.id)", searchResultID: recent.id, view: itemView)
            }
            if isSearchMode,
               let itemView = view as? ShelfScrubberItemView,
               let result = searchResult(for: itemView) {
                return ShelfBridgeHit(id: "search:\(result.id)", searchResultID: result.id, view: itemView)
            }
            if let itemView = view as? ShelfScrubberItemView,
               let item = itemView.representedItem {
                let resolved = visibleFileItemForInteraction(matching: item)
                let canReorder = itemView.allowsInternalReorder && !isPinnedRootItem(resolved)
                return ShelfBridgeHit(
                    id: "shelf:\(fileURLKey(resolved.url))",
                    item: resolved,
                    view: itemView,
                    allowsReorder: canReorder
                )
            }
            if let itemView = view as? ShelfScrubberItemView,
               let item = itemView.representedClipboardItem {
                return ShelfBridgeHit(id: "clipboard:\(item.id)", clipboardItem: item, view: itemView)
            }
            if let itemView = view as? ShelfScrubberItemView,
               let stackID = itemView.representedStackID {
                return ShelfBridgeHit(
                    id: "stack:\(stackID)",
                    stackID: stackID,
                    view: itemView,
                    allowsReorder: itemView.allowsInternalReorder
                )
            }
            if let button = view as? NSButton,
               button.isEnabled,
               button.action != nil {
                return ShelfBridgeHit(
                    id: button.title.uppercased(),
                    item: nil,
                    stackID: nil,
                    view: button
                )
            }
            candidate = view.superview
        }

        for view in descendantBridgeViews(of: parentView) {
            let frame = view.superview?.convert(view.frame, to: parentView) ?? .zero
            guard frame.contains(point) else { continue }
            if shelfMode == .recent,
               let itemView = view as? ShelfScrubberItemView,
               let recent = recentItem(for: itemView) {
                return ShelfBridgeHit(id: "recent:\(recent.id)", searchResultID: recent.id, view: itemView)
            }
            if isSearchMode,
               let itemView = view as? ShelfScrubberItemView,
               let result = searchResult(for: itemView) {
                return ShelfBridgeHit(id: "search:\(result.id)", searchResultID: result.id, view: itemView)
            }
            if let itemView = view as? ShelfScrubberItemView,
               let item = itemView.representedItem {
                let resolved = visibleFileItemForInteraction(matching: item)
                let canReorder = itemView.allowsInternalReorder && !isPinnedRootItem(resolved)
                return ShelfBridgeHit(
                    id: "shelf:\(fileURLKey(resolved.url))",
                    item: resolved,
                    view: itemView,
                    allowsReorder: canReorder
                )
            }
            if let itemView = view as? ShelfScrubberItemView,
               let item = itemView.representedClipboardItem {
                return ShelfBridgeHit(id: "clipboard:\(item.id)", clipboardItem: item, view: itemView)
            }
            if let itemView = view as? ShelfScrubberItemView,
               let stackID = itemView.representedStackID {
                return ShelfBridgeHit(
                    id: "stack:\(stackID)",
                    stackID: stackID,
                    view: itemView,
                    allowsReorder: itemView.allowsInternalReorder
                )
            }
            if let button = view as? NSButton,
               button.isEnabled,
               button.action != nil {
                return ShelfBridgeHit(
                    id: button.title.uppercased(),
                    item: nil,
                    stackID: nil,
                    view: button
                )
            }
        }
        return nil
    }

    private func shelfMouseBridgeButtonHit(at point: NSPoint, in parentView: NSView) -> NSButton? {
        descendantBridgeViews(of: parentView)
            .compactMap { $0 as? NSButton }
            .first { button in
                guard button.isEnabled,
                      !button.isHidden,
                      button.alphaValue > 0.01,
                      button.action != nil
                else { return false }
                let localPoint = button.convert(point, from: parentView)
                return button.bounds.contains(localPoint)
            }
    }

    private func searchResult(for view: ShelfScrubberItemView) -> ShelfSearchResult? {
        if let item = view.representedItem {
            return searchResults.first {
                if case let .file(result) = $0 { return result.id == item.id }
                if case let .stackFile(_, _, entry) = $0 { return entry.id == item.id }
                if case let .recent(result) = $0 { return result.id == item.id }
                return false
            }
        }
        if let item = view.representedClipboardItem {
            return searchResults.first {
                if case let .clipboard(result) = $0 { return result.id == item.id }
                if case let .recent(result) = $0 { return result.id == item.id }
                return false
            }
        }
        if let stackID = view.representedStackID {
            return searchResults.first {
                if case let .stack(stack) = $0 { return stack.id == stackID }
                return false
            }
        }
        return nil
    }

    private func recentItem(for view: ShelfScrubberItemView) -> RecentShelfItem? {
        if let item = view.representedItem {
            return recentItemsStore.items.first { $0.id == item.id }
        }
        if let item = view.representedClipboardItem {
            return recentItemsStore.items.first { $0.id == item.id }
        }
        return nil
    }

    func shelfMouseBridgeRegisteredHitRegionNames(in parentView: NSView) -> [String] {
        var names: [String] = []
        for identifier in touchBar.defaultItemIdentifiers {
            guard let rootView = touchBar.item(forIdentifier: identifier)?.view else { continue }
            let views = [rootView] + descendantBridgeViews(of: rootView)
            for view in views {
                if let itemView = view as? ShelfScrubberItemView,
                   let item = itemView.representedItem,
                   let resolved = Optional(visibleFileItemForInteraction(matching: item)),
                   let index = visibleFileItemsForCurrentContainer().firstIndex(where: {
                       fileURLKey($0.url) == fileURLKey(resolved.url)
                   }) {
                    let prefix = isPinnedRootItem(resolved) ? "Pinned Shelf item" : "Shelf item"
                    names.append("\(prefix) \(index + 1)")
                } else if let itemView = view as? ShelfScrubberItemView,
                          let item = itemView.representedClipboardItem {
                    names.append("Clipboard item \(item.title)")
                } else if let itemView = view as? ShelfScrubberItemView,
                          let stackID = itemView.representedStackID,
                          let stack = stacks.stack(id: stackID) {
                    names.append("Stack \(stack.name)")
                } else if let button = view as? NSButton,
                          button.isEnabled,
                          button.action != nil {
                    names.append(button.title.uppercased())
                }
            }
        }
        return names
    }

    func shelfMouseBridgeDidClick(itemID: UUID) {
        guard selectedOperationItemID == nil,
              let item = visibleFileItemForInteraction(id: itemID)
        else { return }
        selectOperationItem(item)
        shelfMouseBridgeDidLog("action menu opened item id=\(item.id)")
        refreshTouchBarItems()
        updateMouseBridgeState()
        setStatus(.shelfActive)
    }

    func shelfMouseBridgeDidClickFile(fileURL: URL, fallbackItemID: UUID) {
        guard selectedOperationItemID == nil else { return }
        let key = fileURLKey(fileURL)
        let item = visibleFileItemsForCurrentContainer().first { fileURLKey($0.url) == key }
            ?? visibleFileItemForInteraction(id: fallbackItemID)
        guard let item else {
            shelfMouseBridgeDidLog(
                "pinned/file mouse click skipped | reason=no canonical match url=\(fileURL.absoluteString) fallback id=\(fallbackItemID)"
            )
            return
        }
        selectOperationItem(item)
        shelfMouseBridgeDidLog(
            "pinned/file mouse click resolved | canonical url=\(fileURL.absoluteString) item id=\(item.id)"
        )
        refreshTouchBarItems()
        updateMouseBridgeState()
        setStatus(.shelfActive)
    }

    func shelfMouseBridgeDidClickClipboard(itemID: UUID) {
        guard selectedClipboardOperationItemID == nil,
              clipboardStore.item(id: itemID) != nil
        else { return }
        selectedClipboardOperationItemID = itemID
        shelfMouseBridgeDidLog("clipboard action menu opened item id=\(itemID)")
        refreshTouchBarItems()
        updateMouseBridgeState()
        setStatus(.shelfActive)
    }

    func shelfMouseBridgeDidClickSearchResult(resultID: UUID) {
        if isSearchMode,
           let index = searchResults.firstIndex(where: { $0.id == resultID }) {
            handleSearchSelection(at: index)
        } else if shelfMode == .recent,
                  let index = recentItemsStore.items.firstIndex(where: { $0.id == resultID }) {
            handleRecentSelection(at: index)
        }
    }

    func shelfMouseBridgeDidClickStack(stackID: UUID) {
        guard let stack = stacks.stack(id: stackID), stack.parentStackID == currentStackID else { return }
        enterStack(id: stackID)
    }

    func shelfMouseBridgeCanDrop(sourceItemID: UUID, onto hit: ShelfBridgeHit) -> Bool {
        guard let source = visibleFileItemForInteraction(id: sourceItemID) else { return false }
        if isPinnedRootItem(source) { return false }
        if let targetItemID = hit.item?.id {
            guard let target = visibleFileItemForInteraction(id: targetItemID) else { return false }
            if isPinnedRootItem(target) { return false }
            return fileURLKey(target.url) != fileURLKey(source.url)
        }
        if let stackID = hit.stackID {
            return stacks.stack(id: stackID)?.parentStackID == currentStackID
        }
        return false
    }

    func shelfMouseBridgeDidMerge(sourceItemID: UUID, targetItemID: UUID) {
        guard let source = visibleFileItemForInteraction(id: sourceItemID),
              let target = visibleFileItemForInteraction(id: targetItemID),
              fileURLKey(source.url) != fileURLKey(target.url)
        else { return }
        let sourceID = source.id
        let targetID = target.id
        let previousRootEntries = currentStackID == nil ? rootOrderedEntries : []

        shelfMouseBridgeDidLog(
            "stack create source item | id=\(sourceID) url=\(source.url.absoluteString)"
        )
        shelfMouseBridgeDidLog(
            "stack target item | id=\(targetID) url=\(target.url.absoluteString)"
        )
        animateStackMerge(sourceItemID: sourceID, targetItemID: targetID) { [weak self] in
            guard let self,
                  self.visibleFileItemForInteraction(id: sourceID) != nil,
                  self.visibleFileItemForInteraction(id: targetID) != nil
            else { return }
            let stackID = self.stacks.create(
                name: "",
                items: [target, source],
                parentStackID: self.currentStackID
            )
            if self.currentStackID == nil,
               let stack = self.stacks.stack(id: stackID),
               let nextEntries = self.rootEntriesByCreatingStackAtDropTarget(
                previousEntries: previousRootEntries,
                sourceID: sourceID,
                targetID: targetID,
                stack: stack
               ) {
                self.saveRootDisplayOrder(nextEntries)
                self.shelfMouseBridgeDidLog(
                    "stack root order committed | stackID=\(stackID) "
                        + "targetID=\(targetID) orderIndex=\(nextEntries.firstIndex(where: { $0.id == stackID }).map(String.init) ?? "nil")"
                )
            }
            if let parentID = self.currentStackID {
                self.stacks.removeFiles(ids: [sourceID, targetID], from: parentID)
            } else {
                self.removeRootVisibleItemsAfterStacking(ids: [sourceID, targetID])
            }
            self.shelfMouseBridgeDidLog(
                "stack add item | stackID=\(stackID) parent=\(self.currentStackID?.uuidString ?? "root") count=2 source=\(sourceID) target=\(targetID)"
            )
            self.animateStackDrop(stackID: stackID)
        }
    }

    private func rootEntriesByCreatingStackAtDropTarget(
        previousEntries: [RootDisplayEntry],
        sourceID: UUID,
        targetID: UUID,
        stack: ShelfStack
    ) -> [RootDisplayEntry]? {
        guard previousEntries.contains(where: { $0.id == sourceID }),
              previousEntries.contains(where: { $0.id == targetID })
        else { return nil }
        let stackedIDs: Set<UUID> = [sourceID, targetID]
        var nextEntries = previousEntries.filter { !stackedIDs.contains($0.id) }
        let targetSlot = previousEntries
            .prefix { $0.id != targetID }
            .filter { !stackedIDs.contains($0.id) }
            .count
        let unpinnedFloor = nextEntries.filter(isPinnedRootEntry).count
        let insertionIndex = min(max(targetSlot, unpinnedFloor), nextEntries.count)
        nextEntries.insert(.stack(stack), at: insertionIndex)
        return pinnedFirstRootEntries(nextEntries)
    }

    func shelfMouseBridgeDidDrop(itemID: UUID, ontoStack stackID: UUID) {
        guard let item = visibleFileItemForInteraction(id: itemID),
              stacks.stack(id: stackID)?.parentStackID == currentStackID
        else { return }
        shelfMouseBridgeDidLog(
            "stack add item | stackID=\(stackID) sourceItemID=\(item.id) url=\(item.url.absoluteString)"
        )
        stacks.add(item: item, to: stackID)
        if let parentID = currentStackID {
            stacks.removeFiles(ids: [item.id], from: parentID)
        } else {
            saveRootDisplayOrder(rootOrderedEntries.filter { $0.id != item.id })
            removeRootVisibleItemsAfterStacking(ids: [item.id])
        }
        animateStackDrop(stackID: stackID)
    }

    private func removeRootVisibleItemsAfterStacking(ids: Set<UUID>) {
        let visible = displayedRootFileItems.filter { ids.contains($0.id) }
        let shelfIDs = Set(shelf.items.map(\.id))
        let favoriteKeys = Set(favoritesStore.fileURLStrings)
        var shelfRemoveIDs = Set<UUID>()
        for item in visible {
            if shelfIDs.contains(item.id) {
                shelfRemoveIDs.insert(item.id)
            } else if favoriteKeys.contains(item.url.standardizedFileURL.absoluteString) {
                favoritesStore.remove(fileURL: item.url)
            }
        }
        if !shelfRemoveIDs.isEmpty {
            shelf.remove(ids: shelfRemoveIDs)
        }
    }

    func shelfMouseBridgeInsertionIndex(
        atTouchBarPoint point: NSPoint,
        in parentView: NSView
    ) -> Int? {
        let itemViews = descendantBridgeViews(of: parentView)
            .compactMap { $0 as? ShelfScrubberItemView }
            .filter { view in
                guard view.allowsInternalReorder else { return false }
                guard let id = reorderID(for: view) else { return false }
                if currentStackID == nil {
                    if let item = view.representedItem {
                        return !isPinnedRootItem(item)
                    }
                    return rootOrderedEntries.contains(where: { $0.id == id })
                }
                return currentStackDisplayEntries.contains(where: { $0.id == id })
            }
            .sorted { left, right in
                let leftFrame = left.superview?.convert(left.frame, to: parentView) ?? .zero
                let rightFrame = right.superview?.convert(right.frame, to: parentView) ?? .zero
                return leftFrame.midX < rightFrame.midX
            }
        guard !itemViews.isEmpty else { return 0 }
        let firstFrame = itemViews[0].superview?.convert(itemViews[0].frame, to: parentView) ?? .zero
        let lastFrame = itemViews[itemViews.count - 1].superview?.convert(itemViews[itemViews.count - 1].frame, to: parentView) ?? .zero
        if !firstFrame.isEmpty,
           point.x <= firstFrame.minX + firstFrame.width * 0.35 {
            return 0
        }
        if !lastFrame.isEmpty,
           point.x >= lastFrame.maxX - lastFrame.width * 0.35 {
            return itemViews.count
        }
        for (index, view) in itemViews.enumerated() {
            let frame = view.superview?.convert(view.frame, to: parentView) ?? .zero
            if point.x < frame.midX { return index }
        }
        return itemViews.count
    }

    func shelfMouseBridgeDidReorder(itemID: UUID, to destinationIndex: Int) {
        let parent = currentStackID?.uuidString ?? "root"
        shelfMouseBridgeDidLog(
            "internal reorder | source item id=\(itemID) parent=\(parent) insertion index=\(destinationIndex)"
        )
        if let currentStackID {
            if let item = visibleFileItemForInteraction(id: itemID),
               currentFileItems.contains(where: { $0.id == item.id }) {
                let fileDestination = min(destinationIndex, currentFileItems.count)
                stacks.moveFile(id: item.id, in: currentStackID, to: fileDestination)
            } else if stacks.childStacks(of: currentStackID).contains(where: { $0.id == itemID }) {
                let stackDestination = max(destinationIndex - currentFileItems.count, 0)
                stacks.moveStack(id: itemID, withinParent: currentStackID, to: stackDestination)
            } else {
                shelfMouseBridgeDidLog(
                    "internal reorder skipped child stack in stack detail | item id=\(itemID) parent=\(currentStackID)"
                )
            }
        } else if let source = visibleFileItemForInteraction(id: itemID), isPinnedRootItem(source) {
            shelfMouseBridgeDidLog("internal reorder skipped pinned root item id=\(source.id)")
        } else if let entries = rootEntriesByMoving(
            id: rootOrderedEntries.contains(where: { $0.id == itemID })
                ? itemID
                : (visibleFileItemForInteraction(id: itemID)?.id ?? itemID),
            to: rootReorderDestinationIndex(fromGeneralInsertionIndex: destinationIndex)
        ) {
            saveRootDisplayOrder(entries)
            refreshTouchBarItems(forceRebuild: true)
        } else {
            shelf.move(id: itemID, to: destinationIndex)
        }
        scheduleVisibleContentRefresh(mode: currentTouchBarMode, delay: 0.02)
        updateMouseBridgeState()
    }

    private func reorderID(for view: ShelfScrubberItemView) -> UUID? {
        view.representedItem?.id ?? view.representedStackID
    }

    func shelfMouseBridgeDidScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        inverted: Bool
    ) -> CGFloat? {
        let rawDelta = abs(deltaX) > 0.01 ? deltaX : deltaY
        let contentDelta = inverted ? -rawDelta : rawDelta
        shelfMouseBridgeDidLog(
            "Shelf horizontal scroll direction | raw deltaX=\(String(format: "%.2f", deltaX)) "
                + "raw deltaY=\(String(format: "%.2f", deltaY)) "
                + "applied deltaX=\(String(format: "%.2f", contentDelta))"
        )
        if let parent = NSFunctionRow._topLevelViews().last,
           let scrollView = currentVisibleShelfScrollView(in: parent),
           let documentView = scrollView.documentView {
            let offset = TouchBarHorizontalScrollBridge.scroll(
                scrollView,
                documentView: documentView,
                deltaX: deltaX,
                deltaY: deltaY,
                inverted: inverted,
                logPrefix: "Shelf main",
                logHandler: { [weak self] message in
                    self?.shelfMouseBridgeDidLog(message)
                }
            )
            onShelfScrollOffsetChange?(offset)
            return offset
        }

        guard let scrubber else { return nil }
        let itemPitch: CGFloat = 96
        let maximum = max(CGFloat(numberOfItems(for: scrubber) - 1) * itemPitch, 0)
        fallbackShelfScrollOffset = min(
            max(fallbackShelfScrollOffset + contentDelta, 0),
            maximum
        )
        let index = min(
            max(Int((fallbackShelfScrollOffset / itemPitch).rounded()), 0),
            max(numberOfItems(for: scrubber) - 1, 0)
        )
        if numberOfItems(for: scrubber) > 0 {
            scrubber.scrollItem(at: index, to: .center)
        }
        onShelfScrollOffsetChange?(fallbackShelfScrollOffset)
        shelfMouseBridgeDidLog(
            "Shelf scrubber fallback scroll offset | new scrollOffset=\(String(format: "%.2f", fallbackShelfScrollOffset))"
        )
        return fallbackShelfScrollOffset
    }

    func shelfMouseBridgeDiagnosticContext(
        atTouchBarPoint point: NSPoint,
        in parentView: NSView
    ) -> String {
        let pinnedCount = currentStackID == nil ? rootPinnedEntryCount : 0
        let rawHitTarget = debugViewName(parentView.hitTest(point))
        let resolvedHit = shelfMouseBridgeHit(atTouchBarPoint: point, in: parentView)
        let resolvedTarget = resolvedHit.map {
            "\($0.id) view=\(debugViewName($0.view)) reorder=\($0.allowsReorder)"
        } ?? "nil"
        let scrollView = currentVisibleShelfScrollView(in: parentView)
        let scrollFrame = scrollView.map {
            debugFrame($0.superview?.convert($0.frame, to: parentView) ?? $0.frame)
        } ?? "nil"
        let contentFrame = scrollView.map {
            debugFrame($0.contentView.superview?.convert($0.contentView.frame, to: parentView) ?? $0.contentView.frame)
        } ?? "nil"
        let documentFrame = scrollView?.documentView.map {
            debugFrame($0.superview?.convert($0.frame, to: parentView) ?? $0.frame)
        } ?? "nil"
        return "pinned count=\(pinnedCount) hitTest target=\(rawHitTarget) "
            + "resolved target=\(resolvedTarget) scrollView frame=\(scrollFrame) "
            + "content frame=\(contentFrame) document frame=\(documentFrame)"
    }

    func shelfMouseBridgeCanAttach(in parentView: NSView, mode: String) -> Bool {
        guard parentView.window != nil,
              parentView.bounds.width > 0,
              parentView.bounds.height > 0
        else { return false }
        guard expectsScrollableMouseBridge(mode: mode) else { return true }
        let visibleStripCount = numberOfShelfStripItems()
        let visibleScrubberCount = scrubber.map { numberOfItems(for: $0) } ?? 0
        if visibleStripCount == 0 && visibleScrubberCount == 0 {
            return true
        }
        if let visibleScrubber = currentVisibleScrubber(in: parentView),
           visibleScrubber.window != nil,
           visibleScrubber.frame.width > 0,
           visibleScrubber.frame.height > 0,
           visibleItemViews(in: parentView).contains(where: { view in
               let frame = view.superview?.convert(view.frame, to: parentView) ?? view.frame
               return frame.width > 0 && frame.height > 0
           }) {
            return true
        }
        guard let scrollView = currentVisibleShelfScrollView(in: parentView),
              let documentView = scrollView.documentView,
              scrollView.window != nil,
              scrollView.frame.width > 0,
              scrollView.frame.height > 0,
              scrollView.contentSize.width > 0,
              scrollView.contentSize.height > 0,
              documentView.frame.width > 0,
              documentView.frame.height > 0
        else { return false }
        if visibleStripCount > 0 || visibleScrubberCount > 0 {
            return visibleItemViews(in: parentView).contains { view in
                let frame = view.superview?.convert(view.frame, to: parentView) ?? view.frame
                return frame.width > 0 && frame.height > 0
            }
        }
        return true
    }

    func shelfMouseBridgeAttachDiagnosticContext(in parentView: NSView, mode: String) -> String {
        let visibleScrubber = currentVisibleScrubber(in: parentView)
        let scrollView = currentVisibleShelfScrollView(in: parentView)
        let documentView = scrollView?.documentView
        let samplePoint = (visibleScrubber.map {
            let frame = $0.superview?.convert($0.frame, to: parentView) ?? $0.frame
            return NSPoint(x: frame.midX, y: frame.midY)
        } ?? scrollView.map {
            let frame = $0.superview?.convert($0.frame, to: parentView) ?? $0.frame
            return NSPoint(x: frame.midX, y: frame.midY)
        }) ?? NSPoint(x: parentView.bounds.midX, y: parentView.bounds.midY)
        let itemViews = visibleItemViews(in: parentView)
        let itemFrameSummary = itemViews.prefix(10).map { view -> String in
            let frame = view.superview?.convert(view.frame, to: parentView) ?? view.frame
            return "\(debugViewName(view))[\(debugFrame(frame))]"
        }.joined(separator: "; ")
        let dividerPresence = rootDisplayEntries.contains { $0.isDivider }
            || itemViews.contains { $0.isPinDivider }
        let parentTrackingCount = parentView.trackingAreas.count
        let scrubberTrackingCount = visibleScrubber?.trackingAreas.count ?? 0
        let scrollTrackingCount = scrollView?.trackingAreas.count ?? 0
        let itemTrackingCount = itemViews.reduce(0) { partial, view in
            partial + view.trackingAreas.count
        }
        let trackingTotal = parentTrackingCount
            + scrubberTrackingCount
            + scrollTrackingCount
            + itemTrackingCount
        let rawHitTarget = debugViewName(parentView.hitTest(samplePoint))
        let resolvedHit = shelfMouseBridgeHit(atTouchBarPoint: samplePoint, in: parentView)
        let resolvedTarget = resolvedHit.map {
            "\($0.id) view=\(debugViewName($0.view)) reorder=\($0.allowsReorder)"
        } ?? "nil"
        return "mode=\(mode) scrollExpected=\(expectsScrollableMouseBridge(mode: mode)) "
            + "pinned=\(currentStackID == nil ? rootPinnedEntryCount : 0) "
            + "divider=\(dividerPresence) firstLayout=\(lastMainLayoutFirstPassDescription) "
            + "scrubberWindow=\(visibleScrubber?.window != nil) "
            + "scrubberFrame=\(visibleScrubber.map { debugFrame($0.superview?.convert($0.frame, to: parentView) ?? $0.frame) } ?? "nil") "
            + "scrollWindow=\(scrollView?.window != nil) "
            + "scrollFrame=\(scrollView.map { debugFrame($0.superview?.convert($0.frame, to: parentView) ?? $0.frame) } ?? "nil") "
            + "contentSize=\(scrollView.map { debugSize($0.contentSize) } ?? "nil") "
            + "documentFrame=\(documentView.map { debugFrame($0.superview?.convert($0.frame, to: parentView) ?? $0.frame) } ?? "nil") "
            + "trackingAreas=\(trackingTotal) hitTest=\(rawHitTarget) resolved=\(resolvedTarget) "
            + "visibleItemFrames(count=\(itemViews.count))=\(itemFrameSummary.isEmpty ? "none" : itemFrameSummary)"
    }

    private func animateStackMerge(
        sourceItemID: UUID,
        targetItemID: UUID,
        completion: @escaping () -> Void
    ) {
        let views = descendantBridgeViews(of: NSFunctionRow._topLevelViews().last ?? NSView())
            .compactMap { $0 as? ShelfScrubberItemView }
        let sourceView = views.first { $0.representedItem?.id == sourceItemID }
        let targetView = views.first { $0.representedItem?.id == targetItemID }
        sourceView?.wantsLayer = true
        targetView?.wantsLayer = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sourceView?.animator().alphaValue = 0.35
            targetView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.05, y: 1.05))
        } completionHandler: {
            completion()
        }
    }

    private func animateStackDrop(stackID: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self,
                  let view = self.descendantBridgeViews(
                    of: NSFunctionRow._topLevelViews().last ?? NSView()
                  )
                  .compactMap({ $0 as? ShelfScrubberItemView })
                  .first(where: { $0.representedStackID == stackID })
            else { return }
            view.wantsLayer = true
            view.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.05, y: 1.05))
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                view.animator().layer?.setAffineTransform(.identity)
            }
        }
    }

    func shelfMouseBridgeDidCompleteCopy(itemID: UUID) {
        if let currentStackID,
           currentFileItems.contains(where: { $0.id == itemID }) {
            let outcome = stacks.removeFile(
                id: itemID,
                from: currentStackID,
                autoDissolveSingle: false
            )
            if case .removedEmpty = outcome {
                shelfMouseBridgeDidLog(
                    "Stack auto removed after DragOut | stackID=\(currentStackID) reason=empty"
                )
            }
            if !currentFileItems.isEmpty {
                setStatus(.shelfActive)
            }
            return
        }
        guard shelf.items.contains(where: { $0.id == itemID }) else {
            shelfMouseBridgeDidLog("DragOut copy succeeded but item was already absent")
            return
        }
        shelf.remove(id: itemID)
        if !shelf.items.isEmpty {
            setStatus(.shelfActive)
        }
    }

    func shelfMouseBridgeDidLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let entry = "\(formatter.string(from: Date()))  \(message)"
        print("[ShelfDragOut] \(entry)")
        onDeveloperLogEntry?(entry)
    }

    private func descendantBridgeViews(of view: NSView) -> [NSView] {
        var result: [NSView] = []
        for subview in view.subviews {
            if subview is ShelfScrubberItemView || subview is NSButton {
                result.append(subview)
            }
            result.append(contentsOf: descendantBridgeViews(of: subview))
        }
        return result
    }

    private func descendantScrollView(of view: NSView) -> NSScrollView? {
        TouchBarHorizontalScrollBridge.descendantScrollView(of: view)
    }

    private func currentVisibleShelfScrollView(in parentView: NSView) -> NSScrollView? {
        if let mainLayout = touchBar.item(forIdentifier: ItemID.mainLayout)?.view,
           let scrollView = descendantScrollView(of: mainLayout),
           scrollView.isDescendant(of: parentView) || scrollView.window != nil {
            return scrollView
        }
        if let shelfScrollView,
           shelfScrollView.isDescendant(of: parentView) || shelfScrollView.window != nil {
            return shelfScrollView
        }
        if let visibleScrubber = currentVisibleScrubber(in: parentView),
           let scrollView = descendantScrollView(of: visibleScrubber),
           scrollView.isDescendant(of: parentView) || scrollView.window != nil {
            return scrollView
        }
        return descendantScrollView(of: parentView)
    }

    private func currentVisibleScrubber(in parentView: NSView) -> NSScrubber? {
        let identifier = currentStackID == nil ? ItemID.shelf : ItemID.stackShelf
        if let direct = touchBar.item(forIdentifier: identifier)?.view as? NSScrubber,
           direct.isDescendant(of: parentView) || direct.window != nil {
            return direct
        }
        if let mainLayout = touchBar.item(forIdentifier: ItemID.mainLayout)?.view,
           let nested = descendantScrubber(of: mainLayout),
           nested.isDescendant(of: parentView) || nested.window != nil {
            return nested
        }
        if let scrubber,
           scrubber.isDescendant(of: parentView) || scrubber.window != nil {
            return scrubber
        }
        return descendantScrubber(of: parentView)
    }

    private func expectsScrollableMouseBridge(mode: String) -> Bool {
        switch mode {
        case "shelf", "clipboard", "recent", "search":
            return true
        default:
            return mode.hasPrefix("stack:")
        }
    }

    private func visibleItemViews(in parentView: NSView) -> [ShelfScrubberItemView] {
        descendantBridgeViews(of: parentView)
            .compactMap { $0 as? ShelfScrubberItemView }
            .filter { view in
                !view.isHidden && view.alphaValue > 0.01
            }
            .sorted { left, right in
                let leftFrame = left.superview?.convert(left.frame, to: parentView) ?? left.frame
                let rightFrame = right.superview?.convert(right.frame, to: parentView) ?? right.frame
                return leftFrame.midX < rightFrame.midX
            }
    }

    private func debugViewName(_ view: NSView?) -> String {
        guard let view else { return "nil" }
        if let itemView = view as? ShelfScrubberItemView {
            if itemView.isPinDivider { return "ShelfScrubberItemView.pinDivider" }
            if itemView.representedItem != nil { return "ShelfScrubberItemView.file" }
            if itemView.representedStackID != nil { return "ShelfScrubberItemView.stack" }
            if itemView.representedClipboardItem != nil { return "ShelfScrubberItemView.clipboard" }
            return "ShelfScrubberItemView.empty"
        }
        if let button = view as? NSButton {
            return "NSButton(\(button.title))"
        }
        return String(describing: type(of: view))
    }

    private func debugFrame(_ rect: NSRect) -> String {
        "x=\(String(format: "%.1f", rect.origin.x)),y=\(String(format: "%.1f", rect.origin.y)),w=\(String(format: "%.1f", rect.width)),h=\(String(format: "%.1f", rect.height))"
    }

    private func debugSize(_ size: NSSize) -> String {
        "w=\(String(format: "%.1f", size.width)),h=\(String(format: "%.1f", size.height))"
    }

    private func descendantScrubber(of view: NSView) -> NSScrubber? {
        if let scrubber = view as? NSScrubber { return scrubber }
        for subview in view.subviews {
            if let result = descendantScrubber(of: subview) { return result }
        }
        return nil
    }
}
