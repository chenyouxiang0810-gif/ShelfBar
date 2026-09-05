import AppKit

@MainActor
protocol ShelfScrubberItemViewTouchReorderDelegate: AnyObject {
    func shelfScrubberItemView(_ view: ShelfScrubberItemView, didBeginTouchReorderAt point: NSPoint) -> Bool
    func shelfScrubberItemView(_ view: ShelfScrubberItemView, didUpdateTouchReorderAt point: NSPoint)
    func shelfScrubberItemView(_ view: ShelfScrubberItemView, didEndTouchReorderAt point: NSPoint, cancelled: Bool)
}

@MainActor
final class ShelfScrubberItemView: NSScrubberItemView, NSGestureRecognizerDelegate {
    private static let maxThumbnailWidth: CGFloat = 48
    private static let maxThumbnailHeight: CGFloat = 20
    private static let rowHeight: CGFloat = 30
    private static let badgeTopInset: CGFloat = 8
    private static let badgeTrailingInset: CGFloat = 22
    private static let badgeLeadingInset: CGFloat = 10
    private static let badgeHorizontalPadding: CGFloat = 7
    private static let badgeMinWidth: CGFloat = 15
    private static let badgeHeight: CGFloat = 13
    private let iconView = NSImageView()
    private let filenameLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let dividerView = NSView()
    private(set) var representedItem: FileShelfItem?
    private(set) var representedClipboardItem: ClipboardShelfItem?
    private(set) var representedStackID: UUID?
    private(set) var allowsInternalReorder = true
    private(set) var isPinDivider = false
    weak var touchReorderDelegate: ShelfScrubberItemViewTouchReorderDelegate?
    private var isStackDropTargetHighlighted = false
    private var isStackDropTargetReady = false
    private var internalDragShift: CGFloat = 0
    private var isInternalDragLifted = false
    private var isTouchReorderGestureActive = false
    private lazy var touchReorderPressRecognizer: NSPressGestureRecognizer = {
        let recognizer = NSPressGestureRecognizer(
            target: self,
            action: #selector(handleTouchReorderPress(_:))
        )
        recognizer.minimumPressDuration = 0.35
        recognizer.allowedTouchTypes = [.direct]
        recognizer.delegate = self
        return recognizer
    }()
    var isBridgeHighlighted = false {
        didSet {
            updateHighlightAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        filenameLabel.alignment = .center
        filenameLabel.font = .systemFont(ofSize: 8, weight: .regular)
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.maximumNumberOfLines = 1
        filenameLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.alignment = .center
        badgeLabel.font = .systemFont(ofSize: 7.5, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = .controlAccentColor
        badgeLabel.isBezeled = false
        badgeLabel.isEditable = false
        badgeLabel.drawsBackground = true
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = Self.badgeHeight / 2
        badgeLabel.layer?.cornerCurve = .continuous
        badgeLabel.layer?.masksToBounds = true
        badgeLabel.isHidden = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = true

        addSubview(iconView)
        addSubview(filenameLabel)
        addSubview(badgeLabel)
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.58).cgColor
        dividerView.isHidden = true
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dividerView)
        addGestureRecognizer(touchReorderPressRecognizer)
        touchReorderPressRecognizer.isEnabled = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(lessThanOrEqualToConstant: Self.rowHeight),
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxThumbnailWidth),
            iconView.heightAnchor.constraint(lessThanOrEqualToConstant: Self.maxThumbnailHeight),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: Self.maxThumbnailHeight),
            filenameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            filenameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            filenameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor),
            filenameLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            dividerView.topAnchor.constraint(equalTo: topAnchor),
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 1.5)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with item: FileShelfItem, pinned: Bool = false, allowsReorder: Bool = true) {
        representedItem = item
        representedClipboardItem = nil
        representedStackID = nil
        allowsInternalReorder = allowsReorder
        isTouchReorderGestureActive = false
        isPinDivider = false
        dividerView.isHidden = true
        isStackDropTargetHighlighted = false
        isStackDropTargetReady = false
        isBridgeHighlighted = false
        internalDragShift = 0
        isInternalDragLifted = false
        layer?.setAffineTransform(.identity)
        iconView.contentTintColor = nil
        iconView.image = item.displayImage
        filenameLabel.font = .systemFont(ofSize: 8, weight: .regular)
        filenameLabel.textColor = .labelColor
        filenameLabel.alignment = .center
        filenameLabel.stringValue = item.filename
        badgeLabel.stringValue = "PIN"
        badgeLabel.backgroundColor = .systemYellow
        badgeLabel.textColor = .black
        badgeLabel.isHidden = !pinned
        needsLayout = true
        toolTip = item.url.path
        updateTouchReorderRecognizerAvailability()
    }

    func configure(with stack: ShelfStack, itemCount: Int? = nil, allowsReorder: Bool = true) {
        representedItem = nil
        representedClipboardItem = nil
        representedStackID = stack.id
        allowsInternalReorder = allowsReorder
        isTouchReorderGestureActive = false
        isPinDivider = false
        dividerView.isHidden = true
        isStackDropTargetHighlighted = false
        isStackDropTargetReady = false
        isBridgeHighlighted = false
        internalDragShift = 0
        isInternalDragLifted = false
        layer?.setAffineTransform(.identity)
        let stackIcon = NSImage(
            systemSymbolName: "square.stack.3d.up.fill",
            accessibilityDescription: stack.name
        )
        stackIcon?.isTemplate = true
        iconView.image = stackIcon
        iconView.contentTintColor = .secondaryLabelColor
        filenameLabel.font = .systemFont(ofSize: 8, weight: .regular)
        filenameLabel.textColor = .labelColor
        filenameLabel.alignment = .center
        filenameLabel.stringValue = stack.name
        let count = itemCount ?? stack.entries.count
        badgeLabel.stringValue = "\(count)"
        badgeLabel.backgroundColor = .controlAccentColor
        badgeLabel.textColor = .white
        badgeLabel.isHidden = false
        needsLayout = true
        toolTip = "\(stack.name) — \(count) items"
        updateTouchReorderRecognizerAvailability()
    }

    func configure(with item: ClipboardShelfItem) {
        representedItem = nil
        representedClipboardItem = item
        representedStackID = nil
        allowsInternalReorder = false
        isTouchReorderGestureActive = false
        isPinDivider = false
        dividerView.isHidden = true
        isStackDropTargetHighlighted = false
        isStackDropTargetReady = false
        isBridgeHighlighted = false
        internalDragShift = 0
        isInternalDragLifted = false
        layer?.setAffineTransform(.identity)
        iconView.contentTintColor = nil
        iconView.image = item.displayImage
        filenameLabel.font = .systemFont(ofSize: 8, weight: .regular)
        filenameLabel.textColor = .labelColor
        filenameLabel.alignment = .center
        filenameLabel.stringValue = item.title
        badgeLabel.stringValue = "★"
        badgeLabel.backgroundColor = .systemYellow
        badgeLabel.textColor = .black
        badgeLabel.isHidden = !item.pinned
        needsLayout = true
        toolTip = item.text ?? item.urlString ?? item.fileURLString ?? item.title
        updateTouchReorderRecognizerAvailability()
    }

    func configurePinDivider() {
        representedItem = nil
        representedClipboardItem = nil
        representedStackID = nil
        allowsInternalReorder = false
        isTouchReorderGestureActive = false
        isPinDivider = true
        isStackDropTargetHighlighted = false
        isStackDropTargetReady = false
        isBridgeHighlighted = false
        internalDragShift = 0
        isInternalDragLifted = false
        layer?.setAffineTransform(.identity)
        iconView.image = nil
        iconView.contentTintColor = nil
        filenameLabel.stringValue = ""
        filenameLabel.alignment = .center
        badgeLabel.isHidden = true
        dividerView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.58).cgColor
        dividerView.isHidden = false
        needsLayout = true
        toolTip = "Pinned files divider"
        updateTouchReorderRecognizerAvailability()
    }

    override func layout() {
        super.layout()
        layoutBadgeInsideBounds()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isInternalDragLifted { return nil }
        return super.hitTest(point)
    }

    private func layoutBadgeInsideBounds() {
        guard !badgeLabel.isHidden else { return }
        let safeBounds = bounds.insetBy(
            dx: Self.badgeLeadingInset,
            dy: Self.badgeTopInset
        )
        let availableWidth = max(safeBounds.width - Self.badgeTrailingInset, 0)
        guard availableWidth > 0 else {
            badgeLabel.frame = .zero
            return
        }

        let textWidth = badgeLabel.intrinsicContentSize.width + Self.badgeHorizontalPadding
        let width = min(max(Self.badgeMinWidth, ceil(textWidth)), availableWidth)
        let height = min(Self.badgeHeight, max(safeBounds.height, 0))
        let iconFrame = iconView.frame.isEmpty ? bounds : iconView.frame
        let preferredX = iconFrame.maxX - width * 0.55
        let x = min(
            max(preferredX, safeBounds.minX),
            max(bounds.maxX - Self.badgeTrailingInset - width, safeBounds.minX)
        )
        let preferredY = iconFrame.maxY - height * 0.75
        let y = min(
            max(preferredY, safeBounds.minY),
            max(bounds.maxY - Self.badgeTopInset - height, safeBounds.minY)
        )
        badgeLabel.frame = NSRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
        badgeLabel.layer?.cornerRadius = badgeLabel.frame.height / 2
    }

    func setStackDropTargetHighlighted(_ highlighted: Bool) {
        guard isStackDropTargetHighlighted != highlighted else { return }
        isStackDropTargetHighlighted = highlighted
        if !highlighted { isStackDropTargetReady = false }
        updateHighlightAppearance()
        wantsLayer = true
        layer?.shadowColor = NSColor.controlAccentColor.cgColor
        layer?.shadowOpacity = highlighted ? 0.48 : 0
        layer?.shadowRadius = highlighted ? 5 : 0
        layer?.shadowOffset = .zero
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            layer?.setAffineTransform(
                highlighted ? CGAffineTransform(scaleX: 1.02, y: 1.02) : .identity
            )
        }
    }

    func setStackDropTargetReady(_ ready: Bool) {
        isStackDropTargetReady = ready
        if ready { isStackDropTargetHighlighted = true }
        updateHighlightAppearance()
        layer?.shadowOpacity = ready ? 0.68 : (isStackDropTargetHighlighted ? 0.48 : 0)
        layer?.shadowRadius = ready ? 7 : (isStackDropTargetHighlighted ? 5 : 0)
    }

    func setBridgePressed(_ pressed: Bool) {
        guard !isInternalDragLifted else { return }
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = pressed ? 0.22 : 0
        layer?.shadowRadius = pressed ? 4 : 0
        let transform = pressed
            ? CGAffineTransform(scaleX: 0.96, y: 0.96)
            : .identity
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            layer?.setAffineTransform(transform)
        }
    }

    func setDragOutActive(_ active: Bool) {
        guard !isInternalDragLifted else { return }
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = active ? 0.34 : 0
        layer?.shadowRadius = active ? 7 : 0
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            animator().alphaValue = active ? 0.92 : 1
            layer?.setAffineTransform(
                active ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
            )
        }
    }

    func setInternalDragShift(_ x: CGFloat, animated: Bool = false) {
        guard allowsInternalReorder, representedItem != nil || representedStackID != nil else { return }
        guard abs(internalDragShift - x) > 0.25 else { return }
        internalDragShift = x
        wantsLayer = true
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        if x == 0 {
            layer?.setAffineTransform(.identity)
        } else {
            layer?.setAffineTransform(CGAffineTransform(translationX: x, y: 0))
        }
        CATransaction.commit()
    }

    func setInternalDragLifted(_ lifted: Bool, animated: Bool = true) {
        guard isInternalDragLifted != lifted else { return }
        isInternalDragLifted = lifted
        wantsLayer = true
        let update = {
            self.alphaValue = lifted ? 0 : 1
            self.layer?.shadowOpacity = 0
            self.layer?.shadowRadius = 0
        }
        guard animated else {
            update()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = lifted ? 0.08 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            update()
        }
    }

    func resetTransientInteractionState() {
        isTouchReorderGestureActive = false
        isInternalDragLifted = false
        internalDragShift = 0
        alphaValue = 1
        wantsLayer = true
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 0
        layer?.setAffineTransform(.identity)
        setStackDropTargetHighlighted(false)
    }

    @objc private func handleTouchReorderPress(_ recognizer: NSPressGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            guard canAttemptTouchReorder else {
                isTouchReorderGestureActive = false
                return
            }
            isTouchReorderGestureActive = touchReorderDelegate?
                .shelfScrubberItemView(self, didBeginTouchReorderAt: point) == true
        case .changed:
            guard isTouchReorderGestureActive else { return }
            touchReorderDelegate?.shelfScrubberItemView(self, didUpdateTouchReorderAt: point)
        case .ended:
            finishTouchReorder(at: point, cancelled: false)
        case .cancelled, .failed:
            finishTouchReorder(at: point, cancelled: true)
        default:
            break
        }
    }

    private var canAttemptTouchReorder: Bool {
        allowsInternalReorder && (representedItem != nil || representedStackID != nil)
    }

    private func updateTouchReorderRecognizerAvailability() {
        touchReorderPressRecognizer.isEnabled = canAttemptTouchReorder
    }

    private func finishTouchReorder(at point: NSPoint, cancelled: Bool) {
        guard isTouchReorderGestureActive else { return }
        touchReorderDelegate?.shelfScrubberItemView(
            self,
            didEndTouchReorderAt: point,
            cancelled: cancelled
        )
        isTouchReorderGestureActive = false
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
        canAttemptTouchReorder
    }

    func animateDragOutSuccess(completion: @escaping () -> Void) {
        wantsLayer = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
            layer?.setAffineTransform(CGAffineTransform(scaleX: 0.84, y: 0.84))
        } completionHandler: {
            completion()
        }
    }

    func animateDragOutCancelled() {
        wantsLayer = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            layer?.shadowOpacity = 0
            layer?.shadowRadius = 0
            layer?.setAffineTransform(.identity)
        }
    }

    private func updateHighlightAppearance() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = isStackDropTargetReady ? 2 : (isStackDropTargetHighlighted ? 1 : 0)
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.72).cgColor
        layer?.backgroundColor = (isBridgeHighlighted || isStackDropTargetHighlighted)
            ? NSColor.selectedControlColor.withAlphaComponent(isStackDropTargetReady ? 0.50 : 0.32).cgColor
            : NSColor.clear.cgColor
    }

}
