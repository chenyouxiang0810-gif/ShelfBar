import AppKit

@MainActor
protocol ShelfTouchDragDelegate: AnyObject {
    func shelfTouchDragBegan(
        sourceView: ShelfScrubberItemView,
        itemID: UUID,
        at point: NSPoint,
        in parentView: NSView
    )
    func shelfTouchDragChanged(itemID: UUID, at point: NSPoint, in parentView: NSView)
    func shelfTouchDragEnded(itemID: UUID, at point: NSPoint, in parentView: NSView, cancelled: Bool)
}

@MainActor
final class ShelfScrubberItemView: NSScrubberItemView {
    private static let maxThumbnailWidth: CGFloat = 48
    private static let maxThumbnailHeight: CGFloat = 28
    private let iconView = NSImageView()
    private let filenameLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private(set) var representedItem: FileShelfItem?
    private(set) var representedStackID: UUID?
    weak var touchDragDelegate: ShelfTouchDragDelegate?
    private var isStackDropTargetHighlighted = false
    private var isStackDropTargetReady = false
    private var touchDragItemID: UUID?
    private var internalDragShift: CGFloat = 0
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
        badgeLabel.font = .systemFont(ofSize: 7, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = .controlAccentColor
        badgeLabel.isBezeled = false
        badgeLabel.isEditable = false
        badgeLabel.drawsBackground = true
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 6
        badgeLabel.layer?.cornerCurve = .continuous
        badgeLabel.isHidden = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(filenameLabel)
        addSubview(badgeLabel)
        let press = NSPressGestureRecognizer(target: self, action: #selector(handleTouchDrag(_:)))
        press.minimumPressDuration = 0.18
        press.allowableMovement = 8
        addGestureRecognizer(press)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxThumbnailWidth),
            iconView.heightAnchor.constraint(lessThanOrEqualToConstant: Self.maxThumbnailHeight),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            filenameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            filenameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            filenameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor),
            filenameLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 13),
            badgeLabel.heightAnchor.constraint(equalToConstant: 12),
            badgeLabel.centerXAnchor.constraint(equalTo: iconView.trailingAnchor, constant: -2),
            badgeLabel.centerYAnchor.constraint(equalTo: iconView.topAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with item: FileShelfItem) {
        representedItem = item
        representedStackID = nil
        isStackDropTargetHighlighted = false
        isStackDropTargetReady = false
        isBridgeHighlighted = false
        internalDragShift = 0
        layer?.setAffineTransform(.identity)
        iconView.contentTintColor = nil
        iconView.image = item.displayImage
        filenameLabel.stringValue = item.filename
        badgeLabel.isHidden = true
        toolTip = item.url.path
    }

    func configure(with stack: ShelfStack, itemCount: Int? = nil) {
        representedItem = nil
        representedStackID = stack.id
        isStackDropTargetHighlighted = false
        isStackDropTargetReady = false
        isBridgeHighlighted = false
        internalDragShift = 0
        layer?.setAffineTransform(.identity)
        let stackIcon = NSImage(
            systemSymbolName: "square.stack.3d.up.fill",
            accessibilityDescription: stack.name
        )
        stackIcon?.isTemplate = true
        iconView.image = stackIcon
        iconView.contentTintColor = .secondaryLabelColor
        filenameLabel.stringValue = stack.name
        let count = itemCount ?? stack.entries.count
        badgeLabel.stringValue = "\(count)"
        badgeLabel.isHidden = false
        toolTip = "\(stack.name) — \(count) items"
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
                highlighted ? CGAffineTransform(scaleX: 1.04, y: 1.04) : .identity
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

    func setInternalDragShift(_ x: CGFloat) {
        guard representedItem != nil else { return }
        guard abs(internalDragShift - x) > 0.5 else { return }
        internalDragShift = x
        wantsLayer = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.setAffineTransform(CGAffineTransform(translationX: x, y: 0))
        }
    }

    @objc private func handleTouchDrag(_ recognizer: NSPressGestureRecognizer) {
        guard let parent = physicalTouchBarParent() else { return }
        let point = recognizer.location(in: parent)
        switch recognizer.state {
        case .began:
            guard let id = representedItem?.id else { return }
            touchDragItemID = id
            touchDragDelegate?.shelfTouchDragBegan(
                sourceView: self,
                itemID: id,
                at: point,
                in: parent
            )
        case .changed:
            guard let id = touchDragItemID else { return }
            touchDragDelegate?.shelfTouchDragChanged(itemID: id, at: point, in: parent)
        case .ended, .cancelled, .failed:
            guard let id = touchDragItemID else { return }
            touchDragDelegate?.shelfTouchDragEnded(
                itemID: id,
                at: point,
                in: parent,
                cancelled: recognizer.state != .ended
            )
            touchDragItemID = nil
        default:
            break
        }
    }

    private func physicalTouchBarParent() -> NSView? {
        var candidate: NSView? = self
        while let superview = candidate?.superview {
            candidate = superview
        }
        return candidate
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
