import AppKit

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
final class PrivateTouchBarController: NSObject,
    NSTouchBarDelegate,
    NSScrubberDataSource,
    NSScrubberDelegate,
    OverlayDropDelegate,
    ShelfMouseBridgeDelegate,
    ShelfTouchDragDelegate {

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
    }

    private static let scrubberItemIdentifier = NSUserInterfaceItemIdentifier(
        "com.prototype.TouchBarPrivateResearch.shelfItem"
    )

    let touchBar = NSTouchBar()
    let shelf: FileShelfModel
    let stacks: ShelfStackModel
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
    private var selectedOperationItemID: UUID?
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
    private(set) var isPresented = false
    private(set) var currentStatus = AutoDropStatus.idle.rawValue

    init(shelf: FileShelfModel, stacks: ShelfStackModel) {
        self.shelf = shelf
        self.stacks = stacks
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
        isCenterExpandOpening = false
        currentStackID = nil
        stackNavigationPath.removeAll()
        renderedStackItemIDs.removeAll()
        isShowingDropTarget = mainItemCount == 0
        selectedOperationItemID = nil
        refreshTouchBarItems()
        ensureSystemModalPresented()
        updateMouseBridgeState()
        setStatus(mainItemCount == 0 ? .dropReady : .shelfActive)
    }

    func presentSystemModalWithCenterExpand() {
        pendingDragDismiss?.cancel()
        pendingDragDismiss = nil
        isShowingDropTarget = false
        activeDropZone = .none
        selectedOperationItemID = nil
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

    func clearShelf() {
        shelf.clear()
        stacks.clear()
        shelfMouseBridgeDidLog("CLEAR removed root Shelf items and all Stack/Nested Stack records")
        dismissSystemModal()
    }

    func setMouseBridgeHeightInPixels(_ pixels: Int) {
        shelfMouseBridgeController.setHeightInPixels(pixels)
        actionMenuMouseBridgeController.setHeightInPixels(pixels)
    }

    func finderFileDragDetected() {
        pendingDragDismiss?.cancel()
        pendingDragDismiss = nil
        currentDragDidDrop = false
        setStatus(.dragDetected)
    }

    func finderFileDragEnded() {
        scheduleDismissAfterCancelledDrag()
    }

    func overlayDragEntered(snapshot: ShelfDropZoneSnapshot) {
        showDropTarget(snapshot: snapshot)
    }

    func overlayDragUpdated(snapshot: ShelfDropZoneSnapshot) {
        showDropTarget(snapshot: snapshot)
    }

    func overlayDragExited() {
        activeDropZone = .none
        scheduleDismissAfterCancelledDrag()
    }

    func overlayDragEnded() {
        activeDropZone = .none
        scheduleDismissAfterCancelledDrag()
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
            scheduleDismissAfterCancelledDrag()
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
        scheduleDismissAfterCancelledDrag()
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        switch identifier {
        case ItemID.dropHere:
            item.view = TouchBarDropButton(activeZone: activeDropZone)
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
        default:
            return nil
        }
        return item
    }

    func numberOfItems(for scrubber: NSScrubber) -> Int {
        if let currentStackID {
            return stacks.directItemCount(in: currentStackID)
        }
        return shelf.items.count + stacks.rootStacks.count
    }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        guard let view = scrubber.makeItem(
                withIdentifier: Self.scrubberItemIdentifier,
                owner: self
            ) as? ShelfScrubberItemView
        else { return NSScrubberItemView() }
        view.touchDragDelegate = self

        if currentStackID != nil {
            guard let currentStackID,
                  let stack = stacks.stack(id: currentStackID)
            else { return NSScrubberItemView() }
            if stack.entries.indices.contains(index), let renderedItem = stack.entries[index].fileItem {
                view.configure(with: renderedItem)
                if renderedStackItemIDs.insert(renderedItem.id).inserted {
                    shelfMouseBridgeDidLog("each rendered item filename=\(renderedItem.filename)")
                }
            } else {
                let childIndex = index - stack.entries.count
                let children = stacks.childStacks(of: currentStackID)
                guard children.indices.contains(childIndex) else { return NSScrubberItemView() }
                let child = children[childIndex]
                view.configure(with: child, itemCount: stacks.directItemCount(in: child.id))
            }
        } else if shelf.items.indices.contains(index) {
            view.configure(with: shelf.items[index])
        } else {
            let stackIndex = index - shelf.items.count
            let rootStacks = stacks.rootStacks
            guard rootStacks.indices.contains(stackIndex) else { return NSScrubberItemView() }
            let stack = rootStacks[stackIndex]
            view.configure(with: stack, itemCount: stacks.directItemCount(in: stack.id))
        }
        return view
    }

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt selectedIndex: Int) {
        guard selectedOperationItemID == nil else { return }
        if currentStackID != nil {
            if currentFileItems.indices.contains(selectedIndex) {
                selectedOperationItemID = currentFileItems[selectedIndex].id
            } else {
                let childIndex = selectedIndex - currentFileItems.count
                guard currentChildStacks.indices.contains(childIndex) else { return }
                enterStack(id: currentChildStacks[childIndex].id)
                scrubber.selectedIndex = -1
                return
            }
        } else if shelf.items.indices.contains(selectedIndex) {
            selectedOperationItemID = shelf.items[selectedIndex].id
        } else {
            let stackIndex = selectedIndex - shelf.items.count
            let rootStacks = stacks.rootStacks
            guard rootStacks.indices.contains(stackIndex) else { return }
            enterStack(id: rootStacks[stackIndex].id)
            scrubber.selectedIndex = -1
            return
        }
        scrubber.selectedIndex = -1
        if let selectedOperationItemID {
            shelfMouseBridgeDidLog("action menu opened item id=\(selectedOperationItemID)")
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
        activeDropZone = snapshot.zone
        shelfMouseBridgeDidLog(
            "activeDropZone=\(snapshot.zone.rawValue) "
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

    private func scheduleDismissAfterCancelledDrag() {
        guard !currentDragDidDrop else { return }
        pendingDragDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.currentDragDidDrop else { return }
            self.dismissSystemModal()
        }
        pendingDragDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
           !currentFileItems.contains(where: { $0.id == selectedOperationItemID }) {
            self.selectedOperationItemID = nil
        }
        refreshTouchBarItems()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode)
        onShelfChange?(items)
        if mainItemCount == 0 && currentStackID == nil && !isShowingDropTarget {
            dismissSystemModal()
        } else {
            updateMouseBridgeState()
        }
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
        scrubber?.reloadItems(at: indexes)
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
                scrubber?.reloadItems(at: changed)
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

    private func refreshTouchBarItems() {
        let identifiers: [NSTouchBarItem.Identifier]
        let principal: NSTouchBarItem.Identifier
        if isCenterExpandOpening {
            identifiers = [ItemID.centerExpand]
            principal = ItemID.centerExpand
        } else if isShowingDropTarget {
            identifiers = [ItemID.dropHere]
            principal = ItemID.dropHere
        } else if selectedOperationItem != nil {
            identifiers = [ItemID.operationActions]
            principal = ItemID.operationActions
        } else if currentStackID != nil {
            identifiers = currentContainerItemCount == 0
                ? [ItemID.stackBack, ItemID.stackTitle, ItemID.close]
                : [ItemID.stackBack, ItemID.stackTitle, ItemID.stackShelf, ItemID.close]
            principal = currentContainerItemCount == 0
                ? ItemID.stackTitle
                : ItemID.stackShelf
        } else if mainItemCount == 0 {
            identifiers = [ItemID.dropHere]
            principal = ItemID.dropHere
        } else {
            identifiers = [ItemID.shelf, ItemID.clear, ItemID.close]
            principal = ItemID.shelf
        }
        if touchBar.defaultItemIdentifiers != identifiers {
            touchBar.defaultItemIdentifiers = identifiers
        }
        if touchBar.principalItemIdentifier != principal {
            touchBar.principalItemIdentifier = principal
        }
    }

    private func makeScrubber() -> NSScrubber {
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
        layout.itemSize = NSSize(width: 88, height: 30)
        layout.itemSpacing = 8
        scrubber.scrubberLayout = layout
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrubber.widthAnchor.constraint(equalToConstant: currentStackID == nil ? 830 : 650),
            scrubber.heightAnchor.constraint(equalToConstant: 30)
        ])
        self.scrubber = scrubber
        return scrubber
    }

    private var selectedOperationItem: FileShelfItem? {
        guard let selectedOperationItemID else { return nil }
        return currentFileItems.first { $0.id == selectedOperationItemID }
    }

    private var currentFileItems: [FileShelfItem] {
        guard let currentStackID else { return shelf.items }
        return stacks.fileItems(in: currentStackID)
    }

    private var currentChildStacks: [ShelfStack] {
        guard let currentStackID else { return stacks.rootStacks }
        return stacks.childStacks(of: currentStackID)
    }

    private var currentContainerItemCount: Int {
        currentFileItems.count + currentChildStacks.count
    }

    private var mainItemCount: Int {
        shelf.items.count + stacks.rootStacks.count
    }

    private var currentTouchBarMode: String {
        if isShowingDropTarget { return "dropHere" }
        if selectedOperationItemID != nil { return "actionMenu" }
        if let currentStackID { return "stack:\(currentStackID.uuidString)" }
        return mainItemCount == 0 ? "empty" : "shelf"
    }

    private var autoDissolveSingleItemStack: Bool {
        let key = "ShelfBar.autoDissolveSingleItemStack"
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func scheduleVisibleContentRefresh(mode: String, delay: TimeInterval = 0.07) {
        contentRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let scrubberIdentifier = self.currentStackID == nil ? ItemID.shelf : ItemID.stackShelf
            if let visibleScrubber = self.touchBar.item(forIdentifier: scrubberIdentifier)?.view
                as? NSScrubber {
                self.scrubber = visibleScrubber
                visibleScrubber.reloadData()
                visibleScrubber.layoutSubtreeIfNeeded()
                if let currentStackID = self.currentStackID {
                    let latestItems = self.stacks.fileItems(in: currentStackID)
                    let visibleCount = self.stacks.directItemCount(in: currentStackID)
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
                    self.shelfMouseBridgeDidLog("stack item count=\(latestItems.count)")
                    self.shelfMouseBridgeDidLog("rendered stack item count=\(renderedCount)")
                    if !latestItems.isEmpty, renderedCount == 0 {
                        self.shelfMouseBridgeDidLog(
                            "ERROR stack item count > 0 but rendered stack item count = 0"
                        )
                    }
                }
            }
            NSFunctionRow._topLevelViews().last?.layoutSubtreeIfNeeded()
            self.shelfMouseBridgeController.requestHitRegionRebuild(mode: mode)
            self.shelfMouseBridgeDidLog(
                "Touch Bar content refresh | current mode=\(mode) delay=\(Int(delay * 1000))ms"
            )
        }
        contentRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func removeStackItem(id: UUID, from stackID: UUID) {
        let removedItem = stacks.fileItems(in: stackID).first { $0.id == id }
        let outcome = stacks.removeFile(
            id: id,
            from: stackID,
            autoDissolveSingle: autoDissolveSingleItemStack
        )
        if let removedItem {
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
        let filename = NSTextField(labelWithString: selectedOperationItem?.filename ?? "")
        filename.alignment = .center
        filename.font = .systemFont(ofSize: 11, weight: .semibold)
        filename.lineBreakMode = .byTruncatingMiddle
        filename.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            filename.widthAnchor.constraint(equalToConstant: 300),
            filename.heightAnchor.constraint(equalToConstant: 30)
        ])
        return filename
    }

    private func makeOperationIcon() -> NSImageView {
        let imageView = NSImageView()
        imageView.image = selectedOperationItem?.displayImage
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 42),
            imageView.heightAnchor.constraint(equalToConstant: 28)
        ])
        operationIconImageView = imageView
        return imageView
    }

    private func makeOperationActions() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let icon = makeOperationIcon()
        let filename = makeOperationPrompt()
        let open = makeButton(title: "OPEN", action: #selector(openPressed), width: 136)
        let remove = makeSymbolButton(
            title: "REMOVE",
            symbol: "trash",
            action: #selector(removePressed),
            width: 136
        )
        let back = makeSymbolButton(
            title: "BACK",
            symbol: "chevron.left",
            action: #selector(backPressed),
            width: 136
        )
        let stack = NSStackView(views: [icon, filename, open, remove, back])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 960),
            container.heightAnchor.constraint(equalToConstant: 30),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func makeButton(title: String, action: Selector, width: CGFloat) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: 30)
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
        let label = NSTextField(
            labelWithString: stack?.name ?? "Stack"
        )
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: currentContainerItemCount == 0 ? 620 : 140),
            label.heightAnchor.constraint(equalToConstant: 30)
        ])
        return label
    }

    private func setStatus(_ status: AutoDropStatus) {
        guard currentStatus != status.rawValue else { return }
        currentStatus = status.rawValue
        print("[ShelfBar] status=\(status.rawValue)")
        onStatusChange?(status.rawValue)
    }

    private func updateMouseBridgeState() {
        let shouldPresent = isPresented
            && !isShowingDropTarget
            && selectedOperationItemID == nil
            && (mainItemCount > 0 || currentStackID != nil)
        if shouldPresent {
            actionMenuMouseBridgeController.dismiss()
            shelfMouseBridgeController.present(mode: currentTouchBarMode)
        } else if isPresented,
                  !isShowingDropTarget,
                  selectedOperationItemID != nil,
                  (mainItemCount > 0 || currentStackID != nil) {
            shelfMouseBridgeController.dismiss()
            actionMenuMouseBridgeController.present()
        } else {
            shelfMouseBridgeController.dismiss()
            actionMenuMouseBridgeController.dismiss()
        }
    }

    @objc private func clearPressed() {
        clearShelf()
    }

    @objc private func closePressed() {
        closeShelfFromUser()
    }

    @objc private func openPressed() {
        guard let item = selectedOperationItem else { return }
        NSWorkspace.shared.open(item.url)
        selectedOperationItemID = nil
        refreshTouchBarItems()
        updateMouseBridgeState()
        setStatus(.shelfActive)
    }

    @objc private func removePressed() {
        guard let id = selectedOperationItemID else { return }
        selectedOperationItemID = nil
        if let currentStackID {
            removeStackItem(id: id, from: currentStackID)
        } else {
            removeShelfItem(id: id)
        }
        refreshTouchBarItems()
        updateMouseBridgeState()
        if mainItemCount > 0 || currentStackID != nil {
            setStatus(.shelfActive)
        }
    }

    @objc private func backPressed() {
        selectedOperationItemID = nil
        refreshTouchBarItems()
        updateMouseBridgeState()
        setStatus(.shelfActive)
    }

    @objc private func stackBackPressed() {
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
        refreshTouchBarItems()
        scheduleVisibleContentRefresh(mode: currentTouchBarMode)
        updateMouseBridgeState()
    }

    func shelfMouseBridgeHit(
        atTouchBarPoint point: NSPoint,
        in parentView: NSView
    ) -> ShelfBridgeHit? {
        var candidate = parentView.hitTest(point)
        while let view = candidate, view !== parentView {
            if let itemView = view as? ShelfScrubberItemView,
               let item = itemView.representedItem {
                return ShelfBridgeHit(id: "shelf:\(item.id)", item: item, stackID: nil, view: itemView)
            }
            if let itemView = view as? ShelfScrubberItemView,
               let stackID = itemView.representedStackID {
                return ShelfBridgeHit(id: "stack:\(stackID)", item: nil, stackID: stackID, view: itemView)
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
            if let itemView = view as? ShelfScrubberItemView,
               let item = itemView.representedItem {
                return ShelfBridgeHit(id: "shelf:\(item.id)", item: item, stackID: nil, view: itemView)
            }
            if let itemView = view as? ShelfScrubberItemView,
               let stackID = itemView.representedStackID {
                return ShelfBridgeHit(id: "stack:\(stackID)", item: nil, stackID: stackID, view: itemView)
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

    func shelfMouseBridgeRegisteredHitRegionNames(in parentView: NSView) -> [String] {
        var names: [String] = []
        for identifier in touchBar.defaultItemIdentifiers {
            guard let rootView = touchBar.item(forIdentifier: identifier)?.view else { continue }
            let views = [rootView] + descendantBridgeViews(of: rootView)
            for view in views {
                if let itemView = view as? ShelfScrubberItemView,
                   let item = itemView.representedItem,
                   let index = currentFileItems.firstIndex(where: { $0.id == item.id }) {
                    names.append("Shelf item \(index + 1)")
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
              currentFileItems.contains(where: { $0.id == itemID })
        else { return }
        selectedOperationItemID = itemID
        shelfMouseBridgeDidLog("action menu opened item id=\(itemID)")
        refreshTouchBarItems()
        updateMouseBridgeState()
        setStatus(.shelfActive)
    }

    func shelfTouchDragBegan(
        sourceView: ShelfScrubberItemView,
        itemID: UUID,
        at point: NSPoint,
        in parentView: NSView
    ) {
        shelfMouseBridgeController.beginDirectTouchDrag(
            sourceView: sourceView,
            itemID: itemID,
            at: point,
            in: parentView
        )
    }

    func shelfTouchDragChanged(itemID: UUID, at point: NSPoint, in parentView: NSView) {
        shelfMouseBridgeController.updateDirectTouchDrag(
            itemID: itemID,
            at: point,
            in: parentView
        )
    }

    func shelfTouchDragEnded(
        itemID: UUID,
        at point: NSPoint,
        in parentView: NSView,
        cancelled: Bool
    ) {
        shelfMouseBridgeController.endDirectTouchDrag(
            itemID: itemID,
            at: point,
            in: parentView,
            cancelled: cancelled
        )
    }

    func shelfMouseBridgeDidClickStack(stackID: UUID) {
        guard let stack = stacks.stack(id: stackID), stack.parentStackID == currentStackID else { return }
        enterStack(id: stackID)
    }

    func shelfMouseBridgeCanDrop(sourceItemID: UUID, onto hit: ShelfBridgeHit) -> Bool {
        let sourceItems = currentFileItems
        guard sourceItems.contains(where: { $0.id == sourceItemID }) else { return false }
        if let targetItemID = hit.item?.id {
            return targetItemID != sourceItemID
                && sourceItems.contains(where: { $0.id == targetItemID })
        }
        if let stackID = hit.stackID {
            return stacks.stack(id: stackID)?.parentStackID == currentStackID
        }
        return false
    }

    func shelfMouseBridgeDidMerge(sourceItemID: UUID, targetItemID: UUID) {
        let items = currentFileItems
        guard sourceItemID != targetItemID,
              let source = items.first(where: { $0.id == sourceItemID }),
              let target = items.first(where: { $0.id == targetItemID })
        else { return }

        shelfMouseBridgeDidLog(
            "stack create source item | id=\(source.id) url=\(source.url.absoluteString)"
        )
        shelfMouseBridgeDidLog(
            "stack target item | id=\(target.id) url=\(target.url.absoluteString)"
        )
        animateStackMerge(sourceItemID: sourceItemID, targetItemID: targetItemID) { [weak self] in
            guard let self,
                  self.currentFileItems.contains(where: { $0.id == sourceItemID }),
                  self.currentFileItems.contains(where: { $0.id == targetItemID })
            else { return }
            let stackID = self.stacks.create(
                name: "",
                items: [target, source],
                parentStackID: self.currentStackID
            )
            if let parentID = self.currentStackID {
                self.stacks.removeFiles(ids: [sourceItemID, targetItemID], from: parentID)
            } else {
                self.shelf.remove(ids: [sourceItemID, targetItemID])
            }
            self.shelfMouseBridgeDidLog(
                "stack add item | stackID=\(stackID) parent=\(self.currentStackID?.uuidString ?? "root") count=2 source=\(sourceItemID) target=\(targetItemID)"
            )
            self.animateStackDrop(stackID: stackID)
        }
    }

    func shelfMouseBridgeDidDrop(itemID: UUID, ontoStack stackID: UUID) {
        guard let item = currentFileItems.first(where: { $0.id == itemID }),
              stacks.stack(id: stackID)?.parentStackID == currentStackID
        else { return }
        shelfMouseBridgeDidLog(
            "stack add item | stackID=\(stackID) sourceItemID=\(item.id) url=\(item.url.absoluteString)"
        )
        stacks.add(item: item, to: stackID)
        if let parentID = currentStackID {
            stacks.removeFiles(ids: [itemID], from: parentID)
        } else {
            shelf.remove(id: itemID)
        }
        animateStackDrop(stackID: stackID)
    }

    func shelfMouseBridgeInsertionIndex(
        atTouchBarPoint point: NSPoint,
        in parentView: NSView
    ) -> Int? {
        let itemViews = descendantBridgeViews(of: parentView)
            .compactMap { $0 as? ShelfScrubberItemView }
            .filter { view in
                guard let id = view.representedItem?.id else { return false }
                return currentFileItems.contains(where: { $0.id == id })
            }
            .sorted { left, right in
                let leftFrame = left.superview?.convert(left.frame, to: parentView) ?? .zero
                let rightFrame = right.superview?.convert(right.frame, to: parentView) ?? .zero
                return leftFrame.midX < rightFrame.midX
            }
        guard !itemViews.isEmpty else { return 0 }
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
            stacks.moveFile(id: itemID, in: currentStackID, to: destinationIndex)
        } else {
            shelf.move(id: itemID, to: destinationIndex)
        }
    }

    func shelfMouseBridgeDidScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        inverted: Bool
    ) -> CGFloat? {
        guard let scrubber else { return nil }
        let rawDelta = abs(deltaX) > 0.01 ? deltaX : deltaY
        let contentDelta = inverted ? -rawDelta : rawDelta
        shelfMouseBridgeDidLog(
            "Shelf horizontal scroll direction | raw deltaX=\(String(format: "%.2f", deltaX)) "
                + "raw deltaY=\(String(format: "%.2f", deltaY)) "
                + "applied deltaX=\(String(format: "%.2f", contentDelta))"
        )
        guard let scrollView = descendantScrollView(of: scrubber),
              let documentView = scrollView.documentView
        else {
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
                "Shelf horizontal scroll offset | new scrollOffset=\(String(format: "%.2f", fallbackShelfScrollOffset))"
            )
            return fallbackShelfScrollOffset
        }
        let maximum = max(documentView.bounds.width - scrollView.contentView.bounds.width, 0)
        var origin = scrollView.contentView.bounds.origin
        origin.x = min(max(origin.x + contentDelta, 0), maximum)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        onShelfScrollOffsetChange?(origin.x)
        shelfMouseBridgeDidLog(
            "Shelf horizontal scroll offset | new scrollOffset=\(String(format: "%.2f", origin.x))"
        )
        return origin.x
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
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let result = descendantScrollView(of: subview) { return result }
        }
        return nil
    }
}
