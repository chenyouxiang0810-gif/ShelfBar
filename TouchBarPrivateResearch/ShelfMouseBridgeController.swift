import AppKit
import UniformTypeIdentifiers

@MainActor
protocol ShelfMouseBridgeDelegate: AnyObject {
    func shelfMouseBridgeHit(atTouchBarPoint point: NSPoint, in parentView: NSView) -> ShelfBridgeHit?
    func shelfMouseBridgeRegisteredHitRegionNames(in parentView: NSView) -> [String]
    func shelfMouseBridgeDidClick(itemID: UUID)
    func shelfMouseBridgeDidClickStack(stackID: UUID)
    func shelfMouseBridgeCanDrop(sourceItemID: UUID, onto hit: ShelfBridgeHit) -> Bool
    func shelfMouseBridgeDidMerge(sourceItemID: UUID, targetItemID: UUID)
    func shelfMouseBridgeDidDrop(itemID: UUID, ontoStack stackID: UUID)
    func shelfMouseBridgeInsertionIndex(atTouchBarPoint point: NSPoint, in parentView: NSView) -> Int?
    func shelfMouseBridgeDidReorder(itemID: UUID, to destinationIndex: Int)
    func shelfMouseBridgeDidScroll(deltaX: CGFloat, deltaY: CGFloat, inverted: Bool) -> CGFloat?
    func shelfMouseBridgeDidCompleteCopy(itemID: UUID)
    func shelfMouseBridgeDidLog(_ message: String)
}

@MainActor
struct ShelfBridgeHit {
    let id: String
    let item: FileShelfItem?
    let stackID: UUID?
    let view: NSView
}

@MainActor
private final class ShelfFilePromiseWriter: NSObject, NSFilePromiseProviderDelegate {
    nonisolated let id: UUID
    nonisolated let sourceURL: URL
    private let logHandler: (String) -> Void
    private let finishedHandler: (Bool) -> Void
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "TouchBarPrivateResearch.ShelfFilePromiseWriter"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(
        id: UUID,
        sourceURL: URL,
        logHandler: @escaping (String) -> Void,
        finishedHandler: @escaping (Bool) -> Void
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.logHandler = logHandler
        self.finishedHandler = finishedHandler
        super.init()
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        let filename = sourceURL.lastPathComponent
        logHandler("Shelf promise filename | type=\(fileType) filename=\(filename)")
        return filename
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo destinationURL: URL,
        completionHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        let filename = sourceURL.lastPathComponent
        emit(
            "Shelf writePromiseTo called | destinationURL=\(destinationURL.absoluteString) "
                + "filename=\(filename) source=\(sourceURL.path)"
        )

        do {
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileNoSuchFileError,
                    userInfo: [
                        NSFilePathErrorKey: sourceURL.path,
                        NSLocalizedDescriptionKey: "Shelf source file no longer exists."
                    ]
                )
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            emit(
                "Shelf FilePromise success | destinationURL=\(destinationURL.absoluteString) "
                    + "filename=\(filename) success=true"
            )
            completionHandler(nil)
            finish(success: true)
        } catch {
            let nsError = error as NSError
            emit(
                "Shelf FilePromise failure | destinationURL=\(destinationURL.absoluteString) "
                    + "filename=\(filename) success=false "
                    + "error=\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
            )
            completionHandler(error)
            finish(success: false)
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        queue
    }

    nonisolated private func emit(_ message: String) {
        Task { @MainActor [weak self] in
            self?.logHandler(message)
        }
    }

    nonisolated private func finish(success: Bool) {
        Task { @MainActor [weak self] in
            self?.finishedHandler(success)
        }
    }
}

@MainActor
final class ShelfMouseBridgeController: NSObject {
    private final class FloatingDragImageView: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private final class BridgePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class BridgeView: NSView, NSDraggingSource {
        weak var bridge: ShelfMouseBridgeController?
        private var trackingAreaReference: NSTrackingArea?
        private var mouseDownPoint: NSPoint?
        private var lockedSourceHit: ShelfBridgeHit?
        private var gestureExceededThreshold = false
        private var externalDragStarted = false
        private var internalDragStarted = false
        private var internalInsertionIndex: Int?
        private var activePromiseID: UUID?
        private var internalDropTarget: ShelfBridgeHit?
        private var internalDropTargetSince: TimeInterval?
        private var targetReadyWorkItem: DispatchWorkItem?

        var hasActiveGesture: Bool {
            mouseDownPoint != nil || externalDragStarted || internalDragStarted
        }

        var activeItemID: UUID? {
            lockedSourceHit?.item?.id
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaReference {
                removeTrackingArea(trackingAreaReference)
            }
            let tracking = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(tracking)
            trackingAreaReference = tracking
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseEntered(with event: NSEvent) {
            bridge?.pointerEntered()
            bridge?.pointerMoved(toPanelPoint: bridge?.currentPanelPoint ?? event.locationInWindow)
        }

        override func mouseMoved(with event: NSEvent) {
            bridge?.pointerMoved(toPanelPoint: event.locationInWindow)
        }

        override func mouseExited(with event: NSEvent) {
            guard mouseDownPoint == nil else { return }
            bridge?.pointerExited()
        }

        override func scrollWheel(with event: NSEvent) {
            guard !hasActiveGesture else {
                bridge?.log("Shelf scroll ignored during active drag")
                return
            }
            let horizontal = event.scrollingDeltaX
            let shiftedVertical = event.modifierFlags.contains(.shift)
                ? event.scrollingDeltaY
                : 0
            guard abs(horizontal) > 0.01 || abs(shiftedVertical) > 0.01 else { return }
            bridge?.handleScroll(
                deltaX: horizontal,
                deltaY: shiftedVertical,
                inverted: event.isDirectionInvertedFromDevice
            )
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = event.locationInWindow
            lockedSourceHit = bridge?.hit(atPanelPoint: event.locationInWindow)
            gestureExceededThreshold = false
            externalDragStarted = false
            internalDragStarted = false
            internalInsertionIndex = nil
            activePromiseID = nil
            clearInternalDropTarget()
            (lockedSourceHit?.view as? ShelfScrubberItemView)?.setBridgePressed(true)
            bridge?.logBridgeState(reason: "mouseDown")
        }

        override func mouseDragged(with event: NSEvent) {
            guard !externalDragStarted,
                  let start = mouseDownPoint,
                  let item = lockedSourceHit?.item
            else { return }

            if let bridge {
                let stableDragRect = bridge.virtualTouchBarRect.insetBy(
                    dx: -ShelfMouseBridgeController.exitThreshold,
                    dy: -ShelfMouseBridgeController.exitThreshold
                )
                if stableDragRect.contains(event.locationInWindow) {
                    bridge.pointerMoved(toPanelPoint: event.locationInWindow)
                }
            }
            let deltaX = event.locationInWindow.x - start.x
            let deltaY = event.locationInWindow.y - start.y
            let distance = hypot(deltaX, deltaY)
            let threshold = bridge?.dragThresholdInPoints ?? 5
            guard distance >= threshold else { return }
            gestureExceededThreshold = true

            let leftVirtualTouchBar = event.locationInWindow.y
                > (bridge?.virtualTouchBarRect.maxY ?? 40)
            let isUpwardIntent = deltaY >= threshold
                && (leftVirtualTouchBar || deltaY >= abs(deltaX))
            if !isUpwardIntent {
                if !internalDragStarted {
                    internalDragStarted = true
                    bridge?.beginInternalDrag(
                        source: lockedSourceHit,
                        atPanelPoint: event.locationInWindow
                    )
                }
                internalInsertionIndex = bridge?.updateInternalDrag(
                    sourceItemID: item.id,
                    atPanelPoint: event.locationInWindow
                )
                if let target = bridge?.internalDropTarget(
                    for: item.id,
                    atPanelPoint: event.locationInWindow
                ) {
                    updateInternalDropTarget(target)
                } else {
                    clearInternalDropTarget()
                }
                return
            }

            if internalDragStarted {
                bridge?.endInternalDrag(cancelled: true)
                internalDragStarted = false
                internalInsertionIndex = nil
            }
            clearInternalDropTarget()

            externalDragStarted = true
            (lockedSourceHit?.view as? ShelfScrubberItemView)?.setBridgePressed(false)
            guard let bridge else { return }
            let sourceView = lockedSourceHit?.view as? ShelfScrubberItemView
            sourceView?.setDragOutActive(true)
            let writer = bridge.makePromiseWriter(for: item, sourceView: sourceView)
            activePromiseID = writer.id
            let provider = NSFilePromiseProvider(
                fileType: ShelfMouseBridgeController.promiseType(for: item.url),
                delegate: writer
            )
            provider.userInfo = item.url
            let draggingItem = NSDraggingItem(pasteboardWriter: provider)
            let preview = ShelfMouseBridgeController.dragPreview(for: item.displayImage)
            draggingItem.setDraggingFrame(
                NSRect(
                    x: event.locationInWindow.x - preview.size.width / 2,
                    y: event.locationInWindow.y - preview.size.height / 2,
                    width: preview.size.width,
                    height: preview.size.height
                ),
                contents: preview.image
            )

            bridge.clearHover()
            bridge.log(
                "Shelf Drag Begin requested | sourceItemID=\(item.id) "
                    + "fileURL=\(item.url.absoluteString) filename=\(item.filename) "
                    + "threshold=\(Int(ShelfMouseBridgeController.dragThresholdPixels))px"
            )
            let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
            let types = (session.draggingPasteboard.types ?? []).map(\.rawValue)
            bridge.log(
                "Shelf Drag pasteboard | sourceItemID=\(item.id) fileURL=\(item.url.absoluteString) "
                    + "types=\(types)"
            )
        }

        override func mouseUp(with event: NSEvent) {
            if externalDragStarted {
                (lockedSourceHit?.view as? ShelfScrubberItemView)?.setBridgePressed(false)
                mouseDownPoint = nil
                lockedSourceHit = nil
                gestureExceededThreshold = false
                clearInternalDropTarget()
                return
            }

            let releasedHit = bridge?.hit(atPanelPoint: event.locationInWindow)
            let releasedID = releasedHit?.item?.id.uuidString
                ?? releasedHit?.stackID?.uuidString
                ?? "nil"
            bridge?.log(
                String(
                    format: "click point=(%.2f, %.2f) hit item id=%@",
                    event.locationInWindow.x,
                    event.locationInWindow.y,
                    releasedID
                )
            )
            let releasedTarget = lockedSourceHit?.item.flatMap {
                bridge?.internalDropTarget(for: $0.id, atPanelPoint: event.locationInWindow)
            }
            let requiredDelay = releasedTarget?.stackID == nil
                ? ShelfMouseBridgeController.createStackHoverDelay
                : ShelfMouseBridgeController.addToStackHoverDelay
            let targetWasArmed = releasedTarget?.id == internalDropTarget?.id
                && ProcessInfo.processInfo.systemUptime - (internalDropTargetSince ?? .infinity)
                    >= requiredDelay
            defer {
                (lockedSourceHit?.view as? ShelfScrubberItemView)?.setBridgePressed(false)
                mouseDownPoint = nil
                lockedSourceHit = nil
                gestureExceededThreshold = false
                externalDragStarted = false
                internalDragStarted = false
                internalInsertionIndex = nil
                activePromiseID = nil
                clearInternalDropTarget()
            }
            guard let hit = lockedSourceHit else { return }
            if gestureExceededThreshold,
               targetWasArmed,
               let source = hit.item,
               let target = releasedTarget {
                if let stackID = target.stackID {
                    bridge?.didDrop(itemID: source.id, ontoStack: stackID)
                } else if let targetItemID = target.item?.id {
                    bridge?.didMerge(sourceItemID: source.id, targetItemID: targetItemID)
                }
                bridge?.endInternalDrag(cancelled: false)
            } else if internalDragStarted,
                      gestureExceededThreshold,
                      let source = hit.item,
                      let internalInsertionIndex {
                bridge?.didReorder(itemID: source.id, to: internalInsertionIndex)
                bridge?.endInternalDrag(cancelled: false)
            } else if !gestureExceededThreshold,
                      let releasedHit,
                      releasedHit.id == hit.id {
                bridge?.didClick(hit: releasedHit)
            } else {
                bridge?.clearHover()
                bridge?.log("MouseBridge blank mouseUp ignored")
            }
        }

        private func updateInternalDropTarget(_ target: ShelfBridgeHit) {
            guard target.id != internalDropTarget?.id else { return }
            clearInternalDropTarget()
            internalDropTarget = target
            internalDropTargetSince = ProcessInfo.processInfo.systemUptime
            (target.view as? ShelfScrubberItemView)?.setStackDropTargetHighlighted(true)
            let delay = target.stackID == nil
                ? ShelfMouseBridgeController.createStackHoverDelay
                : ShelfMouseBridgeController.addToStackHoverDelay
            bridge?.log("Stack hover target=\(target.id) delay=\(delay)s state=hover")
            let work = DispatchWorkItem { [weak self, weak targetView = target.view] in
                guard let self, self.internalDropTarget?.id == target.id else { return }
                (targetView as? ShelfScrubberItemView)?.setStackDropTargetReady(true)
                self.bridge?.log("stack ready | target=\(target.id) delay=\(delay)s")
            }
            targetReadyWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func clearInternalDropTarget() {
            targetReadyWorkItem?.cancel()
            targetReadyWorkItem = nil
            (internalDropTarget?.view as? ShelfScrubberItemView)?
                .setStackDropTargetHighlighted(false)
            internalDropTarget = nil
            internalDropTargetSince = nil
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            let isLocal = context == .withinApplication
            bridge?.log("Shelf Operation Mask | isLocal=\(isLocal) allowed=copy")
            return .copy
        }

        func draggingSession(
            _ session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint
        ) {
            bridge?.log("Shelf Drag Begin | point=\(screenPoint)")
        }

        func draggingSession(
            _ session: NSDraggingSession,
            movedTo screenPoint: NSPoint
        ) {
            bridge?.log("Shelf Drag Update | point=\(screenPoint)")
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            let accepted = !operation.isEmpty
            bridge?.log(
                "Shelf Drag End | point=\(screenPoint) operation=\(operation.rawValue) "
                    + "accepted=\(accepted) cancelled=\(!accepted)"
            )
            if accepted {
                bridge?.log("DragOut accepted; awaiting FilePromise copy")
            } else if let activePromiseID {
                bridge?.cancelPromise(id: activePromiseID)
            }
            (lockedSourceHit?.view as? ShelfScrubberItemView)?.setBridgePressed(false)
            mouseDownPoint = nil
            lockedSourceHit = nil
            gestureExceededThreshold = false
            clearInternalDropTarget()
            activePromiseID = nil
            externalDragStarted = false
            bridge?.pointerExited()
            bridge?.logBridgeState(reason: accepted ? "dragAccepted" : "dragCancelled")
            bridge?.gestureDidEnd()
        }
    }

    static let virtualTouchBarHeight: CGFloat = 40
    static let enterThreshold: CGFloat = 5
    static let exitThreshold: CGFloat = 12
    static let dragThresholdPixels: CGFloat = 5
    static let createStackHoverDelay: TimeInterval = 0.55
    static let addToStackHoverDelay: TimeInterval = 0.35
    static let maxDragPreviewWidth: CGFloat = 96
    static let maxDragPreviewHeight: CGFloat = 56

    private weak var delegate: ShelfMouseBridgeDelegate?
    private weak var physicalTouchBarView: NSView?
    private weak var cursorView: NSImageView?
    private weak var hoveredView: NSView?
    private weak var internalDragSourceView: ShelfScrubberItemView?
    private weak var internalFloatingView: NSImageView?
    private var directTouchSourceItemID: UUID?
    private var directTouchInsertionIndex: Int?
    private var directTouchDropTarget: ShelfBridgeHit?
    private var directTouchDropTargetSince: TimeInterval?
    private var directTouchReadyWorkItem: DispatchWorkItem?
    private var hoveredItemID: String?
    private var panel: BridgePanel?
    private var bridgeView: BridgeView?
    private var bridgeWidth: CGFloat = 1085
    private var heightInPixels = 5
    private var attachWorkItem: DispatchWorkItem?
    private var rebuildWorkItem: DispatchWorkItem?
    private var retainedPromiseWriters: [UUID: ShelfFilePromiseWriter] = [:]
    private var promiseItemIDs: [UUID: UUID] = [:]
    private var promiseSourceViews: [UUID: WeakShelfItemView] = [:]
    private var isPointerInsideBridge = false
    private var isPresentationRequested = false
    private var currentMode = "inactive"
    private var lastRebuildTime: Date?
    private var lastHitRegionCount = 0
    private var lastGapSourceItemID: UUID?
    private var lastGapInsertionIndex: Int?

    private var isDirectTouchDragging: Bool {
        directTouchSourceItemID != nil
    }

    private final class WeakShelfItemView {
        weak var view: ShelfScrubberItemView?
        init(_ view: ShelfScrubberItemView?) { self.view = view }
    }

    private(set) var virtualTouchBarRect = NSRect.zero

    fileprivate var currentPanelPoint: NSPoint? {
        guard let panel else { return nil }
        return panel.convertPoint(fromScreen: NSEvent.mouseLocation)
    }

    fileprivate var dragThresholdInPoints: CGFloat {
        let scale = max(NSScreen.main?.backingScaleFactor ?? 1, 1)
        return Self.dragThresholdPixels / scale
    }

    init(delegate: ShelfMouseBridgeDelegate) {
        self.delegate = delegate
        super.init()
    }

    func present(mode: String) {
        isPresentationRequested = true
        currentMode = mode
        scheduleHitRegionRebuild(delay: panel == nil ? 0.12 : 0.07)
    }

    func dismiss() {
        isPresentationRequested = false
        if isDirectTouchDragging {
            endInternalDrag(cancelled: true)
            clearDirectTouchDropTarget()
            directTouchSourceItemID = nil
            directTouchInsertionIndex = nil
        }
        attachWorkItem?.cancel()
        attachWorkItem = nil
        rebuildWorkItem?.cancel()
        rebuildWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
        bridgeView = nil
        pointerExited()
        physicalTouchBarView = nil
        currentMode = "inactive"
        logBridgeState(reason: "dismiss")
    }

    func requestHitRegionRebuild(mode: String) {
        guard isPresentationRequested else { return }
        currentMode = mode
        scheduleHitRegionRebuild(delay: 0.07)
    }

    func setHeightInPixels(_ pixels: Int) {
        heightInPixels = max(pixels, 2)
        updatePanelFrame()
    }

    fileprivate func hit(atPanelPoint panelPoint: NSPoint) -> ShelfBridgeHit? {
        guard let parent = physicalTouchBarView else { return nil }
        guard virtualTouchBarRect.contains(panelPoint) else { return nil }
        let point = touchBarPoint(from: panelPoint, in: parent)
        return delegate?.shelfMouseBridgeHit(atTouchBarPoint: point, in: parent)
    }

    fileprivate func pointerEntered() {
        guard !isPointerInsideBridge else { return }
        isPointerInsideBridge = true
        updatePanelFrame()
        log(
            "Shelf MouseBridge entered | virtualTouchBarRect=\(virtualTouchBarRect) "
                + "exitThreshold=\(Int(Self.exitThreshold))"
        )
        logBridgeState(reason: "pointerEntered")
    }

    fileprivate func pointerMoved(toPanelPoint panelPoint: NSPoint) {
        guard let parent = physicalTouchBarView else { return }
        let exitRect = virtualTouchBarRect.insetBy(
            dx: -Self.exitThreshold,
            dy: -Self.exitThreshold
        )
        guard exitRect.contains(panelPoint) else {
            pointerExited()
            return
        }
        showCursor(atPanelPoint: panelPoint, in: parent)
        let nextHit = hit(atPanelPoint: panelPoint)
        let nextView = nextHit?.view
        guard nextView !== hoveredView else { return }
        clearHover()
        hoveredView = nextView
        hoveredItemID = nextHit?.id
        setHighlighted(true, for: hoveredView)
        logBridgeState(reason: "hoverChanged")
    }

    fileprivate func pointerExited() {
        let wasInside = isPointerInsideBridge
        isPointerInsideBridge = false
        cursorView?.removeFromSuperview()
        cursorView = nil
        clearHover()
        if wasInside {
            updatePanelFrame()
            log("Shelf MouseBridge exited")
        }
    }

    fileprivate func clearHover() {
        setHighlighted(false, for: hoveredView)
        hoveredView = nil
        hoveredItemID = nil
    }

    fileprivate func gestureDidEnd() {
        scheduleHitRegionRebuild(delay: 0.07)
    }

    fileprivate func didClick(hit: ShelfBridgeHit) {
        if let item = hit.item {
            delegate?.shelfMouseBridgeDidClick(itemID: item.id)
        } else if let stackID = hit.stackID {
            delegate?.shelfMouseBridgeDidClickStack(stackID: stackID)
        } else if let button = hit.view as? NSButton, button.isEnabled {
            DispatchQueue.main.async {
                guard button.isEnabled else { return }
                button.performClick(nil)
            }
        }
    }

    fileprivate func internalDropTarget(
        for sourceItemID: UUID,
        atPanelPoint panelPoint: NSPoint
    ) -> ShelfBridgeHit? {
        guard let hit = hit(atPanelPoint: panelPoint),
              hit.item?.id != sourceItemID,
              (hit.item != nil || hit.stackID != nil),
              delegate?.shelfMouseBridgeCanDrop(sourceItemID: sourceItemID, onto: hit) == true
        else { return nil }
        return hit
    }

    fileprivate func didMerge(sourceItemID: UUID, targetItemID: UUID) {
        log("Stack merge requested | sourceItemID=\(sourceItemID) targetItemID=\(targetItemID)")
        delegate?.shelfMouseBridgeDidMerge(
            sourceItemID: sourceItemID,
            targetItemID: targetItemID
        )
    }

    fileprivate func didDrop(itemID: UUID, ontoStack stackID: UUID) {
        log("Shelf item dropped into stack | itemID=\(itemID) stackID=\(stackID)")
        delegate?.shelfMouseBridgeDidDrop(itemID: itemID, ontoStack: stackID)
    }

    fileprivate func didReorder(itemID: UUID, to destinationIndex: Int) {
        log("internal reorder requested | source item id=\(itemID) insertion index=\(destinationIndex)")
        delegate?.shelfMouseBridgeDidReorder(itemID: itemID, to: destinationIndex)
    }

    fileprivate func handleScroll(deltaX: CGFloat, deltaY: CGFloat, inverted: Bool) {
        let offset = delegate?.shelfMouseBridgeDidScroll(
            deltaX: deltaX,
            deltaY: deltaY,
            inverted: inverted
        )
        log(
            "Shelf scroll | deltaX=\(String(format: "%.2f", deltaX)) "
                + "shiftDeltaY=\(String(format: "%.2f", deltaY)) "
                + "new shelf scroll offset=\(offset.map { String(format: "%.2f", $0) } ?? "unavailable") "
                + "current container id=\(currentMode)"
        )
    }

    fileprivate func beginInternalDrag(source: ShelfBridgeHit?, atPanelPoint point: NSPoint) {
        guard let parent = physicalTouchBarView else { return }
        beginInternalDrag(
            source: source,
            atTouchBarPoint: touchBarPoint(from: point, in: parent),
            in: parent,
            input: "MouseBridge"
        )
    }

    private func beginInternalDrag(
        source: ShelfBridgeHit?,
        atTouchBarPoint point: NSPoint,
        in parent: NSView,
        input: String
    ) {
        guard internalFloatingView == nil,
              let sourceView = source?.view as? ShelfScrubberItemView
        else { return }
        physicalTouchBarView = parent
        sourceView.layoutSubtreeIfNeeded()
        let image = snapshot(of: sourceView)
        let floating = FloatingDragImageView(image: image)
        floating.imageScaling = .scaleProportionallyDown
        floating.wantsLayer = true
        floating.layer?.zPosition = 1_000
        floating.layer?.shadowColor = NSColor.black.cgColor
        floating.layer?.shadowOpacity = 0.38
        floating.layer?.shadowRadius = 7
        floating.layer?.shadowOffset = NSSize(width: 0, height: -1)
        floating.alphaValue = 0.94
        let size = NSSize(width: sourceView.bounds.width * 1.06, height: sourceView.bounds.height * 1.06)
        floating.frame = NSRect(origin: .zero, size: size)
        parent.addSubview(floating)
        internalDragSourceView = sourceView
        internalFloatingView = floating
        sourceView.alphaValue = 0.20
        updateFloatingView(atTouchBarPoint: point)
        let sourceIndex = allShelfItemViews(in: parent)
            .filter { $0.representedItem != nil }
            .sorted { lhs, rhs in
                let a = lhs.superview?.convert(lhs.frame, to: parent).midX ?? 0
                let b = rhs.superview?.convert(rhs.frame, to: parent).midX ?? 0
                return a < b
            }
            .firstIndex(where: { $0 === sourceView })
        let parentID = currentMode.hasPrefix("stack:") ? String(currentMode.dropFirst(6)) : "root"
        log(
            "internal drag begin | input=\(input) source item id=\(source?.item?.id.uuidString ?? "nil") "
                + "source index=\(sourceIndex.map(String.init) ?? "nil") parent stack=\(parentID)"
        )
    }

    fileprivate func updateInternalDrag(
        sourceItemID: UUID,
        atPanelPoint point: NSPoint
    ) -> Int? {
        guard let parent = physicalTouchBarView else { return nil }
        let touchPoint = touchBarPoint(from: point, in: parent)
        return updateInternalDrag(
            sourceItemID: sourceItemID,
            atTouchBarPoint: touchPoint,
            in: parent
        )
    }

    private func updateInternalDrag(
        sourceItemID: UUID,
        atTouchBarPoint touchPoint: NSPoint,
        in parent: NSView
    ) -> Int? {
        updateFloatingView(atTouchBarPoint: touchPoint)
        let insertion = delegate?.shelfMouseBridgeInsertionIndex(
            atTouchBarPoint: touchPoint,
            in: parent
        )
        let insertionChanged = lastGapSourceItemID != sourceItemID
            || lastGapInsertionIndex != insertion
        if insertionChanged {
            lastGapSourceItemID = sourceItemID
            lastGapInsertionIndex = insertion
            updatePlaceholderGap(sourceItemID: sourceItemID, insertionIndex: insertion, in: parent)
        }
        if let insertion, insertionChanged {
            log("internal drag update | source item id=\(sourceItemID) insertion index=\(insertion)")
        }
        return insertion
    }

    fileprivate func endInternalDrag(cancelled: Bool) {
        internalFloatingView?.removeFromSuperview()
        internalFloatingView = nil
        internalDragSourceView?.alphaValue = 1
        if cancelled {
            internalDragSourceView?.animateDragOutCancelled()
        }
        internalDragSourceView = nil
        resetPlaceholderGaps()
        lastGapSourceItemID = nil
        lastGapInsertionIndex = nil
        log("internal drag end | cancelled=\(cancelled)")
    }

    func beginDirectTouchDrag(
        sourceView: ShelfScrubberItemView,
        itemID: UUID,
        at point: NSPoint,
        in parent: NSView
    ) {
        guard directTouchSourceItemID == nil,
              sourceView.representedItem?.id == itemID
        else { return }
        directTouchSourceItemID = itemID
        directTouchInsertionIndex = nil
        clearDirectTouchDropTarget()
        let hit = ShelfBridgeHit(
            id: "shelf:\(itemID)",
            item: sourceView.representedItem,
            stackID: nil,
            view: sourceView
        )
        beginInternalDrag(
            source: hit,
            atTouchBarPoint: point,
            in: parent,
            input: "physicalTouch"
        )
        log("Touch Bar finger drag begin | source item id=\(itemID)")
    }

    func updateDirectTouchDrag(itemID: UUID, at point: NSPoint, in parent: NSView) {
        guard directTouchSourceItemID == itemID else { return }
        directTouchInsertionIndex = updateInternalDrag(
            sourceItemID: itemID,
            atTouchBarPoint: point,
            in: parent
        )
        let hit = delegate?.shelfMouseBridgeHit(atTouchBarPoint: point, in: parent)
        if let hit,
           hit.item?.id != itemID,
           (hit.item != nil || hit.stackID != nil),
           delegate?.shelfMouseBridgeCanDrop(sourceItemID: itemID, onto: hit) == true {
            updateDirectTouchDropTarget(hit)
        } else {
            clearDirectTouchDropTarget()
        }
    }

    func endDirectTouchDrag(
        itemID: UUID,
        at point: NSPoint,
        in parent: NSView,
        cancelled: Bool
    ) {
        guard directTouchSourceItemID == itemID else { return }
        if !cancelled {
            updateDirectTouchDrag(itemID: itemID, at: point, in: parent)
        }
        let target = directTouchDropTarget
        let delay = target?.stackID == nil
            ? Self.createStackHoverDelay
            : Self.addToStackHoverDelay
        let ready = !cancelled
            && target != nil
            && ProcessInfo.processInfo.systemUptime - (directTouchDropTargetSince ?? .infinity) >= delay
        if ready, let target {
            if let stackID = target.stackID {
                didDrop(itemID: itemID, ontoStack: stackID)
            } else if let targetItemID = target.item?.id {
                didMerge(sourceItemID: itemID, targetItemID: targetItemID)
            }
        } else if !cancelled, let insertion = directTouchInsertionIndex {
            didReorder(itemID: itemID, to: insertion)
        }
        endInternalDrag(cancelled: cancelled)
        clearDirectTouchDropTarget()
        directTouchSourceItemID = nil
        directTouchInsertionIndex = nil
        log("Touch Bar finger drag end | source item id=\(itemID) cancelled=\(cancelled) stackReady=\(ready)")
        gestureDidEnd()
    }

    private func updateDirectTouchDropTarget(_ target: ShelfBridgeHit) {
        guard target.id != directTouchDropTarget?.id else { return }
        clearDirectTouchDropTarget()
        directTouchDropTarget = target
        directTouchDropTargetSince = ProcessInfo.processInfo.systemUptime
        (target.view as? ShelfScrubberItemView)?.setStackDropTargetHighlighted(true)
        let delay = target.stackID == nil ? Self.createStackHoverDelay : Self.addToStackHoverDelay
        log("Touch Bar finger hover target=\(target.id) stackReady timer=\(delay)s")
        let work = DispatchWorkItem { [weak self, weak targetView = target.view] in
            guard let self, self.directTouchDropTarget?.id == target.id else { return }
            (targetView as? ShelfScrubberItemView)?.setStackDropTargetReady(true)
            self.log("Touch Bar finger stackReady state=true target=\(target.id)")
        }
        directTouchReadyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func clearDirectTouchDropTarget() {
        directTouchReadyWorkItem?.cancel()
        directTouchReadyWorkItem = nil
        (directTouchDropTarget?.view as? ShelfScrubberItemView)?
            .setStackDropTargetHighlighted(false)
        directTouchDropTarget = nil
        directTouchDropTargetSince = nil
    }

    fileprivate func log(_ message: String) {
        delegate?.shelfMouseBridgeDidLog(message)
    }

    private func snapshot(of view: NSView) -> NSImage {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return (view as? ShelfScrubberItemView)?.representedItem?.displayImage
                ?? NSImage(size: view.bounds.size)
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private func updateFloatingView(atPanelPoint point: NSPoint, in parent: NSView) {
        let touchPoint = touchBarPoint(from: point, in: parent)
        updateFloatingView(atTouchBarPoint: touchPoint)
    }

    private func updateFloatingView(atTouchBarPoint touchPoint: NSPoint) {
        guard let floating = internalFloatingView else { return }
        floating.frame.origin = NSPoint(
            x: touchPoint.x - floating.frame.width / 2,
            y: touchPoint.y - floating.frame.height / 2
        )
    }

    private func updatePlaceholderGap(
        sourceItemID: UUID,
        insertionIndex: Int?,
        in parent: NSView
    ) {
        let views = allShelfItemViews(in: parent)
            .filter { $0.representedItem != nil }
            .sorted { lhs, rhs in
                let a = lhs.superview?.convert(lhs.frame, to: parent).midX ?? 0
                let b = rhs.superview?.convert(rhs.frame, to: parent).midX ?? 0
                return a < b
            }
        guard let sourceIndex = views.firstIndex(where: { $0.representedItem?.id == sourceItemID }),
              let insertionIndex
        else {
            views.forEach { $0.setInternalDragShift(0) }
            return
        }
        let destination = min(max(insertionIndex, 0), views.count)
        for (index, view) in views.enumerated() {
            var shift: CGFloat = 0
            if destination > sourceIndex + 1, index > sourceIndex && index < destination {
                shift = -18
            } else if destination <= sourceIndex, index >= destination && index < sourceIndex {
                shift = 18
            }
            view.setInternalDragShift(shift)
        }
    }

    private func resetPlaceholderGaps() {
        guard let parent = physicalTouchBarView else { return }
        allShelfItemViews(in: parent).forEach { $0.setInternalDragShift(0) }
    }

    private func allShelfItemViews(in view: NSView) -> [ShelfScrubberItemView] {
        var result: [ShelfScrubberItemView] = []
        if let item = view as? ShelfScrubberItemView { result.append(item) }
        for child in view.subviews {
            result.append(contentsOf: allShelfItemViews(in: child))
        }
        return result
    }

    fileprivate func makePromiseWriter(
        for item: FileShelfItem,
        sourceView: ShelfScrubberItemView?
    ) -> ShelfFilePromiseWriter {
        let id = UUID()
        let writer = ShelfFilePromiseWriter(
            id: id,
            sourceURL: item.url,
            logHandler: { [weak self] message in self?.log(message) },
            finishedHandler: { [weak self] success in
                self?.promiseFinished(id: id, success: success)
            }
        )
        retainedPromiseWriters[id] = writer
        promiseItemIDs[id] = item.id
        promiseSourceViews[id] = WeakShelfItemView(sourceView)
        return writer
    }

    fileprivate func cancelPromise(id: UUID) {
        guard retainedPromiseWriters[id] != nil else { return }
        promiseSourceViews.removeValue(forKey: id)?.view?.animateDragOutCancelled()
        retainedPromiseWriters[id] = nil
        promiseItemIDs[id] = nil
        log("DragOut cancelled keep item")
    }

    private func promiseFinished(id: UUID, success: Bool) {
        let itemID = promiseItemIDs.removeValue(forKey: id)
        let sourceView = promiseSourceViews.removeValue(forKey: id)?.view
        retainedPromiseWriters[id] = nil
        guard success, let itemID else {
            sourceView?.animateDragOutCancelled()
            log("DragOut failed keep item")
            return
        }
        log("FilePromise copy success")
        let finishRemoval = { [weak self] in
            self?.delegate?.shelfMouseBridgeDidCompleteCopy(itemID: itemID)
            self?.log("DragOut success remove item")
        }
        if let sourceView {
            sourceView.animateDragOutSuccess(completion: finishRemoval)
        } else {
            finishRemoval()
        }
    }

    private func attachToPhysicalTouchBar() {
        guard isPresentationRequested else { return }
        if bridgeView?.hasActiveGesture == true || isDirectTouchDragging {
            scheduleHitRegionRebuild(delay: 0.07)
            logBridgeState(reason: "rebuildDeferredForActiveGesture")
            return
        }
        guard let parent = NSFunctionRow._topLevelViews().last,
              parent.visibleRect.width > 100
        else {
            log("Shelf MouseBridge unavailable: no physical Touch Bar view")
            return
        }
        if physicalTouchBarView !== parent {
            cursorView?.removeFromSuperview()
            cursorView = nil
            physicalTouchBarView = parent
        }
        bridgeWidth = parent.visibleRect.width
        if panel == nil {
            createPanel()
        } else {
            updatePanelFrame()
        }
        lastRebuildTime = Date()
        let names = delegate?.shelfMouseBridgeRegisteredHitRegionNames(in: parent) ?? []
        lastHitRegionCount = names.count
        log("Registered hit regions:\n" + names.map { "- \($0)" }.joined(separator: "\n"))
        logBridgeState(reason: "hitRegionsRebuilt", hitRegionCount: names.count)
    }

    private func scheduleHitRegionRebuild(delay: TimeInterval) {
        rebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildWorkItem = nil
            self?.attachToPhysicalTouchBar()
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    fileprivate func logBridgeState(reason: String, hitRegionCount: Int? = nil) {
        let count: Int
        if let hitRegionCount {
            count = hitRegionCount
        } else {
            count = lastHitRegionCount
        }
        let formatter = ISO8601DateFormatter()
        let rebuild = lastRebuildTime.map(formatter.string(from:)) ?? "never"
        let activeItem = bridgeView?.activeItemID
            ?? promiseItemIDs.values.first
        log(
            "bridge active=\(panel != nil && isPresentationRequested) "
                + "current mode=\(currentMode) hitRegions count=\(count) "
                + "hovered item id=\(hoveredItemID ?? "none") "
                + "active drag item id=\(activeItem?.uuidString ?? "none") "
                + "last rebuild time=\(rebuild) reason=\(reason)"
        )
    }

    private func createPanel() {
        panel?.orderOut(nil)
        let panel = BridgePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let view = BridgeView(frame: .zero)
        view.bridge = self
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        self.panel = panel
        bridgeView = view
        updatePanelFrame()
        panel.orderFrontRegardless()
    }

    private func updatePanelFrame() {
        guard let panel, let screen = NSScreen.main else { return }
        let scale = max(screen.backingScaleFactor, 1)
        let configuredEnterHeight = max(
            CGFloat(heightInPixels) / scale,
            Self.enterThreshold
        )
        let horizontalMargin = isPointerInsideBridge ? Self.exitThreshold : 0
        let height = isPointerInsideBridge
            ? Self.virtualTouchBarHeight + Self.exitThreshold
            : configuredEnterHeight
        panel.setFrame(
            NSRect(
                x: screen.frame.midX - bridgeWidth / 2 - horizontalMargin,
                y: screen.frame.minY,
                width: bridgeWidth + horizontalMargin * 2,
                height: height
            ),
            display: true
        )
        bridgeView?.frame = NSRect(origin: .zero, size: panel.contentView?.bounds.size ?? .zero)
        virtualTouchBarRect = NSRect(
            x: horizontalMargin,
            y: 0,
            width: bridgeWidth,
            height: Self.virtualTouchBarHeight
        )
    }

    private func touchBarPoint(from panelPoint: NSPoint, in parent: NSView) -> NSPoint {
        let normalizedX = (panelPoint.x - virtualTouchBarRect.minX)
            / max(virtualTouchBarRect.width, 1)
        let normalizedY = (panelPoint.y - virtualTouchBarRect.minY)
            / max(virtualTouchBarRect.height, 1)
        return NSPoint(
            x: min(max(normalizedX, 0), 1) * parent.bounds.width,
            y: min(max(normalizedY, 0), 1) * parent.bounds.height
        )
    }

    private func showCursor(atPanelPoint panelPoint: NSPoint, in parent: NSView) {
        let touchPoint = touchBarPoint(from: panelPoint, in: parent)
        let cursor: NSImageView
        if let cursorView {
            cursor = cursorView
        } else {
            cursor = NSImageView(image: NSCursor.arrow.image)
            cursor.frame.size = NSSize(width: 18, height: 18)
            cursor.wantsLayer = true
            cursor.layer?.zPosition = 999
            parent.addSubview(cursor)
            cursorView = cursor
        }
        cursor.frame.origin = NSPoint(
            x: min(
                max(touchPoint.x - cursor.frame.width / 2, 0),
                max(parent.bounds.width - cursor.frame.width, 0)
            ),
            y: min(
                max(touchPoint.y - cursor.frame.height / 2, 0),
                max(parent.bounds.height - cursor.frame.height, 0)
            )
        )
    }

    private func setHighlighted(_ highlighted: Bool, for view: NSView?) {
        if let itemView = view as? ShelfScrubberItemView {
            itemView.isBridgeHighlighted = highlighted
        } else if let button = view as? NSButton {
            button.isHighlighted = highlighted
        }
    }

    private static func promiseType(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        if values?.isDirectory == true {
            return UTType.folder.identifier
        }
        return values?.contentType?.identifier ?? UTType.data.identifier
    }

    private static func dragPreview(for image: NSImage) -> (image: NSImage, size: NSSize) {
        let fitted = FileShelfModel.aspectFit(
            image,
            maxWidth: maxDragPreviewWidth,
            maxHeight: maxDragPreviewHeight
        )
        return (fitted, fitted.size)
    }
}
