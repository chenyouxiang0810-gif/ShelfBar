import AppKit
import UniformTypeIdentifiers

@MainActor
func shelfBarBrandImage(for appearance: NSAppearance) -> NSImage? {
    let match = appearance.bestMatch(from: [.darkAqua, .aqua])
    let resource = match == .darkAqua ? "ShelfBarDark" : "ShelfBarLight"
    return Bundle.main.image(forResource: resource)
}

@MainActor
private final class ShelfBarLogoImageView: NSImageView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshBrandImage()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBrandImage()
    }

    func refreshBrandImage() {
        image = shelfBarBrandImage(for: effectiveAppearance)
        if let image {
            NSApp.applicationIconImage = image
        }
    }
}

@MainActor
private final class ShelfBarButton: NSButton {
    enum Style {
        case primary
        case secondary
        case danger
    }

    private let visualStyle: Style
    private var trackingAreaReference: NSTrackingArea?

    init(title: String, style: Style, target: AnyObject?, action: Selector?) {
        visualStyle = style
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        controlSize = .large
        font = .systemFont(ofSize: 13, weight: .semibold)
        alignment = .center
        focusRingType = .none
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.10
        layer?.shadowRadius = 5
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        heightAnchor.constraint(equalToConstant: 38).isActive = true
        updateColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 0.82
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch visualStyle {
            case .primary:
                layer?.backgroundColor = NSColor.controlAccentColor.cgColor
                contentTintColor = .white
            case .danger:
                layer?.backgroundColor = NSColor.systemRed.cgColor
                contentTintColor = .white
            case .secondary:
                layer?.backgroundColor = NSColor.controlColor.withAlphaComponent(0.78).cgColor
                contentTintColor = .labelColor
            }
        }
    }
}

@MainActor
private final class ShelfBarSidebarButton: NSButton {
    var isSelectedPage = false {
        didSet { updateColors() }
    }

    private var trackingAreaReference: NSTrackingArea?
    private var isHovering = false

    init(title: String, symbol: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageLeading
        imageHugsTitle = true
        alignment = .left
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 13, weight: .medium)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        heightAnchor.constraint(equalToConstant: 34).isActive = true
        updateColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isSelectedPage {
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                contentTintColor = .controlAccentColor
            } else if isHovering {
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
                contentTintColor = .labelColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                contentTintColor = .secondaryLabelColor
            }
        }
    }
}

@MainActor
final class DebugWindowController: NSWindowController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSToolbarDelegate {

    private enum SidebarPage: Int, CaseIterable {
        case general
        case appearance
        case shelf
        case developer

        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .shelf: "Shelf"
            case .developer: "Developer"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "circle.lefthalf.filled"
            case .shelf: "rectangle.bottomthird.inset.filled"
            case .developer: "hammer"
            }
        }
    }

    private enum Theme: String {
        case auto
        case light
        case dark

        static let defaultsKey = "ShelfBar.theme"
    }

    private struct FileMetadata {
        let kind: String
        let size: String
    }

    private static let aboutToolbarItem = NSToolbarItem.Identifier("ShelfBar.About")

    private let touchBarController: PrivateTouchBarController
    private let overlayController: ScreenEdgeDropOverlayController
    private let mouseBridgeResearchController: MouseBridgeResearchController
    private let stacks: ShelfStackModel

    private let rootEffect = NSVisualEffectView()
    private let logoImageView = ShelfBarLogoImageView()
    private let sidebarSettingsStack = NSStackView()
    private let previewStack = NSStackView()
    private weak var previewScrollView: NSScrollView?
    private let previewCountLabel = NSTextField(labelWithString: "0 items")
    private let countLabel = NSTextField(labelWithString: "0 files")
    private let filesTitleLabel = NSTextField(labelWithString: "Current Files")
    private let backFromStackButton = NSButton()
    private let renameStackButton = NSButton()
    private let removeStackButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "Idle")
    private let tableView = NSTableView()
    private let overlayToggle = NSButton()
    private let showDockToggle = NSButton()
    private let floatingButtonToggle = NSButton()
    private let airDropZoneToggle = NSButton()
    private let floatingAnimationPopup = NSPopUpButton()
    private let autoDissolveToggle = NSButton()
    private let showDeveloperTabToggle = NSButton()
    private let overlayHeightPopup = NSPopUpButton()
    private let themeControl = NSSegmentedControl(labels: ["Auto", "Light", "Dark"], trackingMode: .selectOne, target: nil, action: nil)
    private let developerToggle = NSButton()
    private let researchToggle = NSButton()
    private let finderPromiseToggle = NSButton()
    private let researchStatusLabel = NSTextField(labelWithString: "Research tools are off")
    private let dragLogTextView = NSTextView()
    private let developerDetailStack = NSStackView()
    private var sidebarButtons: [ShelfBarSidebarButton] = []
    private var selectedPage = SidebarPage.general
    private var items: [FileShelfItem] = []
    private var viewingStackID: UUID?
    private var stackButtonMap: [Int: UUID] = [:]
    private var metadataCache: [URL: FileMetadata] = [:]
    var onDockPreferenceChange: ((Bool) -> Void)?
    var onFloatingButtonPreferenceChange: ((Bool) -> Void)?

    init(
        touchBarController: PrivateTouchBarController,
        overlayController: ScreenEdgeDropOverlayController,
        mouseBridgeResearchController: MouseBridgeResearchController,
        stacks: ShelfStackModel
    ) {
        self.touchBarController = touchBarController
        self.overlayController = overlayController
        self.mouseBridgeResearchController = mouseBridgeResearchController
        self.stacks = stacks

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ShelfBar"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 980, height: 680)
        window.center()

        super.init(window: window)
        configureToolbar()
        buildUI()
        connectModel()
        configureTheme()
        statusLabel.stringValue = touchBarController.currentStatus
        updateOverlayControls()
        display(items: touchBarController.shelf.items)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "ShelfBar.Toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    private func connectModel() {
        touchBarController.onShelfChange = { [weak self] items in
            self?.display(items: items)
        }
        touchBarController.onStatusChange = { [weak self] message in
            self?.statusLabel.stringValue = message
        }
        overlayController.onConfigurationChange = { [weak self] in
            self?.updateOverlayControls()
            self?.touchBarController.setMouseBridgeHeightInPixels(
                self?.overlayController.heightInPixels ?? 5
            )
        }
        touchBarController.onDeveloperLogEntry = { [weak self] entry in
            self?.appendDragLog(entry)
        }
        touchBarController.onStacksChange = { [weak self] stacks in
            self?.stacksDidChange(stacks)
        }
        touchBarController.onShelfScrollOffsetChange = { [weak self] offset in
            self?.syncPreviewScrollOffset(offset)
        }
        mouseBridgeResearchController.onStatusChange = { [weak self] message in
            self?.researchStatusLabel.stringValue = message
        }
        mouseBridgeResearchController.onDragLogEntry = { [weak self] entry in
            self?.appendDragLog(entry)
        }
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        rootEffect.material = .underWindowBackground
        rootEffect.blendingMode = .behindWindow
        rootEffect.state = .active
        rootEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootEffect)

        let sidebar = makeSidebar()
        let dashboard = makeDashboard()
        rootEffect.addSubview(sidebar)
        rootEffect.addSubview(dashboard)

        NSLayoutConstraint.activate([
            rootEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            sidebar.leadingAnchor.constraint(equalTo: rootEffect.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: rootEffect.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: rootEffect.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 250),

            dashboard.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            dashboard.trailingAnchor.constraint(equalTo: rootEffect.trailingAnchor),
            dashboard.topAnchor.constraint(equalTo: rootEffect.topAnchor),
            dashboard.bottomAnchor.constraint(equalTo: rootEffect.bottomAnchor)
        ])

        showSidebarPage(.general, animated: false)
    }

    private func makeSidebar() -> NSVisualEffectView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        logoImageView.imageScaling = .scaleProportionallyUpOrDown
        logoImageView.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "ShelfBar")
        title.font = .systemFont(ofSize: 21, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Touch Bar file shelf")
        subtitle.font = .systemFont(ofSize: 11, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        let identityText = NSStackView(views: [title, subtitle])
        identityText.orientation = .vertical
        identityText.alignment = .leading
        identityText.spacing = 1
        let identity = NSStackView(views: [logoImageView, identityText])
        identity.orientation = .horizontal
        identity.alignment = .centerY
        identity.spacing = 12

        let settingsTitle = NSTextField(labelWithString: "SETTINGS")
        settingsTitle.font = .systemFont(ofSize: 10, weight: .semibold)
        settingsTitle.textColor = .tertiaryLabelColor

        let navigation = NSStackView()
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 3
        for page in SidebarPage.allCases {
            let button = ShelfBarSidebarButton(
                title: page.title,
                symbol: page.symbol,
                target: self,
                action: #selector(selectSidebarPage(_:))
            )
            button.tag = page.rawValue
            if page == .developer {
                button.isHidden = !UserDefaults.standard.bool(forKey: "ShelfBar.showDeveloperTab")
            }
            button.widthAnchor.constraint(equalToConstant: 214).isActive = true
            navigation.addArrangedSubview(button)
            sidebarButtons.append(button)
        }

        sidebarSettingsStack.orientation = .vertical
        sidebarSettingsStack.alignment = .leading
        sidebarSettingsStack.spacing = 12
        sidebarSettingsStack.translatesAutoresizingMaskIntoConstraints = false

        let settingsDocument = NSView()
        settingsDocument.translatesAutoresizingMaskIntoConstraints = false
        settingsDocument.addSubview(sidebarSettingsStack)
        let settingsScroll = NSScrollView()
        settingsScroll.drawsBackground = false
        settingsScroll.hasVerticalScroller = true
        settingsScroll.autohidesScrollers = true
        settingsScroll.documentView = settingsDocument

        let stack = NSStackView(views: [identity, settingsTitle, navigation, separator(), settingsScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 46),
            logoImageView.heightAnchor.constraint(equalToConstant: 46),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18),
            settingsScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            settingsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            settingsDocument.widthAnchor.constraint(equalTo: settingsScroll.contentView.widthAnchor),
            sidebarSettingsStack.leadingAnchor.constraint(equalTo: settingsDocument.leadingAnchor),
            sidebarSettingsStack.trailingAnchor.constraint(equalTo: settingsDocument.trailingAnchor),
            sidebarSettingsStack.topAnchor.constraint(equalTo: settingsDocument.topAnchor),
            sidebarSettingsStack.bottomAnchor.constraint(equalTo: settingsDocument.bottomAnchor)
        ])
        return sidebar
    }

    private func makeDashboard() -> NSView {
        let dashboard = NSView()
        dashboard.translatesAutoresizingMaskIntoConstraints = false

        let headline = NSTextField(labelWithString: "Shelf Preview")
        headline.font = .systemFont(ofSize: 30, weight: .bold)
        let description = NSTextField(labelWithString: "A live preview of what appears on your Touch Bar.")
        description.font = .systemFont(ofSize: 13)
        description.textColor = .secondaryLabelColor
        let headingText = NSStackView(views: [headline, description])
        headingText.orientation = .vertical
        headingText.alignment = .leading
        headingText.spacing = 3

        previewCountLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        previewCountLabel.textColor = .secondaryLabelColor

        let presentButton = modernButton("Present Shelf", style: .primary, action: #selector(presentTouchBar), width: 126)
        let reloadButton = modernButton("Reload", style: .primary, action: #selector(reloadShelf), width: 88)
        let closeButton = modernButton("Close Shelf", style: .secondary, action: #selector(dismissTouchBar), width: 108)
        let clearButton = modernButton("Clear", style: .danger, action: #selector(clearShelf), width: 76)
        let actions = NSStackView(views: [presentButton, reloadButton, closeButton, clearButton])
        actions.orientation = .horizontal
        actions.spacing = 9

        let headerSpacer = NSView()
        let header = NSStackView(views: [headingText, headerSpacer, previewCountLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let previewCard = makePreviewCard()
        let filesCard = makeFilesCard()

        let stack = NSStackView(views: [header, actions, previewCard, filesCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        dashboard.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: dashboard.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: dashboard.trailingAnchor, constant: -34),
            stack.topAnchor.constraint(equalTo: dashboard.safeAreaLayoutGuide.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: dashboard.bottomAnchor, constant: -30),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            previewCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            filesCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            filesCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 320)
        ])
        return dashboard
    }

    private func makePreviewCard() -> NSVisualEffectView {
        let card = glassCard()
        let title = sectionTitle("TOUCH BAR")

        previewStack.orientation = .horizontal
        previewStack.alignment = .centerY
        previewStack.spacing = 10
        previewStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        previewStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = previewStack
        previewScrollView = scroll
        scroll.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(title)
        card.addSubview(scroll)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            scroll.heightAnchor.constraint(equalToConstant: 126),
            previewStack.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor)
        ])
        return card
    }

    private func syncPreviewScrollOffset(_ offset: CGFloat) {
        guard let scroll = previewScrollView, let document = scroll.documentView else { return }
        let maximum = max(document.bounds.width - scroll.contentView.bounds.width, 0)
        var origin = scroll.contentView.bounds.origin
        origin.x = min(max(offset, 0), maximum)
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func makeFilesCard() -> NSVisualEffectView {
        let card = glassCard()
        filesTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        backFromStackButton.title = "Back"
        backFromStackButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backFromStackButton.imagePosition = .imageLeading
        backFromStackButton.isBordered = false
        backFromStackButton.target = self
        backFromStackButton.action = #selector(backFromStack)
        backFromStackButton.isHidden = true
        renameStackButton.title = "Rename"
        renameStackButton.isBordered = false
        renameStackButton.target = self
        renameStackButton.action = #selector(renameCurrentStack)
        renameStackButton.isHidden = true
        removeStackButton.title = "Remove Stack"
        removeStackButton.contentTintColor = .systemRed
        removeStackButton.isBordered = false
        removeStackButton.target = self
        removeStackButton.action = #selector(removeCurrentStack)
        removeStackButton.isHidden = true
        let removeButton = modernButton("Remove", style: .danger, action: #selector(removeSelected), width: 88)
        let headerSpacer = NSView()
        let header = NSStackView(views: [
            backFromStackButton,
            filesTitleLabel,
            countLabel,
            renameStackButton,
            removeStackButton,
            headerSpacer,
            removeButton
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false

        configureTable()
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = tableView
        scroll.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(header)
        card.addSubview(scroll)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
        ])
        return card
    }

    private func configureTable() {
        let columns: [(String, String, CGFloat, CGFloat)] = [
            ("thumbnail", "", 58, 58),
            ("name", "Name", 180, 120),
            ("kind", "Kind", 120, 90),
            ("size", "Size", 82, 72),
            ("path", "Path", 320, 180)
        ]
        for (identifier, title, width, minWidth) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = minWidth
            tableView.addTableColumn(column)
        }
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 48
        tableView.intercellSpacing = NSSize(width: 8, height: 2)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.style = .fullWidth
        tableView.dataSource = self
        tableView.delegate = self
    }

    private func configureTheme() {
        let stored = UserDefaults.standard.string(forKey: Theme.defaultsKey)
        let theme = Theme(rawValue: stored ?? "") ?? .auto
        themeControl.selectedSegment = theme == .auto ? 0 : (theme == .light ? 1 : 2)
        themeControl.target = self
        themeControl.action = #selector(changeTheme)
        applyTheme(theme, animated: false)
    }

    private func showSidebarPage(_ page: SidebarPage, animated: Bool) {
        selectedPage = page
        for (index, button) in sidebarButtons.enumerated() {
            button.isSelectedPage = index == page.rawValue
        }

        let update = { [self] in
            for view in sidebarSettingsStack.arrangedSubviews {
                sidebarSettingsStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            sidebarSettingsStack.addArrangedSubview(sectionTitle(page.title.uppercased()))
            switch page {
            case .general:
                buildGeneralSettings()
            case .appearance:
                buildAppearanceSettings()
            case .shelf:
                buildShelfSettings()
            case .developer:
                buildDeveloperSettings()
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.10
                sidebarSettingsStack.animator().alphaValue = 0.15
            }, completionHandler: {
                update()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    self.sidebarSettingsStack.animator().alphaValue = 1
                }
            })
        } else {
            update()
        }
    }

    private func buildGeneralSettings() {
        overlayToggle.setButtonType(.switch)
        overlayToggle.target = self
        overlayToggle.action = #selector(toggleOverlay)
        sidebarSettingsStack.addArrangedSubview(overlayToggle)

        if overlayHeightPopup.numberOfItems == 0 {
            overlayHeightPopup.addItems(withTitles:
                ScreenEdgeDropOverlayController.supportedHeights.map { "\($0) px" }
            )
            overlayHeightPopup.target = self
            overlayHeightPopup.action = #selector(changeOverlayHeight)
        }
        sidebarSettingsStack.addArrangedSubview(settingRow(label: "Overlay height", control: overlayHeightPopup))
        sidebarSettingsStack.addArrangedSubview(caption("Universal AutoDrop accepts supported files, images, text, links, RTF and HTML from any app."))
        sidebarSettingsStack.addArrangedSubview(statusPill())

        showDockToggle.setButtonType(.switch)
        showDockToggle.title = "Show in Dock"
        showDockToggle.state = UserDefaults.standard.bool(forKey: "ShelfBar.showInDock") ? .on : .off
        showDockToggle.target = self
        showDockToggle.action = #selector(toggleShowInDock)
        sidebarSettingsStack.addArrangedSubview(showDockToggle)

        floatingButtonToggle.setButtonType(.switch)
        floatingButtonToggle.title = "Show floating Shelf button after Close"
        floatingButtonToggle.state = UserDefaults.standard.bool(
            forKey: "ShelfBar.showFloatingAfterClose"
        ) ? .on : .off
        floatingButtonToggle.target = self
        floatingButtonToggle.action = #selector(toggleFloatingButton)
        sidebarSettingsStack.addArrangedSubview(floatingButtonToggle)

        airDropZoneToggle.setButtonType(.switch)
        airDropZoneToggle.title = "Enable AirDrop Zone"
        airDropZoneToggle.state = UserDefaults.standard.object(forKey: "ShelfBar.enableAirDropZone") == nil
            || UserDefaults.standard.bool(forKey: "ShelfBar.enableAirDropZone")
            ? .on : .off
        airDropZoneToggle.target = self
        airDropZoneToggle.action = #selector(toggleAirDropZone)
        sidebarSettingsStack.addArrangedSubview(airDropZoneToggle)

        if floatingAnimationPopup.numberOfItems == 0 {
            floatingAnimationPopup.addItems(withTitles: ["Instant"])
            floatingAnimationPopup.target = self
            floatingAnimationPopup.action = #selector(changeFloatingOpenAnimation)
        }
        floatingAnimationPopup.selectItem(withTitle: "Instant")
        sidebarSettingsStack.addArrangedSubview(
            settingRow(label: "Floating Button Open", control: floatingAnimationPopup)
        )

        showDeveloperTabToggle.setButtonType(.switch)
        showDeveloperTabToggle.title = "Show Developer Tab"
        showDeveloperTabToggle.state = UserDefaults.standard.bool(forKey: "ShelfBar.showDeveloperTab") ? .on : .off
        showDeveloperTabToggle.target = self
        showDeveloperTabToggle.action = #selector(toggleDeveloperTabVisibility)
        sidebarSettingsStack.addArrangedSubview(showDeveloperTabToggle)
    }

    private func buildAppearanceSettings() {
        themeControl.segmentStyle = .rounded
        themeControl.selectedSegment = currentTheme == .auto ? 0 : (currentTheme == .light ? 1 : 2)
        sidebarSettingsStack.addArrangedSubview(caption("Theme"))
        sidebarSettingsStack.addArrangedSubview(themeControl)
        themeControl.widthAnchor.constraint(equalToConstant: 210).isActive = true
        sidebarSettingsStack.addArrangedSubview(caption("Auto follows the current macOS appearance. Light and Dark stay fixed."))
    }

    private func buildShelfSettings() {
        sidebarSettingsStack.addArrangedSubview(
            caption("Create a Stack on the Touch Bar: drag one Shelf file onto another, hold for 0.55 seconds until the blue ready outline appears, then release.")
        )
        autoDissolveToggle.setButtonType(.switch)
        autoDissolveToggle.title = "Auto dissolve single-item stack"
        autoDissolveToggle.state = UserDefaults.standard.bool(
            forKey: "ShelfBar.autoDissolveSingleItemStack"
        ) ? .on : .off
        autoDissolveToggle.target = self
        autoDissolveToggle.action = #selector(toggleAutoDissolveStack)
        sidebarSettingsStack.addArrangedSubview(autoDissolveToggle)
        let present = modernButton("Present Shelf", style: .primary, action: #selector(presentTouchBar), width: 210)
        let reload = modernButton("Reload", style: .primary, action: #selector(reloadShelf), width: 210)
        let close = modernButton("Close Shelf", style: .secondary, action: #selector(dismissTouchBar), width: 210)
        let clear = modernButton("Clear", style: .danger, action: #selector(clearShelf), width: 210)
        [present, reload, close, clear].forEach(sidebarSettingsStack.addArrangedSubview)
    }

    private func buildDeveloperSettings() {
        developerToggle.setButtonType(.switch)
        developerToggle.title = "Enable Developer Tools"
        developerToggle.target = self
        developerToggle.action = #selector(toggleDeveloperMode)
        sidebarSettingsStack.addArrangedSubview(developerToggle)

        researchToggle.setButtonType(.switch)
        researchToggle.title = "MouseBridge Research"
        researchToggle.target = self
        researchToggle.action = #selector(toggleResearchMode)

        finderPromiseToggle.setButtonType(.switch)
        finderPromiseToggle.title = "FilePromise Prototype"
        finderPromiseToggle.target = self
        finderPromiseToggle.action = #selector(toggleFinderPromiseProbe)

        researchStatusLabel.font = .systemFont(ofSize: 10)
        researchStatusLabel.textColor = .secondaryLabelColor
        researchStatusLabel.lineBreakMode = .byWordWrapping
        researchStatusLabel.maximumNumberOfLines = 3

        dragLogTextView.isEditable = false
        dragLogTextView.isSelectable = true
        dragLogTextView.isRichText = false
        dragLogTextView.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        dragLogTextView.backgroundColor = .clear
        if dragLogTextView.string.isEmpty {
            dragLogTextView.string = "Developer logs are idle.\n"
        }
        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.autohidesScrollers = true
        logScroll.drawsBackground = false
        logScroll.documentView = dragLogTextView
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        logScroll.widthAnchor.constraint(equalToConstant: 210).isActive = true

        let clearLog = modernButton("Clear Logs", style: .secondary, action: #selector(clearDragLog), width: 210)
        developerDetailStack.setViews([
            researchToggle,
            finderPromiseToggle,
            researchStatusLabel,
            clearLog,
            logScroll
        ], in: .top)
        developerDetailStack.orientation = .vertical
        developerDetailStack.alignment = .leading
        developerDetailStack.spacing = 10
        developerDetailStack.isHidden = developerToggle.state != .on
        sidebarSettingsStack.addArrangedSubview(developerDetailStack)
    }

    private func updateOverlayControls() {
        overlayToggle.state = overlayController.isEnabled ? .on : .off
        overlayToggle.title = overlayController.isEnabled ? "Overlay On" : "Overlay Off"
        overlayHeightPopup.selectItem(withTitle: "\(overlayController.heightInPixels) px")
    }

    private func display(items: [FileShelfItem]) {
        self.items = items
        metadataCache.removeAll()
        updateFileListState()
        rebuildPreview()
    }

    private func stacksDidChange(_ updatedStacks: [ShelfStack]) {
        if let viewingStackID,
           !updatedStacks.contains(where: { $0.id == viewingStackID }) {
            self.viewingStackID = nil
        }
        metadataCache.removeAll()
        updateFileListState()
        rebuildPreview()
    }

    private var displayedItems: [FileShelfItem] {
        guard let viewingStackID else { return items }
        return stacks.fileItems(in: viewingStackID)
    }

    private func updateFileListState() {
        let list = displayedItems
        let currentStack = viewingStackID.flatMap(stacks.stack(id:))
        filesTitleLabel.stringValue = currentStack?.name ?? "Current Files"
        countLabel.stringValue = "\(list.count) file\(list.count == 1 ? "" : "s")"
        backFromStackButton.isHidden = currentStack == nil
        renameStackButton.isHidden = currentStack == nil
        removeStackButton.isHidden = currentStack == nil
        let previewCount = viewingStackID.map(stacks.directItemCount(in:))
            ?? (items.count + stacks.rootStacks.count)
        previewCountLabel.stringValue = "\(previewCount) item\(previewCount == 1 ? "" : "s")"
        tableView.reloadData()
    }

    private func rebuildPreview() {
        for view in previewStack.arrangedSubviews {
            previewStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        stackButtonMap.removeAll()
        let previewItems = displayedItems
        let previewStacks = viewingStackID.map(stacks.childStacks(of:)) ?? stacks.rootStacks
        guard !previewItems.isEmpty || !previewStacks.isEmpty else {
            let empty = NSTextField(labelWithString: "Drop files at the bottom edge to begin")
            empty.font = .systemFont(ofSize: 13, weight: .medium)
            empty.textColor = .secondaryLabelColor
            previewStack.addArrangedSubview(empty)
            return
        }

        for item in previewItems {
            previewStack.addArrangedSubview(previewCard(for: item))
        }
        for (index, stack) in previewStacks.enumerated() {
            stackButtonMap[index] = stack.id
            previewStack.addArrangedSubview(stackPreviewCard(stack, tag: index))
        }
    }

    private func previewCard(for item: FileShelfItem) -> NSVisualEffectView {
        let card = NSVisualEffectView()
        card.material = .menu
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false

        let image = NSImageView(image: item.displayImage)
        image.imageScaling = .scaleProportionallyDown
        image.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: item.filename)
        name.alignment = .center
        name.font = .systemFont(ofSize: 10, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        name.toolTip = item.url.path
        let stack = NSStackView(views: [image, name])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 112),
            card.heightAnchor.constraint(equalToConstant: 94),
            image.widthAnchor.constraint(equalToConstant: 48),
            image.heightAnchor.constraint(equalToConstant: 42),
            name.widthAnchor.constraint(equalToConstant: 92),
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    private func stackPreviewCard(_ stack: ShelfStack, tag: Int) -> NSButton {
        let button = NSButton(
            title: "\(stack.name)  ·  \(stacks.directItemCount(in: stack.id))",
            target: self,
            action: #selector(openStackFromPreview(_:))
        )
        button.tag = tag
        button.image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: stack.name)
        button.imagePosition = .imageAbove
        button.font = .systemFont(ofSize: 10, weight: .semibold)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.layer?.cornerCurve = .continuous
        button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.13).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 112),
            button.heightAnchor.constraint(equalToConstant: 94)
        ])
        return button
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedItems.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard displayedItems.indices.contains(row), let tableColumn else { return nil }
        let item = displayedItems[row]
        let key = tableColumn.identifier.rawValue

        if key == "thumbnail" {
            let identifier = NSUserInterfaceItemIdentifier("thumbnailCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
                ?? makeIconCell(identifier: identifier)
            cell.imageView?.image = item.displayImage
            return cell
        }

        let cell = (tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView)
            ?? makeTextCell(identifier: tableColumn.identifier)
        let metadata = metadata(for: item.url)
        switch key {
        case "name": cell.textField?.stringValue = item.filename
        case "kind": cell.textField?.stringValue = metadata.kind
        case "size": cell.textField?.stringValue = metadata.size
        default: cell.textField?.stringValue = item.url.path
        }
        cell.toolTip = item.url.path
        return cell
    }

    private func makeIconCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cell.imageView = imageView
        cell.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 34),
            imageView.heightAnchor.constraint(equalToConstant: 34)
        ])
        return cell
    }

    private func makeTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = label
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -3),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func metadata(for url: URL) -> FileMetadata {
        if let cached = metadataCache[url] { return cached }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        let kind = isDirectory ? "Folder" : (values?.contentType?.localizedDescription ?? "File")
        let size: String
        if isDirectory {
            size = "—"
        } else if let bytes = values?.fileSize {
            size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        } else {
            size = "—"
        }
        let metadata = FileMetadata(kind: kind, size: size)
        metadataCache[url] = metadata
        return metadata
    }

    private var currentTheme: Theme {
        Theme(rawValue: UserDefaults.standard.string(forKey: Theme.defaultsKey) ?? "") ?? .auto
    }

    private func applyTheme(_ theme: Theme, animated: Bool) {
        UserDefaults.standard.set(theme.rawValue, forKey: Theme.defaultsKey)
        let appearance: NSAppearance?
        switch theme {
        case .auto: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }

        let update = {
            NSApp.appearance = appearance
            self.window?.appearance = appearance
            self.logoImageView.refreshBrandImage()
        }
        guard animated else {
            update()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            rootEffect.animator().alphaValue = 0.45
        }, completionHandler: {
            update()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                self.rootEffect.animator().alphaValue = 1
            }
        })
    }

    private func appendDragLog(_ entry: String) {
        let next = dragLogTextView.string + entry + "\n"
        dragLogTextView.string = next.count > 100_000 ? String(next.suffix(100_000)) : next
        dragLogTextView.scrollToEndOfDocument(nil)
    }

    private func glassCard() -> NSVisualEffectView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.cornerCurve = .continuous
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.10
        card.layer?.shadowRadius = 16
        card.layer?.shadowOffset = NSSize(width: 0, height: -4)
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func modernButton(
        _ title: String,
        style: ShelfBarButton.Style,
        action: Selector,
        width: CGFloat
    ) -> ShelfBarButton {
        let button = ShelfBarButton(title: title, style: style, target: self, action: action)
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        return button
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 210).isActive = true
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 214).isActive = true
        return box
    }

    private func settingRow(label: String, control: NSView) -> NSStackView {
        let field = NSTextField(labelWithString: label)
        field.font = .systemFont(ofSize: 12, weight: .medium)
        let spacer = NSView()
        let row = NSStackView(views: [field, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 210).isActive = true
        return row
    }

    private func statusPill() -> NSVisualEffectView {
        let pill = NSVisualEffectView()
        pill.material = .menu
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 9
        pill.translatesAutoresizingMaskIntoConstraints = false
        let dot = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) ?? NSImage())
        dot.contentTintColor = .systemGreen
        dot.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [dot, statusLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)
        NSLayoutConstraint.activate([
            pill.widthAnchor.constraint(equalToConstant: 210),
            pill.heightAnchor.constraint(equalToConstant: 34),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 11),
            row.trailingAnchor.constraint(lessThanOrEqualTo: pill.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        return pill
    }

    private func infoLine(symbol: String, text: String, color: NSColor) -> NSStackView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: text) ?? NSImage())
        image.contentTintColor = color
        image.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let row = NSStackView(views: [image, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        image.widthAnchor.constraint(equalToConstant: 16).isActive = true
        return row
    }

    @objc private func selectSidebarPage(_ sender: NSButton) {
        guard let page = SidebarPage(rawValue: sender.tag) else { return }
        showSidebarPage(page, animated: true)
    }

    @objc private func changeTheme() {
        let theme: Theme = themeControl.selectedSegment == 1
            ? .light
            : (themeControl.selectedSegment == 2 ? .dark : .auto)
        applyTheme(theme, animated: true)
    }

    func setThemeFromMenu(index: Int) {
        themeControl.selectedSegment = min(max(index, 0), 2)
        changeTheme()
    }

    var currentThemeIndex: Int {
        currentTheme == .auto ? 0 : (currentTheme == .light ? 1 : 2)
    }

    func openPreferences(page: Int = 0) {
        let target = SidebarPage(rawValue: page) ?? .general
        if target == .developer,
           !UserDefaults.standard.bool(forKey: "ShelfBar.showDeveloperTab") {
            showSidebarPage(.general, animated: false)
        } else {
            showSidebarPage(target, animated: false)
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func clearShelf() {
        touchBarController.clearShelf()
    }

    @objc private func removeSelected() {
        let row = tableView.selectedRow
        guard displayedItems.indices.contains(row) else {
            NSSound.beep()
            return
        }
        let item = displayedItems[row]
        if let viewingStackID {
            touchBarController.removeStackItem(id: item.id, from: viewingStackID)
        } else {
            touchBarController.removeShelfItem(id: item.id)
        }
    }

    @objc private func createStack() {
        let alert = NSAlert()
        alert.messageText = "New Folder Stack"
        alert.informativeText = "Choose a name for this stack."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "New Stack")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let id = stacks.create(name: field.stringValue)
        touchBarController.enterStack(id: id)
        viewingStackID = id
        updateFileListState()
        rebuildPreview()
    }

    @objc private func openStackFromPreview(_ sender: NSButton) {
        guard let id = stackButtonMap[sender.tag] else { return }
        viewingStackID = id
        touchBarController.enterStack(id: id)
        updateFileListState()
    }

    @objc private func backFromStack() {
        viewingStackID = nil
        touchBarController.leaveStack()
        updateFileListState()
    }

    @objc private func renameCurrentStack() {
        guard let viewingStackID, let stack = stacks.stack(id: viewingStackID) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Stack"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: stack.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        stacks.rename(id: viewingStackID, name: field.stringValue)
    }

    @objc private func removeCurrentStack() {
        guard let viewingStackID, let stack = stacks.stack(id: viewingStackID) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(stack.name)?"
        alert.informativeText = "This removes the stack from ShelfBar. Original files are not deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove Stack")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        stacks.remove(id: viewingStackID)
        self.viewingStackID = nil
        touchBarController.leaveStack()
        updateFileListState()
    }

    @objc private func reloadShelf() {
        touchBarController.shelf.reloadFromDisk()
    }

    @objc private func presentTouchBar() {
        touchBarController.presentSystemModal()
    }

    @objc private func dismissTouchBar() {
        touchBarController.closeShelfFromUser()
    }

    @objc private func toggleOverlay() {
        overlayController.setEnabled(overlayToggle.state == .on)
    }

    @objc private func toggleShowInDock() {
        let enabled = showDockToggle.state == .on
        UserDefaults.standard.set(enabled, forKey: "ShelfBar.showInDock")
        onDockPreferenceChange?(enabled)
    }

    @objc private func toggleFloatingButton() {
        let enabled = floatingButtonToggle.state == .on
        UserDefaults.standard.set(enabled, forKey: "ShelfBar.showFloatingAfterClose")
        onFloatingButtonPreferenceChange?(enabled)
    }

    @objc private func toggleAirDropZone() {
        UserDefaults.standard.set(airDropZoneToggle.state == .on, forKey: "ShelfBar.enableAirDropZone")
    }

    @objc private func changeFloatingOpenAnimation() {
        UserDefaults.standard.set("instant", forKey: "ShelfBar.floatingOpenAnimation")
    }

    @objc private func toggleAutoDissolveStack() {
        let enabled = autoDissolveToggle.state == .on
        UserDefaults.standard.set(enabled, forKey: "ShelfBar.autoDissolveSingleItemStack")
        if enabled {
            touchBarController.normalizeStacksForCurrentPreference()
        }
    }

    @objc private func toggleDeveloperTabVisibility() {
        let visible = showDeveloperTabToggle.state == .on
        UserDefaults.standard.set(visible, forKey: "ShelfBar.showDeveloperTab")
        if let button = sidebarButtons.first(where: { $0.tag == SidebarPage.developer.rawValue }) {
            button.isHidden = !visible
        }
        if !visible, selectedPage == .developer {
            showSidebarPage(.general, animated: true)
        }
    }

    @objc private func changeOverlayHeight() {
        guard let title = overlayHeightPopup.selectedItem?.title,
              let pixels = Int(title.replacingOccurrences(of: " px", with: ""))
        else { return }
        overlayController.setHeightInPixels(pixels)
    }

    @objc private func toggleResearchMode() {
        mouseBridgeResearchController.setEnabled(researchToggle.state == .on)
        if researchToggle.state == .off {
            researchStatusLabel.stringValue = "Research tools are off"
        }
    }

    @objc private func toggleFinderPromiseProbe() {
        mouseBridgeResearchController.setFinderPromiseProbeEnabled(
            finderPromiseToggle.state == .on
        )
    }

    @objc private func toggleDeveloperMode() {
        let enabled = developerToggle.state == .on
        if enabled {
            developerDetailStack.isHidden = false
            developerDetailStack.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                developerDetailStack.animator().alphaValue = 1
            }
        } else {
            researchToggle.state = .off
            finderPromiseToggle.state = .off
            mouseBridgeResearchController.setEnabled(false)
            mouseBridgeResearchController.setFinderPromiseProbeEnabled(false)
            researchStatusLabel.stringValue = "Research tools are off"
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.14
                developerDetailStack.animator().alphaValue = 0
            }, completionHandler: {
                self.developerDetailStack.isHidden = true
            })
        }
    }

    @objc private func clearDragLog() {
        dragLogTextView.string = ""
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let alert = NSAlert()
        alert.messageText = "ShelfBar"
        alert.informativeText = "Version \(version) (\(build))\n\n© 2026 ShelfBar. All rights reserved."
        alert.alertStyle = .informational
        alert.icon = shelfBarBrandImage(for: window?.effectiveAppearance ?? NSApp.effectiveAppearance)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "GitHub")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com")!)
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.aboutToolbarItem]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.aboutToolbarItem]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.aboutToolbarItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "About ShelfBar"
        item.paletteLabel = "About ShelfBar"
        item.toolTip = "About ShelfBar"
        item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About ShelfBar")
        item.target = self
        item.action = #selector(showAbout)
        return item
    }
}
