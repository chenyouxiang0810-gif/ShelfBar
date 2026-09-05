import AppKit

@MainActor
enum TouchBarHorizontalScrollBridge {
    @discardableResult
    static func scrollFirstStrip(
        in parent: NSView,
        deltaX: CGFloat,
        deltaY: CGFloat,
        inverted: Bool,
        logPrefix: String,
        logHandler: (String) -> Void
    ) -> CGFloat? {
        guard let scrollView = descendantScrollView(of: parent),
              let documentView = scrollView.documentView
        else {
            logHandler("\(logPrefix) scroll unavailable")
            return nil
        }
        return scroll(
            scrollView,
            documentView: documentView,
            deltaX: deltaX,
            deltaY: deltaY,
            inverted: inverted,
            logPrefix: logPrefix,
            logHandler: logHandler
        )
    }

    @discardableResult
    static func scroll(
        _ scrollView: NSScrollView,
        documentView: NSView,
        deltaX: CGFloat,
        deltaY: CGFloat,
        inverted: Bool,
        logPrefix: String,
        logHandler: (String) -> Void
    ) -> CGFloat {
        let rawDelta = abs(deltaX) > 0.01 ? deltaX : deltaY
        let contentDelta = inverted ? -rawDelta : rawDelta
        let maximum = max(documentView.bounds.width - scrollView.contentView.bounds.width, 0)
        var origin = scrollView.contentView.bounds.origin
        origin.x = min(max(origin.x + contentDelta, 0), maximum)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        logHandler(
            "\(logPrefix) scroll offset=\(String(format: "%.2f", origin.x)) "
                + "delta=\(String(format: "%.2f", contentDelta)) "
                + "viewport=\(String(format: "%.1f", scrollView.contentView.bounds.width)) "
                + "document=\(String(format: "%.1f", documentView.bounds.width))"
        )
        return origin.x
    }

    static func descendantScrollView(of view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let result = descendantScrollView(of: subview) { return result }
        }
        return nil
    }
}

@MainActor
final class ActionMenuMouseBridgeController: NSObject {
    fileprivate struct HitRegion {
        let id: String
        let frame: NSRect
        let button: NSButton
    }

    private final class BridgePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class BridgeView: NSView {
        weak var bridge: ActionMenuMouseBridgeController?
        private var trackingAreaReference: NSTrackingArea?
        private weak var pressedButton: NSButton?
        private var mouseDownPoint: NSPoint?
        private var lastScrollDragPoint: NSPoint?
        private var didScrollDrag = false

        var hasActiveGesture: Bool {
            pressedButton != nil || mouseDownPoint != nil || didScrollDrag
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
            bridge?.pointerExited()
        }

        override func scrollWheel(with event: NSEvent) {
            let horizontal = event.scrollingDeltaX
            let shiftedVertical = event.modifierFlags.contains(.shift)
                ? event.scrollingDeltaY
                : 0
            guard abs(horizontal) > 0.01 || abs(shiftedVertical) > 0.01 else { return }
            bridge?.scrollActionStrip(
                deltaX: horizontal,
                deltaY: shiftedVertical,
                inverted: event.isDirectionInvertedFromDevice
            )
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = event.locationInWindow
            lastScrollDragPoint = nil
            didScrollDrag = false
            pressedButton = bridge?.hit(atPanelPoint: event.locationInWindow)?.button
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownPoint else { return }
            let previous = lastScrollDragPoint ?? start
            let totalDistance = hypot(
                event.locationInWindow.x - start.x,
                event.locationInWindow.y - start.y
            )
            guard totalDistance >= 5 else { return }
            didScrollDrag = true
            lastScrollDragPoint = event.locationInWindow
            bridge?.scrollActionStrip(
                deltaX: -(event.locationInWindow.x - previous.x),
                deltaY: -(event.locationInWindow.y - previous.y),
                inverted: false
            )
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                pressedButton = nil
                mouseDownPoint = nil
                lastScrollDragPoint = nil
                didScrollDrag = false
            }
            guard !didScrollDrag else { return }
            if let pressedButton,
               pressedButton.window != nil,
               !pressedButton.isHidden,
               pressedButton.alphaValue > 0.01,
               pressedButton.isEnabled {
                bridge?.click(pressedButton)
                return
            }
            if let released = bridge?.hit(atPanelPoint: event.locationInWindow)?.button {
                bridge?.click(released)
            }
        }

        func resetInteractionState() {
            pressedButton = nil
            mouseDownPoint = nil
            lastScrollDragPoint = nil
            didScrollDrag = false
        }
    }

    private static let virtualTouchBarHeight: CGFloat = 40
    private static let enterThreshold: CGFloat = 5
    private static let exitThreshold: CGFloat = 12
    private let logHandler: (String) -> Void
    private weak var physicalTouchBarView: NSView?
    private weak var cursorView: NSImageView?
    private weak var hoveredButton: NSButton?
    private var panel: BridgePanel?
    private var bridgeView: BridgeView?
    private var bridgeWidth: CGFloat = 1085
    private var heightInPixels = 5
    private var isPointerInsideBridge = false
    private var attachWorkItem: DispatchWorkItem?
    private var rebuildWorkItem: DispatchWorkItem?
    private var hitRegions: [HitRegion] = []
    private(set) var virtualTouchBarRect = NSRect.zero

    fileprivate var currentPanelPoint: NSPoint? {
        guard let panel else { return nil }
        return panel.convertPoint(fromScreen: NSEvent.mouseLocation)
    }

    init(logHandler: @escaping (String) -> Void) {
        self.logHandler = logHandler
        super.init()
    }

    func present() {
        if panel != nil {
            panel?.orderFrontRegardless()
            updatePanelFrame()
            scheduleHitRegionRebuild(delay: 0.0, allowCoexisting: true)
            scheduleHitRegionRebuild(delay: 0.03)
            scheduleHitRegionRebuild(delay: 0.14, allowCoexisting: true)
            scheduleHitRegionRebuild(delay: 0.30, allowCoexisting: true)
            return
        }
        attachWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.attachToActionMenu()
        }
        attachWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
        let retry = DispatchWorkItem { [weak self] in
            guard self?.panel == nil else {
                self?.scheduleHitRegionRebuild(delay: 0.03)
                self?.scheduleHitRegionRebuild(delay: 0.18, allowCoexisting: true)
                return
            }
            self?.attachToActionMenu()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: retry)
    }

    func dismiss() {
        attachWorkItem?.cancel()
        attachWorkItem = nil
        rebuildWorkItem?.cancel()
        rebuildWorkItem = nil
        bridgeView?.resetInteractionState()
        hitRegions.removeAll()
        panel?.orderOut(nil)
        panel = nil
        bridgeView = nil
        pointerExited()
        physicalTouchBarView = nil
    }

    func resetTransientInteractionState(reason: String) {
        bridgeView?.resetInteractionState()
        pointerExited()
        logHandler("Action menu transient reset | reason=\(reason)")
    }

    func debugStateSummary(parentView: NSView? = nil) -> String {
        let root = parentView ?? physicalTouchBarView
        let bridgeTrackingCount = bridgeView?.trackingAreas.count ?? 0
        let touchBarTrackingCount = root.map { recursiveTrackingAreaCount(in: $0) } ?? 0
        return "ActionBridge panel=\(panel != nil ? 1 : 0) bridgeView=\(bridgeView != nil ? 1 : 0) "
            + "bridgeTrackingAreas=\(bridgeTrackingCount) touchBarTrackingAreas=\(touchBarTrackingCount) "
            + "hitRegions=\(hitRegions.count) pointerInside=\(isPointerInsideBridge) "
            + "activeGesture=\(bridgeView?.hasActiveGesture == true)"
    }

    func isGestureNeutralForDebug() -> Bool {
        bridgeView?.hasActiveGesture != true
    }

    func setHeightInPixels(_ pixels: Int) {
        heightInPixels = max(pixels, 2)
        updatePanelFrame()
    }

    fileprivate func pointerEntered() {
        guard !isPointerInsideBridge else { return }
        isPointerInsideBridge = true
        updatePanelFrame()
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
        let nextButton = hit(atPanelPoint: panelPoint)?.button
        guard nextButton !== hoveredButton else { return }
        hoveredButton?.isHighlighted = false
        hoveredButton = nextButton
        hoveredButton?.isHighlighted = true
        logHandler("Action menu hover=\(nextButton?.title ?? "none")")
    }

    fileprivate func pointerExited() {
        let wasInside = isPointerInsideBridge
        isPointerInsideBridge = false
        cursorView?.removeFromSuperview()
        cursorView = nil
        hoveredButton?.isHighlighted = false
        hoveredButton = nil
        if wasInside {
            updatePanelFrame()
        }
    }

    fileprivate func hit(atPanelPoint panelPoint: NSPoint) -> HitRegion? {
        guard let parent = physicalTouchBarView,
              virtualTouchBarRect.contains(panelPoint)
        else { return nil }
        let point = touchBarPoint(from: panelPoint, in: parent)
        if let liveButton = liveButton(at: point, in: parent) {
            let frame = liveButton.superview?.convert(liveButton.frame, to: parent) ?? .zero
            return HitRegion(id: liveButton.title.uppercased(), frame: frame, button: liveButton)
        }
        return hitRegions.first { region in
            guard region.button.window != nil,
                  !region.button.isHidden,
                  region.button.isEnabled
            else { return false }
            let currentFrame = region.button.superview?.convert(region.button.frame, to: parent)
                ?? region.frame
            return currentFrame.contains(point)
        }
    }

    fileprivate func click(_ button: NSButton) {
        logHandler("Action menu click=\(button.title)")
        button.performClick(nil)
    }

    fileprivate func scrollActionStrip(deltaX: CGFloat, deltaY: CGFloat, inverted: Bool) {
        guard let parent = physicalTouchBarView else { return }
        _ = TouchBarHorizontalScrollBridge.scrollFirstStrip(
            in: parent,
            deltaX: deltaX,
            deltaY: deltaY,
            inverted: inverted,
            logPrefix: "Action menu",
            logHandler: logHandler
        )
        scheduleHitRegionRebuild(delay: 0.03)
        scheduleHitRegionRebuild(delay: 0.16, allowCoexisting: true)
    }

    private func attachToActionMenu() {
        guard let parent = NSFunctionRow._topLevelViews().last,
              parent.visibleRect.width > 100
        else {
            logHandler("Action menu MouseBridge unavailable: no physical Touch Bar view")
            return
        }
        if physicalTouchBarView !== parent {
            pointerExited()
            physicalTouchBarView = parent
            logHandler("Action menu MouseBridge rebound to current Touch Bar view")
        }
        parent.layoutSubtreeIfNeeded()
        bridgeWidth = parent.visibleRect.width
        createPanel()
        scheduleHitRegionRebuild()
    }

    private func createPanel() {
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

    private func scheduleHitRegionRebuild(delay: TimeInterval = 0.08, allowCoexisting: Bool = false) {
        if !allowCoexisting {
            rebuildWorkItem?.cancel()
        }
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildHitRegions()
        }
        if !allowCoexisting {
            rebuildWorkItem = work
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func rebuildHitRegions() {
        rebuildWorkItem = nil
        guard let parent = physicalTouchBarView else { return }
        hitRegions = descendantButtons(of: parent).compactMap { button in
            guard !button.isHidden,
                  button.alphaValue > 0.01,
                  button.isEnabled,
                  button.action != nil,
                  let superview = button.superview
            else { return nil }
            let frame = superview.convert(button.frame, to: parent)
            guard frame.width > 0, frame.height > 0, frame.intersects(parent.bounds) else {
                return nil
            }
            return HitRegion(id: button.title.uppercased(), frame: frame, button: button)
        }
        logHandler("Action menu hitRegions=\(hitRegions.count)")

        if hitRegions.isEmpty {
            let retry = DispatchWorkItem { [weak self] in self?.rebuildHitRegions() }
            rebuildWorkItem = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: retry)
        } else if isPointerInsideBridge, let point = currentPanelPoint {
            pointerMoved(toPanelPoint: point)
        }
    }

    private func liveButton(at point: NSPoint, in parent: NSView) -> NSButton? {
        var candidate = parent.hitTest(point)
        while let view = candidate, view !== parent {
            if let button = view as? NSButton,
               button.isEnabled,
               !button.isHidden,
               button.alphaValue > 0.01,
               button.action != nil {
                return button
            }
            candidate = view.superview
        }
        return nil
    }

    private func descendantButtons(of view: NSView) -> [NSButton] {
        view.subviews.flatMap { subview in
            var buttons = (subview as? NSButton).map { [$0] } ?? []
            buttons.append(contentsOf: descendantButtons(of: subview))
            return buttons
        }
    }

    private func updatePanelFrame() {
        guard let panel, let screen = NSScreen.main else { return }
        let scale = max(screen.backingScaleFactor, 1)
        let enterHeight = max(CGFloat(heightInPixels) / scale, Self.enterThreshold)
        let horizontalMargin = isPointerInsideBridge ? Self.exitThreshold : 0
        let height = isPointerInsideBridge
            ? Self.virtualTouchBarHeight + Self.exitThreshold
            : enterHeight
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

    private func recursiveTrackingAreaCount(in view: NSView) -> Int {
        view.trackingAreas.count + view.subviews.reduce(0) { partial, subview in
            partial + recursiveTrackingAreaCount(in: subview)
        }
    }
}
