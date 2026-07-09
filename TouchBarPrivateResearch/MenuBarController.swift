import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private weak var shelfController: PrivateTouchBarController?
    private weak var overlayController: ScreenEdgeDropOverlayController?
    private weak var windowController: DebugWindowController?
    private let overlayToggle = NSButton()
    private let themeControl = NSSegmentedControl(
        labels: ["Auto", "Light", "Dark"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    init(
        shelfController: PrivateTouchBarController,
        overlayController: ScreenEdgeDropOverlayController,
        windowController: DebugWindowController
    ) {
        self.shelfController = shelfController
        self.overlayController = overlayController
        self.windowController = windowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.templateIcon()
            button.image?.isTemplate = true
            button.toolTip = "ShelfBar"
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 286, height: 330)
        popover.contentViewController = makeContentController()
    }

    private func makeContentController() -> NSViewController {
        let controller = NSViewController()
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .withinWindow
        root.state = .active

        let logo = NSImageView()
        logo.image = shelfBarBrandImage(for: NSApp.effectiveAppearance)
        logo.imageScaling = .scaleProportionallyDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "ShelfBar")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Touch Bar file shelf")
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1
        let identity = NSStackView(views: [logo, titleStack])
        identity.orientation = .horizontal
        identity.alignment = .centerY
        identity.spacing = 10

        let present = menuButton("Present Shelf", symbol: "rectangle.bottomthird.inset.filled", action: #selector(presentShelf))
        let open = menuButton("Open ShelfBar", symbol: "macwindow", action: #selector(openShelfBar))
        let preferences = menuButton("Preferences…", symbol: "gearshape", action: #selector(openPreferences))

        overlayToggle.setButtonType(.switch)
        overlayToggle.title = "Overlay"
        overlayToggle.state = overlayController?.isEnabled == true ? .on : .off
        overlayToggle.target = self
        overlayToggle.action = #selector(toggleOverlay)

        let themeLabel = NSTextField(labelWithString: "Theme")
        themeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        let spacer = NSView()
        themeControl.selectedSegment = windowController?.currentThemeIndex ?? 0
        themeControl.target = self
        themeControl.action = #selector(changeTheme)
        let themeRow = NSStackView(views: [themeLabel, spacer, themeControl])
        themeRow.orientation = .horizontal
        themeRow.alignment = .centerY

        let quit = menuButton("Quit ShelfBar", symbol: "power", action: #selector(quitShelfBar))
        quit.contentTintColor = .systemRed

        let stack = NSStackView(views: [
            identity,
            separator(),
            present,
            overlayToggle,
            themeRow,
            separator(),
            open,
            preferences,
            quit
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        controller.view = root

        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 38),
            logo.heightAnchor.constraint(equalToConstant: 38),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14),
            identity.widthAnchor.constraint(equalTo: stack.widthAnchor),
            themeRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return controller
    }

    private func menuButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.bezelStyle = .recessed
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        button.widthAnchor.constraint(equalToConstant: 250).isActive = true
        return button
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 250).isActive = true
        return box
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            overlayToggle.state = overlayController?.isEnabled == true ? .on : .off
            themeControl.selectedSegment = windowController?.currentThemeIndex ?? 0
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func presentShelf() {
        shelfController?.presentSystemModal()
        popover.performClose(nil)
    }

    @objc private func toggleOverlay() {
        overlayController?.setEnabled(overlayToggle.state == .on)
    }

    @objc private func changeTheme() {
        windowController?.setThemeFromMenu(index: themeControl.selectedSegment)
    }

    @objc private func openShelfBar() {
        windowController?.openPreferences(page: 0)
        popover.performClose(nil)
    }

    @objc private func openPreferences() {
        windowController?.openPreferences(page: 1)
        popover.performClose(nil)
    }

    @objc private func quitShelfBar() {
        NSApp.terminate(nil)
    }

    private static func templateIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let back = NSBezierPath(roundedRect: NSRect(x: 5, y: 8, width: 8, height: 7), xRadius: 1.5, yRadius: 1.5)
            back.lineWidth = 1.3
            back.stroke()
            let front = NSBezierPath(roundedRect: NSRect(x: 3, y: 6, width: 8, height: 7), xRadius: 1.5, yRadius: 1.5)
            front.lineWidth = 1.3
            front.stroke()
            let bar = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2, width: 15, height: 3), xRadius: 1.5, yRadius: 1.5)
            bar.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
