import AppKit

@MainActor
final class TouchBarDropButton: NSView {
    static let drawerSymbolName = "tray.and.arrow.down.fill"
    private final class ZoneView: NSView {
        private let imageView = NSImageView()
        private let label: NSTextField
        private let iconScale: CGFloat

        init(title: String, image: NSImage?, iconScale: CGFloat) {
            self.label = NSTextField(labelWithString: title)
            self.iconScale = iconScale
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            layer?.cornerRadius = 9
            layer?.cornerCurve = .continuous
            layer?.shadowColor = NSColor.controlAccentColor.cgColor
            layer?.shadowOffset = .zero

            imageView.image = image
            imageView.imageScaling = .scaleProportionallyDown
            imageView.contentTintColor = .controlAccentColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.wantsLayer = true

            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false

            let stack = NSStackView(views: [imageView, label])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 5
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
            ])
            apply(active: false, animated: false)
        }

        required init?(coder: NSCoder) {
            nil
        }

        func apply(active: Bool, animated: Bool = true) {
            let changes = {
                self.layer?.backgroundColor = NSColor.controlAccentColor
                    .withAlphaComponent(active ? 0.26 : 0.14)
                    .cgColor
                self.layer?.shadowOpacity = active ? 0.30 : 0.16
                self.layer?.shadowRadius = active ? 10 : 5
                self.imageView.contentTintColor = active ? .controlAccentColor : .secondaryLabelColor
                self.label.textColor = active ? .controlAccentColor : .labelColor
                self.imageView.layer?.setAffineTransform(
                    active
                        ? CGAffineTransform(scaleX: self.iconScale, y: self.iconScale)
                        : .identity
                )
            }
            guard animated else {
                changes()
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                changes()
            }
        }
    }

    private let airDropZone: ZoneView
    private let shelfZone: ZoneView

    static func drawerImage() -> NSImage? {
        NSImage(
            systemSymbolName: drawerSymbolName,
            accessibilityDescription: "Shelf drawer"
        )
    }

    private static func airDropImage() -> NSImage? {
        NSImage(
            systemSymbolName: "airdrop",
            accessibilityDescription: "AirDrop"
        ) ?? NSImage(
            systemSymbolName: "dot.radiowaves.left.and.right",
            accessibilityDescription: "AirDrop"
        )
    }

    init(activeZone: ShelfDropZone = .none) {
        airDropZone = ZoneView(
            title: "AirDrop",
            image: Self.airDropImage(),
            iconScale: 1.08
        )
        shelfZone = ZoneView(
            title: "Drop your file here",
            image: Self.drawerImage(),
            iconScale: 1.05
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(airDropZone)
        addSubview(shelfZone)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 520),
            heightAnchor.constraint(equalToConstant: 30),
            airDropZone.leadingAnchor.constraint(equalTo: leadingAnchor),
            airDropZone.topAnchor.constraint(equalTo: topAnchor),
            airDropZone.bottomAnchor.constraint(equalTo: bottomAnchor),
            airDropZone.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 1 / 3, constant: -4),
            shelfZone.leadingAnchor.constraint(equalTo: airDropZone.trailingAnchor, constant: 8),
            shelfZone.trailingAnchor.constraint(equalTo: trailingAnchor),
            shelfZone.topAnchor.constraint(equalTo: topAnchor),
            shelfZone.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyActiveZone(activeZone, animated: false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func applyActiveZone(_ zone: ShelfDropZone, animated: Bool = true) {
        airDropZone.apply(active: zone == .airDrop, animated: animated)
        shelfZone.apply(active: zone == .shelf, animated: animated)
    }
}
