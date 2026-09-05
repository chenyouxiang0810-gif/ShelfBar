import AppKit
import UniformTypeIdentifiers

@MainActor
protocol ShelfMouseBridgeDelegate: AnyObject {
    func shelfMouseBridgeHit(atTouchBarPoint point: NSPoint, in parentView: NSView) -> ShelfBridgeHit?
    func shelfMouseBridgeRegisteredHitRegionNames(in parentView: NSView) -> [String]
    func shelfMouseBridgeDidClick(itemID: UUID)
    func shelfMouseBridgeDidClickFile(fileURL: URL, fallbackItemID: UUID)
    func shelfMouseBridgeDidClickClipboard(itemID: UUID)
    func shelfMouseBridgeDidClickSearchResult(resultID: UUID)
    func shelfMouseBridgeDidClickStack(stackID: UUID)
    func shelfMouseBridgeCanDrop(sourceItemID: UUID, onto hit: ShelfBridgeHit) -> Bool
    func shelfMouseBridgeDidMerge(sourceItemID: UUID, targetItemID: UUID)
    func shelfMouseBridgeDidDrop(itemID: UUID, ontoStack stackID: UUID)
    func shelfMouseBridgeInsertionIndex(atTouchBarPoint point: NSPoint, in parentView: NSView) -> Int?
    func shelfMouseBridgeDidReorder(itemID: UUID, to destinationIndex: Int)
    func shelfMouseBridgeDidScroll(deltaX: CGFloat, deltaY: CGFloat, inverted: Bool) -> CGFloat?
    func shelfMouseBridgeDiagnosticContext(atTouchBarPoint point: NSPoint, in parentView: NSView) -> String
    func shelfMouseBridgeCanAttach(in parentView: NSView, mode: String) -> Bool
    func shelfMouseBridgeAttachDiagnosticContext(in parentView: NSView, mode: String) -> String
    func shelfMouseBridgeDidCompleteCopy(itemID: UUID)
    func shelfMouseBridgeDidLog(_ message: String)
}

@MainActor
struct ShelfBridgeHit {
    let id: String
    let item: FileShelfItem?
    let clipboardItem: ClipboardShelfItem?
    let searchResultID: UUID?
    let stackID: UUID?
    let view: NSView
    let allowsReorder: Bool

    init(
        id: String,
        item: FileShelfItem? = nil,
        clipboardItem: ClipboardShelfItem? = nil,
        searchResultID: UUID? = nil,
        stackID: UUID? = nil,
        view: NSView,
        allowsReorder: Bool = true
    ) {
        self.id = id
        self.item = item
        self.clipboardItem = clipboardItem
        self.searchResultID = searchResultID
        self.stackID = stackID
        self.view = view
        self.allowsReorder = allowsReorder
    }

    var reorderID: UUID? {
        guard allowsReorder else { return nil }
        return item?.id ?? stackID
    }
}

private enum ShelfInternalDropClassification {
    case stack(ShelfBridgeHit)
    case insert(Int?)
    case none
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

    private final class InsertionIndicatorView: NSView {
        private let shapeLayer = CAShapeLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            alphaValue = 0
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.shadowColor = NSColor.systemBlue.cgColor
            layer?.shadowOpacity = 0.18
            layer?.shadowRadius = 4
            layer?.shadowOffset = .zero
            shapeLayer.fillColor = NSColor.systemBlue.withAlphaComponent(0.11).cgColor
            shapeLayer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.82).cgColor
            shapeLayer.lineWidth = 1.5
            shapeLayer.lineDashPattern = [5, 4]
            layer?.addSublayer(shapeLayer)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func layout() {
            super.layout()
            updatePath()
        }

        func updatePath() {
            shapeLayer.frame = bounds
            shapeLayer.path = CGPath(
                roundedRect: bounds.insetBy(dx: 1, dy: 1),
                cornerWidth: 5,
                cornerHeight: 5,
                transform: nil
            )
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private final class BridgePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class BridgeView: NSView, NSDraggingSource {
        private enum GesturePhase: String {
            case idle
            case pressed
            case tap
            case scroll
            case reorder
        }

        weak var bridge: ShelfMouseBridgeController?
        private var trackingAreaReference: NSTrackingArea?
        private var mouseDownPoint: NSPoint?
        private var lockedSourceHit: ShelfBridgeHit?
        private var gesturePhase: GesturePhase = .idle
        private var gestureExceededThreshold = false
        private var externalDragStarted = false
        private var internalDragStarted = false
        private var internalInsertionIndex: Int?
        private var activePromiseID: UUID?
        private var internalDropTarget: ShelfBridgeHit?
        private var internalDropTargetSince: TimeInterval?
        private var targetReadyWorkItem: DispatchWorkItem?
        private var lastScrollDragPoint: NSPoint?
        private var mouseDownTime: TimeInterval?
        private var dragScrollStarted = false
        private var internalReorderArmed = false
        private var reorderArmWorkItem: DispatchWorkItem?

        var hasActiveGesture: Bool {
            mouseDownPoint != nil || externalDragStarted || internalDragStarted
        }

        var activeItemID: UUID? {
            lockedSourceHit?.reorderID
        }

        deinit {
            targetReadyWorkItem?.cancel()
            reorderArmWorkItem?.cancel()
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
                inverted: event.isDirectionInvertedFromDevice,
                source: "scrollWheel"
            )
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = event.locationInWindow
            mouseDownTime = ProcessInfo.processInfo.systemUptime
            lockedSourceHit = bridge?.hit(atPanelPoint: event.locationInWindow)
            gesturePhase = .pressed
            gestureExceededThreshold = false
            externalDragStarted = false
            internalDragStarted = false
            internalInsertionIndex = nil
            activePromiseID = nil
            lastScrollDragPoint = nil
            clearInternalDropTarget()
            dragScrollStarted = false
            internalReorderArmed = false
            reorderArmWorkItem?.cancel()
            reorderArmWorkItem = nil
            if lockedSourceHit?.reorderID != nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self,
                          self.mouseDownPoint != nil,
                          !self.dragScrollStarted,
                          !self.externalDragStarted,
                          !self.internalDragStarted
                    else { return }
                    self.internalReorderArmed = true
                    self.bridge?.log("MouseBridge internal reorder armed after hold")
                }
                reorderArmWorkItem = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + ShelfMouseBridgeController.mouseReorderPressDelay,
                    execute: work
                )
            }
            (lockedSourceHit?.view as? ShelfScrubberItemView)?.setBridgePressed(true)
            bridge?.log("Mouse gesture idle -> pressed | hit=\(lockedSourceHit?.id ?? "nil")")
            if let bridge, let parent = bridge.physicalTouchBarView {
                let touchPoint = bridge.touchBarPoint(from: event.locationInWindow, in: parent)
                bridge.log(
                    "MouseBridge mouseDown route | "
                        + (bridge.delegate?.shelfMouseBridgeDiagnosticContext(
                            atTouchBarPoint: touchPoint,
                            in: parent
                        ) ?? "diagnostic unavailable")
                )
            }
            bridge?.logBridgeState(reason: "mouseDown")
        }

        override func mouseDragged(with event: NSEvent) {
            if gesturePhase == .reorder {
                guard !externalDragStarted,
                      let sourceID = lockedSourceHit?.reorderID
                else { return }
                internalInsertionIndex = bridge?.updateInternalDrag(
                    sourceItemID: sourceID,
                    atPanelPoint: event.locationInWindow
                )
                if lockedSourceHit?.item != nil,
                   let target = bridge?.internalDropTarget(
                    for: sourceID,
                    atPanelPoint: event.locationInWindow
                   ) {
                    updateInternalDropTarget(target)
                } else {
                    clearInternalDropTarget()
                }
                return
            }

            if lockedSourceHit?.reorderID == nil {
                guard let start = mouseDownPoint else { return }
                let previous = lastScrollDragPoint ?? start
                let deltaX = event.locationInWindow.x - previous.x
                let deltaY = event.locationInWindow.y - previous.y
                let totalDistance = hypot(
                    event.locationInWindow.x - start.x,
                    event.locationInWindow.y - start.y
                )
                let threshold = bridge?.dragThresholdInPoints ?? 5
                guard totalDistance >= threshold else { return }
                gestureExceededThreshold = true
                dragScrollStarted = true
                gesturePhase = .scroll
                internalReorderArmed = false
                reorderArmWorkItem?.cancel()
                lastScrollDragPoint = event.locationInWindow
                bridge?.log("Mouse gesture pressed -> scroll | hit=\(lockedSourceHit?.id ?? "nil")")
                bridge?.handleScroll(deltaX: -deltaX, deltaY: -deltaY, inverted: false, source: "mouseDragged")
                return
            }

            guard !externalDragStarted,
                  let start = mouseDownPoint,
                  let sourceID = lockedSourceHit?.reorderID
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
            let elapsed = ProcessInfo.processInfo.systemUptime - (mouseDownTime ?? 0)
            let leftVirtualTouchBar = event.locationInWindow.y
                > (bridge?.virtualTouchBarRect.maxY ?? 40)
            let isUpwardIntent = deltaY >= threshold
                && (leftVirtualTouchBar || deltaY >= abs(deltaX))
            if dragScrollStarted || gesturePhase == .scroll {
                gestureExceededThreshold = true
                let previous = lastScrollDragPoint ?? start
                bridge?.handleScroll(
                    deltaX: -(event.locationInWindow.x - previous.x),
                    deltaY: -(event.locationInWindow.y - previous.y),
                    inverted: false,
                    source: "mouseDragged"
                )
                lastScrollDragPoint = event.locationInWindow
                bridge?.log("MouseBridge scroll retained; reorder suppressed")
                return
            }
            if !internalReorderArmed,
               elapsed < ShelfMouseBridgeController.mouseReorderPressDelay {
                if !isUpwardIntent {
                    gestureExceededThreshold = true
                    dragScrollStarted = true
                    gesturePhase = .scroll
                    internalReorderArmed = false
                    reorderArmWorkItem?.cancel()
                    lastScrollDragPoint = event.locationInWindow
                    bridge?.log("Mouse gesture pressed -> scroll | hit=\(lockedSourceHit?.id ?? "nil") reason=movement-before-reorder")
                    bridge?.handleScroll(
                        deltaX: -deltaX,
                        deltaY: -deltaY,
                        inverted: false,
                        source: "mouseDragged"
                    )
                }
                return
            }
            guard internalReorderArmed || elapsed >= ShelfMouseBridgeController.mouseReorderPressDelay else { return }
            gestureExceededThreshold = true
            if !isUpwardIntent || lockedSourceHit?.item == nil {
                if !internalDragStarted {
                    internalDragStarted = true
                    gesturePhase = .reorder
                    bridge?.log("Mouse gesture pressed -> reorder | hit=\(lockedSourceHit?.id ?? "nil")")
                    bridge?.beginInternalDrag(
                        source: lockedSourceHit,
                        atPanelPoint: event.locationInWindow
                    )
                }
                internalInsertionIndex = bridge?.updateInternalDrag(
                    sourceItemID: sourceID,
                    atPanelPoint: event.locationInWindow
                )
                if lockedSourceHit?.item != nil,
                   let target = bridge?.internalDropTarget(
                    for: sourceID,
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
            gesturePhase = .reorder
            (lockedSourceHit?.view as? ShelfScrubberItemView)?.setBridgePressed(false)
            guard let bridge else { return }
            guard let item = lockedSourceHit?.item else { return }
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
                resetSession(reason: "mouseUpExternalDrag")
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
                resetSession(reason: "mouseUp")
            }
            guard let hit = lockedSourceHit else { return }
            if dragScrollStarted {
                bridge?.clearHover()
                bridge?.log("Mouse gesture scroll -> idle | hit=\(hit.id)")
                bridge?.log("MouseBridge drag-to-scroll ended")
                return
            }
            if gestureExceededThreshold,
               let sourceID = hit.reorderID,
               bridge?.commitInternalDrag(
                itemID: sourceID,
                target: releasedTarget,
                targetIsReady: targetWasArmed,
                insertionIndex: internalInsertionIndex ?? bridge?.internalDragLastInsertionIndex,
                cancelled: bridge?.internalDragIsOutsideCommitBounds == true,
                source: "MouseBridge"
               ) == true {
                bridge?.endInternalDrag(cancelled: bridge?.internalDragIsOutsideCommitBounds == true)
                internalDragStarted = false
            } else if !gestureExceededThreshold {
                gesturePhase = .tap
                bridge?.log("Mouse gesture pressed -> tap | hit=\(hit.id)")
                if let releasedHit, releasedHit.id == hit.id {
                    bridge?.didClick(hit: releasedHit)
                } else if !hit.view.isHidden, hit.view.alphaValue > 0.01 {
                    bridge?.log("MouseBridge click used locked mouseDown hit after release hit mismatch")
                    bridge?.didClick(hit: hit)
                } else {
                    bridge?.clearHover()
                    bridge?.log("MouseBridge stale locked hit ignored")
                }
            } else {
                bridge?.clearHover()
                bridge?.log("Mouse gesture pressed -> idle | hit=\(hit.id) reason=blank mouseUp")
                bridge?.log("MouseBridge blank mouseUp ignored")
            }
        }

        private func updateInternalDropTarget(_ target: ShelfBridgeHit) {
            guard target.id != internalDropTarget?.id else { return }
            clearInternalDropTarget()
            internalDropTarget = target
            internalDropTargetSince = ProcessInfo.processInfo.systemUptime
            let delay = target.stackID == nil
                ? ShelfMouseBridgeController.createStackHoverDelay
                : ShelfMouseBridgeController.addToStackHoverDelay
            bridge?.log("Stack dwell target=\(target.id) delay=\(delay)s state=pending")
            let work = DispatchWorkItem { [weak self, weak targetView = target.view] in
                guard let self, self.internalDropTarget?.id == target.id else { return }
                (targetView as? ShelfScrubberItemView)?.setStackDropTargetHighlighted(true)
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
            resetSession(reason: accepted ? "dragAccepted" : "dragCancelled")
            bridge?.pointerExited()
            bridge?.logBridgeState(reason: accepted ? "dragAccepted" : "dragCancelled")
            bridge?.gestureDidEnd()
        }

        private func resetSession(reason: String) {
            if internalDragStarted {
                bridge?.endInternalDrag(cancelled: true)
            }
            (lockedSourceHit?.view as? ShelfScrubberItemView)?.setBridgePressed(false)
            mouseDownPoint = nil
            mouseDownTime = nil
            lockedSourceHit = nil
            gesturePhase = .idle
            gestureExceededThreshold = false
            externalDragStarted = false
            internalDragStarted = false
            internalInsertionIndex = nil
            activePromiseID = nil
            lastScrollDragPoint = nil
            dragScrollStarted = false
            internalReorderArmed = false
            reorderArmWorkItem?.cancel()
            reorderArmWorkItem = nil
            clearInternalDropTarget()
            bridge?.clearHover()
            bridge?.logBridgeState(reason: "resetSession:\(reason)")
        }

        func resetInteractionState(reason: String) {
            resetSession(reason: reason)
        }
    }

    static let virtualTouchBarHeight: CGFloat = 40
    static let enterThreshold: CGFloat = 5
    static let exitThreshold: CGFloat = 12
    static let dragThresholdPixels: CGFloat = 5
    static let createStackHoverDelay: TimeInterval = 0.16
    static let addToStackHoverDelay: TimeInterval = 0.14
    static let mouseReorderPressDelay: TimeInterval = 0.28
    static let stackDropCenterFraction: CGFloat = 0.42
    static let insertionHysteresis: CGFloat = 9
    static let dragEdgeAutoScrollZone: CGFloat = 54
    static let dragEdgeAutoScrollMaxStep: CGFloat = 9.4
    static let dragOutsideCancelMargin: CGFloat = 18
    static let maxDragPreviewWidth: CGFloat = 96
    static let maxDragPreviewHeight: CGFloat = 56
    private static let readyAttachRetryDelay: TimeInterval = 0.035
    private static let maxReadyAttachAttempts = 14

    private weak var delegate: ShelfMouseBridgeDelegate?
    private weak var physicalTouchBarView: NSView?
    private weak var cursorView: NSImageView?
    private weak var hoveredView: NSView?
    private weak var internalDragSourceView: ShelfScrubberItemView?
    private weak var internalFloatingView: NSImageView?
    private var internalDragSourceID: UUID?
    private var internalDragSourceFrame = NSRect.zero
    private var internalDragLastPoint = NSPoint.zero
    private var internalDragLastRawTouchBarPoint: NSPoint?
    private var internalDragLastContentSpaceX: CGFloat = 0
    private var internalDragLastInsertionIndex: Int?
    private var internalDragIsOutsideCommitBounds = false
    private var dragAutoScrollWorkItem: DispatchWorkItem?
    private var dragAutoScrollDeltaX: CGFloat = 0
    private weak var reorderLockedScrollView: NSScrollView?
    private var reorderAllowedScrollOriginX: CGFloat?
    private var insertionIndicatorView: InsertionIndicatorView?
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
    private var readyAttachAttempt = 0
    private var readyAttachStartedAt: TimeInterval?
    private var pendingReadyAttachReason = "unknown"
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
    private var internalDragShiftByViewID: [ObjectIdentifier: CGFloat] = [:]

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
        let wasRequested = isPresentationRequested
        isPresentationRequested = true
        currentMode = mode
        if panel != nil {
            panel?.orderFrontRegardless()
            updatePanelFrame()
        }
        log(
            "BugFix18 MouseBridge present requested | mode=\(mode) "
                + "panelExists=\(panel != nil) alreadyRequested=\(wasRequested)"
        )
        requestReadyAttach(
            mode: mode,
            reason: wasRequested ? "present-refresh" : "present-initial"
        )
    }

    func dismiss() {
        isPresentationRequested = false
        bridgeView?.resetInteractionState(reason: "dismiss")
        if isDirectTouchDragging {
            endInternalDrag(cancelled: true)
            clearDirectTouchDropTarget()
            directTouchSourceItemID = nil
            directTouchInsertionIndex = nil
        }
        stopDragAutoScroll()
        hideInsertionIndicator(animated: false)
        attachWorkItem?.cancel()
        attachWorkItem = nil
        rebuildWorkItem?.cancel()
        rebuildWorkItem = nil
        readyAttachAttempt = 0
        readyAttachStartedAt = nil
        panel?.orderOut(nil)
        panel = nil
        bridgeView = nil
        pointerExited()
        physicalTouchBarView = nil
        currentMode = "inactive"
        logBridgeState(reason: "dismiss")
    }

    func resetTransientInteractionState(reason: String) {
        bridgeView?.resetInteractionState(reason: reason)
        if isDirectTouchDragging {
            endInternalDrag(cancelled: true)
        }
        stopDragAutoScroll()
        clearDirectTouchDropTarget()
        directTouchSourceItemID = nil
        directTouchInsertionIndex = nil
        hideInsertionIndicator(animated: false)
        resetPlaceholderGaps(animated: false)
        clearHover()
        logBridgeState(reason: "transientReset:\(reason)")
    }

    func debugStateSummary(parentView: NSView? = nil) -> String {
        let root = parentView ?? physicalTouchBarView
        let bridgeTrackingCount = bridgeView?.trackingAreas.count ?? 0
        let touchBarTrackingCount = root.map { recursiveTrackingAreaCount(in: $0) } ?? 0
        let visibleItemCount = root.map {
            delegate?.shelfMouseBridgeRegisteredHitRegionNames(in: $0).count ?? 0
        } ?? 0
        return "ShelfBridge mode=\(currentMode) requested=\(isPresentationRequested) "
            + "panel=\(panel != nil ? 1 : 0) bridgeView=\(bridgeView != nil ? 1 : 0) "
            + "bridgeTrackingAreas=\(bridgeTrackingCount) touchBarTrackingAreas=\(touchBarTrackingCount) "
            + "visibleInteractiveViews=\(visibleItemCount) pointerInside=\(isPointerInsideBridge) "
            + "activeMouseGesture=\(bridgeView?.hasActiveGesture == true) "
            + "directTouchActive=\(isDirectTouchDragging) readyAttachAttempt=\(readyAttachAttempt) "
            + "hitRegions=\(lastHitRegionCount)"
    }

    func isGestureNeutralForDebug() -> Bool {
        bridgeView?.hasActiveGesture != true
            && !isDirectTouchDragging
            && directTouchDropTarget == nil
            && directTouchReadyWorkItem == nil
            && internalFloatingView == nil
            && insertionIndicatorView == nil
            && lastGapSourceItemID == nil
            && lastGapInsertionIndex == nil
    }

    func requestHitRegionRebuild(mode: String) {
        guard isPresentationRequested else { return }
        requestReadyAttach(mode: mode, reason: "hit-region-rebuild")
    }

    func requestReadyAttach(mode: String, reason: String) {
        guard isPresentationRequested else { return }
        currentMode = mode
        readyAttachAttempt = 0
        readyAttachStartedAt = ProcessInfo.processInfo.systemUptime
        pendingReadyAttachReason = reason
        scheduleReadyAttach(delay: 0)
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
        guard bridgeView?.hasActiveGesture != true, !isDirectTouchDragging else {
            clearHover()
            return
        }
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
        if let resultID = hit.searchResultID {
            delegate?.shelfMouseBridgeDidClickSearchResult(resultID: resultID)
        } else if let item = hit.item {
            delegate?.shelfMouseBridgeDidClickFile(fileURL: item.url, fallbackItemID: item.id)
        } else if let item = hit.clipboardItem {
            delegate?.shelfMouseBridgeDidClickClipboard(itemID: item.id)
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
        guard !internalDragIsOutsideCommitBounds else { return nil }
        guard let parent = physicalTouchBarView else { return nil }
        let touchPoint = touchBarPoint(from: panelPoint, in: parent)
        if case let .stack(hit) = classifyDrop(
            sourceItemID: sourceItemID,
            atTouchBarPoint: touchPoint,
            in: parent
        ) {
            return hit
        }
        return nil
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

    fileprivate func handleScroll(deltaX: CGFloat, deltaY: CGFloat, inverted: Bool, source: String) {
        let offset = delegate?.shelfMouseBridgeDidScroll(
            deltaX: deltaX,
            deltaY: deltaY,
            inverted: inverted
        )
        if source == "dragEdgeAutoScroll" {
            updateReorderAllowedScrollOrigin()
        }
        let diagnostic: String
        if let parent = physicalTouchBarView, let panelPoint = currentPanelPoint {
            let touchPoint = touchBarPoint(from: panelPoint, in: parent)
            diagnostic = delegate?.shelfMouseBridgeDiagnosticContext(
                atTouchBarPoint: touchPoint,
                in: parent
            ) ?? "diagnostic unavailable"
        } else {
            diagnostic = "diagnostic unavailable"
        }
        log(
            "Shelf scroll | source=\(source) deltaX=\(String(format: "%.2f", deltaX)) "
                + "shiftDeltaY=\(String(format: "%.2f", deltaY)) "
                + "new shelf scroll offset=\(offset.map { String(format: "%.2f", $0) } ?? "unavailable") "
                + "current container id=\(currentMode) \(diagnostic)"
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
        let sourceFrame = sourceView.superview?.convert(sourceView.frame, to: parent) ?? sourceView.frame
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
        internalDragSourceID = source?.reorderID
        internalDragSourceFrame = sourceFrame
        internalDragLastPoint = point
        internalDragLastRawTouchBarPoint = point
        internalDragLastContentSpaceX = contentSpaceX(for: point, in: parent)
        let sourceIndex = reorderableShelfItemViews(in: parent)
            .firstIndex(where: { $0 === sourceView })
        internalDragLastInsertionIndex = sourceIndex
        internalDragIsOutsideCommitBounds = false
        captureReorderScrollLock(in: parent)
        sourceView.setBridgePressed(false)
        sourceView.setInternalDragLifted(true, animated: true)
        updateFloatingView(atTouchBarPoint: point)
        updatePlaceholderGap(
            sourceItemID: source?.reorderID ?? UUID(),
            insertionIndex: source?.reorderID == nil ? nil : sourceIndex,
            dragCenterX: point.x,
            in: parent,
            animated: true
        )
        let parentID = currentMode.hasPrefix("stack:") ? String(currentMode.dropFirst(6)) : "root"
        log(
            "internal drag begin | input=\(input) source id=\(source?.reorderID?.uuidString ?? "nil") "
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
        in parent: NSView,
        animatedGap: Bool = true
    ) -> Int? {
        restoreReorderScrollLockIfNeeded()
        let dragPoint = clampedInternalDragPoint(touchPoint, in: parent)
        internalDragLastPoint = dragPoint
        internalDragLastRawTouchBarPoint = touchPoint
        internalDragLastContentSpaceX = contentSpaceX(for: dragPoint, in: parent)
        internalDragIsOutsideCommitBounds = isOutsideCommitBounds(touchPoint, in: parent)
        updateFloatingView(atTouchBarPoint: dragPoint)
        updateDragAutoScroll(rawTouchBarPoint: touchPoint, clampedTouchBarPoint: dragPoint, in: parent)
        guard !internalDragIsOutsideCommitBounds else {
            clearDirectTouchDropTarget()
            resetPlaceholderGaps(animated: true)
            hideInsertionIndicator(animated: true)
            log("internal drag paused outside commit bounds | source item id=\(sourceItemID)")
            return nil
        }
        let classification = classifyDrop(
            sourceItemID: sourceItemID,
            atTouchBarPoint: dragPoint,
            in: parent
        )
        let insertion: Int?
        switch classification {
        case .stack:
            insertion = stableInsertionIndex(atTouchBarPoint: dragPoint, in: parent)
        case let .insert(index):
            insertion = index
        case .none:
            insertion = nil
        }
        let insertionChanged = lastGapSourceItemID != sourceItemID
            || lastGapInsertionIndex != insertion
        if insertionChanged {
            lastGapSourceItemID = sourceItemID
            lastGapInsertionIndex = insertion
        }
        internalDragLastInsertionIndex = insertion
        updatePlaceholderGap(
            sourceItemID: sourceItemID,
            insertionIndex: insertion,
            dragCenterX: dragPoint.x,
            in: parent,
            animated: animatedGap
        )
        updateInsertionIndicator(
            sourceItemID: sourceItemID,
            insertionIndex: insertion,
            in: parent
        )
        if let insertion, insertionChanged {
            log(
                "internal drag update | source item id=\(sourceItemID) "
                    + "insertion index=\(insertion) "
                    + "contentX=\(String(format: "%.2f", internalDragLastContentSpaceX))"
            )
        }
        return insertion
    }

    fileprivate func endInternalDrag(cancelled: Bool) {
        stopDragAutoScroll()
        let floating = internalFloatingView
        let sourceView = internalDragSourceView
        let sourceFrame = internalDragSourceFrame
        internalFloatingView = nil
        internalDragSourceView = nil
        internalDragSourceID = nil
        internalDragSourceFrame = .zero
        internalDragLastPoint = .zero
        internalDragLastRawTouchBarPoint = nil
        internalDragLastContentSpaceX = 0
        internalDragLastInsertionIndex = nil
        internalDragIsOutsideCommitBounds = false
        releaseReorderScrollLock()
        let finish = {
            floating?.removeFromSuperview()
            sourceView?.resetTransientInteractionState()
            if cancelled {
                sourceView?.animateDragOutCancelled()
            }
        }
        resetPlaceholderGaps(animated: true)
        hideInsertionIndicator(animated: true)
        lastGapSourceItemID = nil
        lastGapInsertionIndex = nil
        guard let floating else {
            finish()
            log("internal drag end | cancelled=\(cancelled)")
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = cancelled ? 0.16 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if cancelled, !sourceFrame.isEmpty {
                floating.animator().frame = sourceFrame
            }
            floating.animator().alphaValue = 0
        } completionHandler: {
            finish()
        }
        log("internal drag end | cancelled=\(cancelled)")
    }

    @discardableResult
    func beginDirectTouchDrag(
        sourceView: ShelfScrubberItemView,
        itemID: UUID,
        at point: NSPoint,
        in parent: NSView
    ) -> Bool {
        if let existing = directTouchSourceItemID, existing != itemID {
            log("Touch Bar finger drag stale source cleared | existing=\(existing) next=\(itemID)")
            endInternalDrag(cancelled: true)
            clearDirectTouchDropTarget()
            directTouchSourceItemID = nil
            directTouchInsertionIndex = nil
        }
        guard directTouchSourceItemID == nil,
              sourceView.allowsInternalReorder,
              sourceView.representedItem?.id == itemID || sourceView.representedStackID == itemID
        else { return false }
        directTouchSourceItemID = itemID
        directTouchInsertionIndex = nil
        clearDirectTouchDropTarget()
        let hit = ShelfBridgeHit(
            id: sourceView.representedStackID == itemID ? "stack:\(itemID)" : "shelf:\(itemID)",
            item: sourceView.representedItem,
            stackID: sourceView.representedStackID,
            view: sourceView,
            allowsReorder: sourceView.allowsInternalReorder
        )
        beginInternalDrag(
            source: hit,
            atTouchBarPoint: point,
            in: parent,
            input: "physicalTouch"
        )
        log("Touch Bar finger drag begin | source item id=\(itemID)")
        return true
    }

    func updateDirectTouchDrag(itemID: UUID, at point: NSPoint, in parent: NSView) {
        guard directTouchSourceItemID == itemID else { return }
        directTouchInsertionIndex = updateInternalDrag(
            sourceItemID: itemID,
            atTouchBarPoint: point,
            in: parent
        )
        if directTouchDropTargetSourceIsFile,
           case let .stack(hit) = classifyDrop(
            sourceItemID: itemID,
            atTouchBarPoint: point,
            in: parent
           ) {
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
        guard directTouchSourceItemID == itemID else {
            if directTouchSourceItemID != nil {
                log("Touch Bar finger drag mismatch reset | ended=\(itemID) active=\(directTouchSourceItemID?.uuidString ?? "nil")")
                endInternalDrag(cancelled: true)
                clearDirectTouchDropTarget()
                directTouchSourceItemID = nil
                directTouchInsertionIndex = nil
                hideInsertionIndicator(animated: false)
                resetPlaceholderGaps(animated: false)
                gestureDidEnd()
            }
            return
        }
        if !cancelled {
            updateDirectTouchDrag(itemID: itemID, at: point, in: parent)
        }
        let target = directTouchDropTarget
        let targetIsReady = target != nil
            && ProcessInfo.processInfo.systemUptime - (directTouchDropTargetSince ?? .infinity)
                >= (target?.stackID == nil ? Self.createStackHoverDelay : Self.addToStackHoverDelay)
        let committed = commitInternalDrag(
            itemID: itemID,
            target: target,
            targetIsReady: targetIsReady,
            insertionIndex: directTouchInsertionIndex,
            cancelled: cancelled || internalDragIsOutsideCommitBounds,
            source: "physicalTouch"
        )
        endInternalDrag(cancelled: cancelled || internalDragIsOutsideCommitBounds)
        clearDirectTouchDropTarget()
        directTouchSourceItemID = nil
        directTouchInsertionIndex = nil
        log("Touch Bar finger drag end | source item id=\(itemID) cancelled=\(cancelled) committed=\(committed)")
        gestureDidEnd()
    }

    @discardableResult
    fileprivate func commitInternalDrag(
        itemID: UUID,
        target: ShelfBridgeHit?,
        targetIsReady: Bool,
        insertionIndex: Int?,
        cancelled: Bool,
        source: String
    ) -> Bool {
        guard !cancelled else {
            log("\(source) commit skipped | reason=cancelled item id=\(itemID)")
            return false
        }
        if targetIsReady, let target {
            if let stackID = target.stackID {
                didDrop(itemID: itemID, ontoStack: stackID)
                log("\(source) commit drop-to-stack | item id=\(itemID) stack id=\(stackID)")
                return true
            }
            if let targetItemID = target.item?.id {
                didMerge(sourceItemID: itemID, targetItemID: targetItemID)
                log("\(source) commit merge-to-item | item id=\(itemID) target id=\(targetItemID)")
                return true
            }
        }
        if let insertionIndex {
            didReorder(itemID: itemID, to: insertionIndex)
            log("\(source) commit reorder | item id=\(itemID) insertion index=\(insertionIndex)")
            return true
        }
        log("\(source) commit skipped | reason=no target or insertion item id=\(itemID)")
        return false
    }

    private var directTouchDropTargetSourceIsFile: Bool {
        guard let id = directTouchSourceItemID,
              let sourceView = internalDragSourceView
        else { return false }
        return sourceView.representedItem?.id == id
    }

    private func updateDirectTouchDropTarget(_ target: ShelfBridgeHit) {
        guard target.id != directTouchDropTarget?.id else { return }
        clearDirectTouchDropTarget()
        directTouchDropTarget = target
        directTouchDropTargetSince = ProcessInfo.processInfo.systemUptime
        let delay = target.stackID == nil ? Self.createStackHoverDelay : Self.addToStackHoverDelay
        log("Touch Bar finger dwell target=\(target.id) stackReady timer=\(delay)s")
        let work = DispatchWorkItem { [weak self, weak targetView = target.view] in
            guard let self, self.directTouchDropTarget?.id == target.id else { return }
            (targetView as? ShelfScrubberItemView)?.setStackDropTargetHighlighted(true)
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

    private func classifyDrop(
        sourceItemID: UUID,
        atTouchBarPoint point: NSPoint,
        in parent: NSView
    ) -> ShelfInternalDropClassification {
        if let hit = delegate?.shelfMouseBridgeHit(atTouchBarPoint: point, in: parent),
           hit.item?.id != sourceItemID,
           (hit.item != nil || hit.stackID != nil),
           delegate?.shelfMouseBridgeCanDrop(sourceItemID: sourceItemID, onto: hit) == true,
           isInStackCenterZone(point: point, hit: hit, parent: parent) {
            return .stack(hit)
        }
        return .insert(stableInsertionIndex(atTouchBarPoint: point, in: parent))
    }

    private func isInStackCenterZone(
        point: NSPoint,
        hit: ShelfBridgeHit,
        parent: NSView
    ) -> Bool {
        let frame = hit.view.superview?.convert(hit.view.frame, to: parent) ?? hit.view.frame
        guard frame.width > 8, frame.contains(point) else { return false }
        let centerWidth = frame.width * Self.stackDropCenterFraction
        let minX = frame.midX - centerWidth / 2
        let maxX = frame.midX + centerWidth / 2
        return point.x >= minX && point.x <= maxX
    }

    private func stableInsertionIndex(
        atTouchBarPoint point: NSPoint,
        in parent: NSView
    ) -> Int? {
        guard let raw = delegate?.shelfMouseBridgeInsertionIndex(
            atTouchBarPoint: point,
            in: parent
        ) else { return nil }
        guard let previous = lastGapInsertionIndex,
              abs(CGFloat(raw - previous)) == 1
        else { return raw }
        let views = allShelfItemViews(in: parent)
            .filter { $0.allowsInternalReorder && ($0.representedItem != nil || $0.representedStackID != nil) }
            .sorted { lhs, rhs in
                let a = lhs.superview?.convert(lhs.frame, to: parent).midX ?? 0
                let b = rhs.superview?.convert(rhs.frame, to: parent).midX ?? 0
                return a < b
            }
        guard views.indices.contains(min(raw, previous)) else { return raw }
        let boundaryView = views[min(raw, previous)]
        let frame = boundaryView.superview?.convert(boundaryView.frame, to: parent) ?? boundaryView.frame
        if abs(point.x - frame.midX) < Self.insertionHysteresis {
            return previous
        }
        return raw
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

    private func clampedInternalDragPoint(_ point: NSPoint, in parent: NSView) -> NSPoint {
        let rect = internalDragContentRect(in: parent)
        let halfWidth = max(internalFloatingView?.frame.width ?? internalDragSourceFrame.width, 1) / 2
        let halfHeight = max(internalFloatingView?.frame.height ?? internalDragSourceFrame.height, 1) / 2
        let minX = rect.minX + halfWidth
        let maxX = rect.maxX - halfWidth
        let x: CGFloat
        if minX <= maxX {
            x = clamp(point.x, min: minX, max: maxX)
        } else {
            x = rect.midX
        }
        let y = clamp(
            point.y,
            min: rect.minY + halfHeight,
            max: rect.maxY - halfHeight
        )
        return NSPoint(x: x, y: y)
    }

    private func isOutsideCommitBounds(_ point: NSPoint, in parent: NSView) -> Bool {
        let rect = internalDragContentRect(in: parent)
        return point.y < rect.minY || point.y > rect.maxY
    }

    private func internalDragContentRect(in parent: NSView) -> NSRect {
        let viewport = shelfContentViewportRect(in: parent)
            ?? parent.bounds.insetBy(dx: 1, dy: 0)
        let reorderableFrames = reorderableShelfItemViews(in: parent)
            .map { $0.superview?.convert($0.frame, to: parent) ?? $0.frame }
            .filter { !$0.isEmpty && $0.intersects(viewport) }
        var contentMinX = viewport.minX
        if let firstReorderableMinX = reorderableFrames.map(\.minX).min() {
            contentMinX = max(contentMinX, firstReorderableMinX - 8)
            let lockedLeftFrames = allShelfItemViews(in: parent)
                .filter { !$0.allowsInternalReorder || $0.isPinDivider }
                .map { $0.superview?.convert($0.frame, to: parent) ?? $0.frame }
                .filter { !$0.isEmpty && $0.intersects(viewport) && $0.midX < firstReorderableMinX }
            if let lockedMaxX = lockedLeftFrames.map(\.maxX).max() {
                contentMinX = max(contentMinX, lockedMaxX + 6)
            }
        }
        let minWidth = max(internalFloatingView?.frame.width ?? internalDragSourceFrame.width, 44)
        let maxX = max(viewport.maxX, contentMinX + minWidth)
        return NSRect(
            x: contentMinX,
            y: viewport.minY,
            width: maxX - contentMinX,
            height: viewport.height
        ).intersection(parent.bounds)
    }

    private func shelfContentViewportRect(in parent: NSView) -> NSRect? {
        if let scrollView = TouchBarHorizontalScrollBridge.descendantScrollView(of: parent) {
            let clipFrame = scrollView.contentView.convert(scrollView.contentView.bounds, to: parent)
            if !clipFrame.isEmpty {
                return clipFrame.intersection(parent.bounds)
            }
            let frame = scrollView.superview?.convert(scrollView.frame, to: parent) ?? scrollView.frame
            if !frame.isEmpty {
                return frame.intersection(parent.bounds)
            }
        }
        return nil
    }

    private func updateDragAutoScroll(
        rawTouchBarPoint rawPoint: NSPoint,
        clampedTouchBarPoint point: NSPoint,
        in parent: NSView
    ) {
        let rect = internalDragContentRect(in: parent)
        guard rawPoint.y >= rect.minY, rawPoint.y <= rect.maxY else {
            stopDragAutoScroll()
            return
        }
        let zone = min(Self.dragEdgeAutoScrollZone, max(rect.width / 3, 1))
        let leftDistance = max(rawPoint.x - rect.minX, 0)
        let rightDistance = max(rect.maxX - rawPoint.x, 0)
        let leftPressure = clamp((zone - leftDistance) / zone, min: 0, max: 1)
        let rightPressure = clamp((zone - rightDistance) / zone, min: 0, max: 1)
        let delta = Self.dragEdgeAutoScrollMaxStep
            * (smoothstep(rightPressure) - smoothstep(leftPressure))
        guard abs(delta) > 0.03 else {
            stopDragAutoScroll()
            return
        }
        dragAutoScrollDeltaX = delta
        if dragAutoScrollWorkItem != nil { return }
        scheduleNextDragAutoScrollTick()
    }

    private func scheduleNextDragAutoScrollTick() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dragAutoScrollWorkItem = nil
            guard self.internalFloatingView != nil,
                  abs(self.dragAutoScrollDeltaX) > 0.03
            else {
                self.stopDragAutoScroll()
                return
            }
            self.handleScroll(
                deltaX: self.dragAutoScrollDeltaX,
                deltaY: 0,
                inverted: false,
                source: "dragEdgeAutoScroll"
            )
            if let sourceID = self.internalDragSourceID,
               let parent = self.physicalTouchBarView {
                _ = self.updateInternalDrag(
                    sourceItemID: sourceID,
                    atTouchBarPoint: self.internalDragLastRawTouchBarPoint ?? self.internalDragLastPoint,
                    in: parent,
                    animatedGap: false
                )
            } else {
                self.scheduleNextDragAutoScrollTick()
            }
        }
        dragAutoScrollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / 60.0), execute: work)
    }

    private func stopDragAutoScroll() {
        dragAutoScrollWorkItem?.cancel()
        dragAutoScrollWorkItem = nil
        dragAutoScrollDeltaX = 0
    }

    private func captureReorderScrollLock(in parent: NSView) {
        guard let scrollView = TouchBarHorizontalScrollBridge.descendantScrollView(of: parent) else {
            reorderLockedScrollView = nil
            reorderAllowedScrollOriginX = nil
            return
        }
        reorderLockedScrollView = scrollView
        reorderAllowedScrollOriginX = scrollView.contentView.bounds.origin.x
        log(
            "Reorder scroll lock captured | offset=\(String(format: "%.2f", reorderAllowedScrollOriginX ?? 0))"
        )
    }

    private func restoreReorderScrollLockIfNeeded() {
        guard let scrollView = reorderLockedScrollView,
              let allowed = reorderAllowedScrollOriginX
        else { return }
        var origin = scrollView.contentView.bounds.origin
        guard abs(origin.x - allowed) > 0.5 else { return }
        origin.x = allowed
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        log("Reorder native scroll suppressed | restored offset=\(String(format: "%.2f", allowed))")
    }

    private func updateReorderAllowedScrollOrigin() {
        guard let scrollView = reorderLockedScrollView else { return }
        reorderAllowedScrollOriginX = scrollView.contentView.bounds.origin.x
    }

    private func contentSpaceX(for touchBarPoint: NSPoint, in parent: NSView) -> CGFloat {
        touchBarPoint.x + currentShelfScrollOriginX(in: parent)
    }

    private func currentShelfScrollOriginX(in parent: NSView) -> CGFloat {
        TouchBarHorizontalScrollBridge.descendantScrollView(of: parent)?
            .contentView.bounds.origin.x ?? 0
    }

    private func releaseReorderScrollLock() {
        reorderLockedScrollView = nil
        reorderAllowedScrollOriginX = nil
    }

    private func updatePlaceholderGap(
        sourceItemID: UUID,
        insertionIndex: Int?,
        dragCenterX: CGFloat,
        in parent: NSView,
        animated: Bool
    ) {
        let views = reorderableShelfItemViews(in: parent)
        guard let insertionIndex else {
            internalDragShiftByViewID = [:]
            views.forEach { $0.setInternalDragShift(0, animated: animated) }
            return
        }
        guard let sourceIndex = views.firstIndex(where: {
            ($0.representedItem?.id ?? $0.representedStackID) == sourceItemID
        }) else {
            updatePlaceholderGapWithoutVisibleSource(
                views: views,
                insertionIndex: insertionIndex,
                animated: animated
            )
            return
        }
        let destination = min(max(insertionIndex, 0), views.count)
        let itemWidth = max(internalDragSourceView?.bounds.width ?? 88, 72)
        let gap = min(max(itemWidth * 0.92, 68), itemWidth + 16)
        let pitch = max(estimatedItemPitch(for: views, in: parent), itemWidth + 8)
        var shifts: [ObjectIdentifier: CGFloat] = [:]
        for (index, view) in views.enumerated() {
            var shift: CGFloat = 0
            if destination > sourceIndex + 1, index > sourceIndex && index < destination {
                let frame = view.superview?.convert(view.frame, to: parent) ?? view.frame
                let raw = (dragCenterX - frame.midX + pitch / 2) / pitch
                shift = -gap * smoothstep(clamp(raw, min: 0, max: 1))
            } else if destination <= sourceIndex, index >= destination && index < sourceIndex {
                let frame = view.superview?.convert(view.frame, to: parent) ?? view.frame
                let raw = (frame.midX - dragCenterX + pitch / 2) / pitch
                shift = gap * smoothstep(clamp(raw, min: 0, max: 1))
            }
            shifts[ObjectIdentifier(view)] = shift
            view.setInternalDragShift(shift, animated: animated)
        }
        internalDragShiftByViewID = shifts
    }

    private func updatePlaceholderGapWithoutVisibleSource(
        views: [ShelfScrubberItemView],
        insertionIndex: Int,
        animated: Bool
    ) {
        guard !views.isEmpty else {
            internalDragShiftByViewID = [:]
            return
        }
        let destination = min(max(insertionIndex, 0), views.count)
        let itemWidth = max(internalDragSourceView?.bounds.width ?? 88, 72)
        let gap = min(max(itemWidth * 0.92, 68), itemWidth + 16)
        var shifts: [ObjectIdentifier: CGFloat] = [:]
        for (index, view) in views.enumerated() {
            let shift = index >= destination ? gap : 0
            shifts[ObjectIdentifier(view)] = shift
            view.setInternalDragShift(shift, animated: animated)
        }
        internalDragShiftByViewID = shifts
        log(
            "internal drag gap recomputed without visible source | "
                + "insertion index=\(destination) visible items=\(views.count)"
        )
    }

    private func resetPlaceholderGaps(animated: Bool) {
        guard let parent = physicalTouchBarView else { return }
        internalDragShiftByViewID = [:]
        allShelfItemViews(in: parent).forEach { $0.setInternalDragShift(0, animated: animated) }
    }

    private func updateInsertionIndicator(
        sourceItemID: UUID,
        insertionIndex: Int?,
        in parent: NSView
    ) {
        guard let frame = insertionIndicatorFrame(
            sourceItemID: sourceItemID,
            insertionIndex: insertionIndex,
            in: parent
        ) else {
            hideInsertionIndicator(animated: true)
            return
        }
        let indicator: InsertionIndicatorView
        if let insertionIndicatorView {
            indicator = insertionIndicatorView
        } else {
            indicator = InsertionIndicatorView(frame: frame)
            indicator.layer?.zPosition = 1_100
            parent.addSubview(indicator)
            insertionIndicatorView = indicator
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        indicator.frame = frame
        indicator.updatePath()
        CATransaction.commit()
        if indicator.alphaValue < 0.99 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                indicator.animator().alphaValue = 1
            }
        }
    }

    private func insertionIndicatorFrame(
        sourceItemID: UUID,
        insertionIndex: Int?,
        in parent: NSView
    ) -> NSRect? {
        let views = reorderableShelfItemViews(in: parent)
        guard let insertionIndex, !views.isEmpty else { return nil }
        let destination = min(max(insertionIndex, 0), views.count)
        let sourceView = internalDragSourceView
        let visualViews = views.filter { $0 !== sourceView }
        guard !visualViews.isEmpty else { return nil }
        let visualDestination: Int
        if let sourceView, let sourceIndex = views.firstIndex(where: { $0 === sourceView }) {
            visualDestination = sourceIndex < destination ? destination - 1 : destination
        } else {
            visualDestination = destination
        }
        let frames = visualViews.map { visualFrame(for: $0, in: parent) }
        let itemWidth = max(internalDragSourceView?.bounds.width ?? frames.first?.width ?? 88, 72)
        let placeholderWidth = min(max(itemWidth * 0.92, 68), itemWidth + 16)
        let clampedDestination = min(max(visualDestination, 0), frames.count)
        let x: CGFloat
        if clampedDestination == 0 {
            x = frames[0].minX - placeholderWidth / 2
        } else if clampedDestination >= frames.count {
            x = frames[frames.count - 1].maxX + placeholderWidth / 2
        } else {
            x = (frames[clampedDestination - 1].maxX + frames[clampedDestination].minX) / 2
        }
        let visibleHeight = min(max(parent.bounds.height, 1), Self.virtualTouchBarHeight)
        let height = max(visibleHeight - 6, 22)
        let y = max((parent.bounds.height - height) / 2, 0)
        let halfWidth = placeholderWidth / 2
        let clampedX = min(
            max(x, parent.bounds.minX + halfWidth + 1),
            parent.bounds.maxX - halfWidth - 1
        )
        return NSRect(
            x: clampedX - halfWidth,
            y: y,
            width: placeholderWidth,
            height: height
        )
    }

    private func hideInsertionIndicator(animated: Bool) {
        guard let indicator = insertionIndicatorView else { return }
        insertionIndicatorView = nil
        let remove = { indicator.removeFromSuperview() }
        guard animated else {
            remove()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            indicator.animator().alphaValue = 0
        } completionHandler: {
            remove()
        }
    }

    private func allShelfItemViews(in view: NSView) -> [ShelfScrubberItemView] {
        var result: [ShelfScrubberItemView] = []
        if let item = view as? ShelfScrubberItemView { result.append(item) }
        for child in view.subviews {
            result.append(contentsOf: allShelfItemViews(in: child))
        }
        return result
    }

    private func reorderableShelfItemViews(in view: NSView) -> [ShelfScrubberItemView] {
        allShelfItemViews(in: view)
            .filter { $0.allowsInternalReorder && ($0.representedItem != nil || $0.representedStackID != nil) }
            .sorted { lhs, rhs in
                let a = lhs.superview?.convert(lhs.frame, to: view).midX ?? 0
                let b = rhs.superview?.convert(rhs.frame, to: view).midX ?? 0
                return a < b
            }
    }

    private func visualFrame(for itemView: ShelfScrubberItemView, in parent: NSView) -> NSRect {
        var frame = itemView.superview?.convert(itemView.frame, to: parent) ?? itemView.frame
        frame.origin.x += internalDragShiftByViewID[ObjectIdentifier(itemView)] ?? 0
        return frame
    }

    private func estimatedItemPitch(for views: [ShelfScrubberItemView], in parent: NSView) -> CGFloat {
        let centers = views
            .map { ($0.superview?.convert($0.frame, to: parent) ?? $0.frame).midX }
            .sorted()
        guard centers.count > 1 else {
            return max(internalDragSourceView?.bounds.width ?? 88, 72) + 8
        }
        var total: CGFloat = 0
        for index in 1..<centers.count {
            total += centers[index] - centers[index - 1]
        }
        return max(total / CGFloat(centers.count - 1), 1)
    }

    private func smoothstep(_ value: CGFloat) -> CGFloat {
        let x = clamp(value, min: 0, max: 1)
        return x * x * (3 - 2 * x)
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
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

    private func attachToPhysicalTouchBar(reason: String, attempt: Int) {
        guard isPresentationRequested else { return }
        if bridgeView?.hasActiveGesture == true || isDirectTouchDragging {
            scheduleReadyAttach(delay: 0.07, nextAttempt: attempt + 1)
            logBridgeState(reason: "rebuildDeferredForActiveGesture")
            return
        }
        guard let parent = NSFunctionRow._topLevelViews().last,
              parent.visibleRect.width > 100
        else {
            log(
                "BugFix18 attach deferred | reason=\(reason) attempt=\(attempt) "
                    + "cause=no physical Touch Bar view"
            )
            deferReadyAttachIfPossible(attempt: attempt)
            return
        }
        parent.layoutSubtreeIfNeeded()
        let diagnostic = delegate?.shelfMouseBridgeAttachDiagnosticContext(
            in: parent,
            mode: currentMode
        ) ?? "attach diagnostic unavailable"
        let elapsed = readyAttachStartedAt.map {
            String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - $0) * 1000)
        } ?? "n/a"
        log(
            "BugFix18 attach probe | reason=\(reason) attempt=\(attempt) "
                + "elapsedMs=\(elapsed) topWindow=\(parent.window != nil) "
                + "topVisible=\(parent.visibleRect) \(diagnostic)"
        )
        guard delegate?.shelfMouseBridgeCanAttach(in: parent, mode: currentMode) != false else {
            log("BugFix18 attach deferred | reason=\(reason) attempt=\(attempt) cause=layout-not-ready")
            deferReadyAttachIfPossible(attempt: attempt)
            return
        }
        if physicalTouchBarView !== parent {
            cursorView?.removeFromSuperview()
            cursorView = nil
            clearHover()
            physicalTouchBarView = parent
            log("Shelf MouseBridge rebound to current Touch Bar view")
        }
        bridgeWidth = parent.visibleRect.width
        if panel == nil {
            createPanel()
        } else {
            updatePanelFrame()
            panel?.orderFrontRegardless()
        }
        lastRebuildTime = Date()
        let names = delegate?.shelfMouseBridgeRegisteredHitRegionNames(in: parent) ?? []
        lastHitRegionCount = names.count
        log("Registered hit regions:\n" + names.map { "- \($0)" }.joined(separator: "\n"))
        log(
            "BugFix18 attach ready | reason=\(reason) attempt=\(attempt) "
                + "bridgeTrackingAreas=\(bridgeView?.trackingAreas.count ?? 0)"
        )
        logBridgeState(reason: "hitRegionsRebuilt", hitRegionCount: names.count)
        if isPointerInsideBridge, let point = currentPanelPoint {
            pointerMoved(toPanelPoint: point)
        }
    }

    private func scheduleHitRegionRebuild(delay: TimeInterval, allowCoexisting: Bool = false) {
        if allowCoexisting {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.attachToPhysicalTouchBar(
                    reason: self.pendingReadyAttachReason,
                    attempt: self.readyAttachAttempt
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return
        }
        scheduleReadyAttach(delay: delay)
    }

    private func scheduleReadyAttach(delay: TimeInterval, nextAttempt: Int? = nil) {
        rebuildWorkItem?.cancel()
        if let nextAttempt {
            readyAttachAttempt = nextAttempt
        }
        let attempt = readyAttachAttempt
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rebuildWorkItem = nil
            self.attachToPhysicalTouchBar(
                reason: self.pendingReadyAttachReason,
                attempt: attempt
            )
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func deferReadyAttachIfPossible(attempt: Int) {
        guard attempt < Self.maxReadyAttachAttempts else {
            log(
                "BugFix18 attach failed | reason=\(pendingReadyAttachReason) "
                    + "attempts=\(attempt + 1) cause=ready-condition-timeout"
            )
            return
        }
        scheduleReadyAttach(
            delay: Self.readyAttachRetryDelay,
            nextAttempt: attempt + 1
        )
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
                + "bridge width=\(String(format: "%.1f", bridgeWidth)) "
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

    private func recursiveTrackingAreaCount(in view: NSView) -> Int {
        view.trackingAreas.count + view.subviews.reduce(0) { partial, subview in
            partial + recursiveTrackingAreaCount(in: subview)
        }
    }
}
