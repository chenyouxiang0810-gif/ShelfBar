import AppKit

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

        override func mouseDown(with event: NSEvent) {
            pressedButton = bridge?.hit(atPanelPoint: event.locationInWindow)?.button
        }

        override func mouseUp(with event: NSEvent) {
            defer { pressedButton = nil }
            guard let pressedButton,
                  bridge?.hit(atPanelPoint: event.locationInWindow)?.button === pressedButton
            else { return }
            bridge?.click(pressedButton)
        }
    }

    private static let virtualTouchBarHeight: CGFloat = 40
    private static let enterThreshold: CGFloat = 5
    private static let exitThreshold: CGFloat = 12
    private static let actionTitles = Set(["OPEN", "REMOVE", "BACK", "DELETE"])

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
            scheduleHitRegionRebuild()
            return
        }
        attachWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.attachToActionMenu()
        }
        attachWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func dismiss() {
        attachWorkItem?.cancel()
        attachWorkItem = nil
        rebuildWorkItem?.cancel()
        rebuildWorkItem = nil
        hitRegions.removeAll()
        panel?.orderOut(nil)
        panel = nil
        bridgeView = nil
        pointerExited()
        physicalTouchBarView = nil
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
        return hitRegions.first { $0.frame.contains(point) }
    }

    fileprivate func click(_ button: NSButton) {
        logHandler("Action menu click=\(button.title)")
        button.performClick(nil)
    }

    private func attachToActionMenu() {
        guard let parent = NSFunctionRow._topLevelViews().last,
              parent.visibleRect.width > 100
        else {
            logHandler("Action menu MouseBridge unavailable: no physical Touch Bar view")
            return
        }
        physicalTouchBarView = parent
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

    private func scheduleHitRegionRebuild() {
        rebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildHitRegions()
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func rebuildHitRegions() {
        rebuildWorkItem = nil
        guard let parent = physicalTouchBarView else { return }
        hitRegions = descendantButtons(of: parent).compactMap { button in
            guard Self.actionTitles.contains(button.title.uppercased()),
                  !button.isHidden,
                  button.alphaValue > 0.01,
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
}
