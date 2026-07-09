import AppKit

@MainActor
final class FloatingShelfButtonController: NSObject {
    private static let positionXKey = "ShelfBar.floatingButton.positionX"
    private static let positionYKey = "ShelfBar.floatingButton.positionY"

    private final class FloatingPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class FloatingButtonView: NSView {
        weak var owner: FloatingShelfButtonController?
        private var mouseDownScreenPoint: NSPoint?
        private var panelStartOrigin: NSPoint?
        private var didDrag = false
        private var trackingAreaReference: NSTrackingArea?
        private var isHovering = false
        private var isPressed = false
        private var isLaunching = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let radius: CGFloat = 28
            let distance = hypot(point.x - bounds.midX, point.y - bounds.midY)
            return distance <= radius ? self : nil
        }

        override func layout() {
            super.layout()
            wantsLayer = true
            layer?.shadowPath = CGPath(
                ellipseIn: NSRect(x: bounds.midX - 30, y: bounds.midY - 30, width: 60, height: 60),
                transform: nil
            )
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaReference {
                removeTrackingArea(trackingAreaReference)
            }
            let tracking = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(tracking)
            trackingAreaReference = tracking
        }

        override func mouseEntered(with event: NSEvent) {
            isHovering = true
            updateInteractionAppearance()
        }

        override func mouseExited(with event: NSEvent) {
            isHovering = false
            updateInteractionAppearance()
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownScreenPoint = NSEvent.mouseLocation
            panelStartOrigin = window?.frame.origin
            didDrag = false
            isPressed = true
            updateInteractionAppearance()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownScreenPoint,
                  let origin = panelStartOrigin,
                  let window
            else { return }
            let current = NSEvent.mouseLocation
            let delta = NSPoint(x: current.x - start.x, y: current.y - start.y)
            if hypot(delta.x, delta.y) >= 4 {
                didDrag = true
            }
            window.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
        }

        override func mouseUp(with event: NSEvent) {
            isPressed = false
            updateInteractionAppearance()
            if didDrag {
                owner?.saveCurrentPosition()
            } else {
                owner?.presentShelf()
            }
            mouseDownScreenPoint = nil
            panelStartOrigin = nil
            didDrag = false
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let owner else { return }
            NSMenu.popUpContextMenu(owner.contextMenu, with: event, for: self)
        }

        private func updateInteractionAppearance() {
            wantsLayer = true
            let scale: CGFloat = isPressed ? 0.96 : (isHovering ? 1.05 : 1)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                animator().alphaValue = isPressed ? 0.82 : 0.96
                layer?.shadowOpacity = isLaunching ? 0.42 : 0.24
                layer?.shadowRadius = isLaunching ? 18 : 8
                layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        func setLaunching(_ launching: Bool) {
            isLaunching = launching
            updateInteractionAppearance()
        }
    }

    private let panel: FloatingPanel
    private weak var buttonView: FloatingButtonView?
    fileprivate let contextMenu = NSMenu(title: "ShelfBar")
    var onPresentShelf: (() -> Void)?
    var onShowApp: (() -> Void)?

    override init() {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let button = FloatingButtonView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
        button.owner = self
        button.alphaValue = 0.96
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.shadowColor = NSColor.black.cgColor
        button.layer?.shadowOpacity = 0.24
        button.layer?.shadowRadius = 8
        button.layer?.shadowOffset = NSSize(width: 0, height: -2)
        self.buttonView = button

        let glass = NSVisualEffectView(frame: NSRect(x: 20, y: 20, width: 56, height: 56))
        glass.material = .hudWindow
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 28
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        button.addSubview(glass)

        let imageView = NSImageView(frame: NSRect(x: 7, y: 7, width: 42, height: 42))
        imageView.image = TouchBarDropButton.drawerImage()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .controlAccentColor
        imageView.isEditable = false
        imageView.unregisterDraggedTypes()
        glass.addSubview(imageView)

        panel.contentView = button
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        contextMenu.addItem(
            withTitle: "Show App",
            action: #selector(showApp),
            keyEquivalent: ""
        ).target = self
        contextMenu.addItem(
            withTitle: "Hide Button",
            action: #selector(hideFromMenu),
            keyEquivalent: ""
        ).target = self
        contextMenu.addItem(.separator())
        contextMenu.addItem(
            withTitle: "Quit ShelfBar",
            action: #selector(quitShelfBar),
            keyEquivalent: ""
        ).target = self

        restorePosition()
    }

    func show() {
        restorePosition()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    fileprivate func presentShelf() {
        UserDefaults.standard.set("instant", forKey: "ShelfBar.floatingOpenAnimation")
        presentShelfInstantly()
    }

    private func presentShelfInstantly() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.onPresentShelf?()
            }
        }
    }

    private func presentShelfWithCenterFlight() {
        guard let screen = NSScreen.main else {
            presentShelfInstantly()
            return
        }
        buttonView?.setLaunching(true)
        let targetOrigin = NSPoint(
            x: screen.frame.midX - panel.frame.width / 2,
            y: screen.frame.minY + 8
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.0
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(targetOrigin)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.animateArrivalBounce()
            }
        }
    }

    private func animateArrivalBounce() {
        guard let buttonView else {
            finishCenterFlight()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            buttonView.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.08, y: 0.92))
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.10
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    buttonView.layer?.setAffineTransform(.identity)
                    self.panel.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        self?.finishCenterFlight()
                    }
                }
            }
        }
    }

    private func finishCenterFlight() {
        buttonView?.setLaunching(false)
        panel.orderOut(nil)
        panel.alphaValue = 1
        restorePosition()
        onPresentShelf?()
    }

    fileprivate func saveCurrentPosition() {
        let origin = clampedOrigin(panel.frame.origin)
        panel.setFrameOrigin(origin)
        UserDefaults.standard.set(Double(origin.x), forKey: Self.positionXKey)
        UserDefaults.standard.set(Double(origin.y), forKey: Self.positionYKey)
    }

    private func restorePosition() {
        let defaults = UserDefaults.standard
        let origin: NSPoint
        if defaults.object(forKey: Self.positionXKey) != nil,
           defaults.object(forKey: Self.positionYKey) != nil {
            origin = NSPoint(
                x: defaults.double(forKey: Self.positionXKey),
                y: defaults.double(forKey: Self.positionYKey)
            )
        } else if let screen = NSScreen.main {
            origin = NSPoint(
                x: screen.visibleFrame.maxX - panel.frame.width - 24,
                y: screen.visibleFrame.minY + 72
            )
        } else {
            origin = .zero
        }
        panel.setFrameOrigin(clampedOrigin(origin))
    }

    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(origin) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - panel.frame.width),
            y: min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
        )
    }

    @objc private func showApp() {
        onShowApp?()
    }

    @objc private func hideFromMenu() {
        hide()
    }

    @objc private func quitShelfBar() {
        NSApp.terminate(nil)
    }
}
