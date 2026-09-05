import AppKit

@MainActor
final class ScreenEdgeDropOverlayController: NSWindowController {
    static let supportedHeights = [30, 20, 10, 5, 2]

    private static let enabledKey = "FileShelf.v2.overlayEnabled"
    private static let heightKey = "FileShelf.v2.overlayHeightPixels"

    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class OverlayDropView: NSView {
        private weak var dropDelegate: OverlayDropDelegate?
        var onDragFinished: (() -> Void)?
        var isAirDropEnabledProvider: (() -> Bool)?
        private var activeZone: ShelfDropZone = .none

        init(delegate: OverlayDropDelegate) {
            self.dropDelegate = delegate
            super.init(frame: .zero)
            registerForDraggedTypes(FileDropReader.registeredTypes)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard FileDropReader.supports(sender.draggingPasteboard) else { return [] }
            let snapshot = zoneSnapshot(for: sender.draggingLocation)
            activeZone = snapshot.zone
            dropDelegate?.overlayDragEntered(snapshot: snapshot)
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard FileDropReader.supports(sender.draggingPasteboard) else { return [] }
            let snapshot = zoneSnapshot(for: sender.draggingLocation)
            activeZone = snapshot.zone
            dropDelegate?.overlayDragUpdated(snapshot: snapshot)
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            activeZone = .none
            dropDelegate?.overlayDragExited()
            onDragFinished?()
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            true
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { onDragFinished?() }
            activeZone = zoneSnapshot(for: sender.draggingLocation).zone
            let inspection = FileDropReader.inspect(sender.draggingPasteboard)
            print("[ShelfBar] pasteboard.types=\(inspection.pasteboardTypes)")
            print("[ShelfBar] fileURLs=\(inspection.urls.map(\.path))")
            print("[ShelfBar] detectedKinds=\(inspection.detectedKinds.map(\.rawValue))")
            print("[ShelfBar] activeDropZone=\(activeZone.rawValue)")

            guard !inspection.imports.isEmpty else {
                print("[ShelfBar] drop rejected reasons=\(inspection.failureReasons)")
                dropDelegate?.overlayDropDidFail(inspection)
                return false
            }

            guard activeZone == .airDrop || activeZone == .shelf else {
                print("[ShelfBar] drop ignored because activeDropZone=\(activeZone.rawValue)")
                dropDelegate?.overlayDropDidFail(inspection)
                return false
            }

            print("[ShelfBar] readers=\(inspection.successfulReaders)")
            for item in inspection.imports {
                print("[ShelfBar] temp/local path=\(item.localURL?.path ?? "original file")")
            }
            if activeZone == .airDrop {
                dropDelegate?.overlayDidRequestAirDrop(imports: inspection.imports, inspection: inspection)
                return true
            }
            dropDelegate?.overlayDidReceive(imports: inspection.imports)
            return true
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            activeZone = .none
            dropDelegate?.overlayDragEnded()
            onDragFinished?()
        }

        private func zoneSnapshot(for location: NSPoint) -> ShelfDropZoneSnapshot {
            let gap: CGFloat = 8
            let airDropEnabled = isAirDropEnabledProvider?() ?? true
            let airDropRect: NSRect
            let gapRect: NSRect
            let shelfRect: NSRect
            if airDropEnabled {
                let split = bounds.width / 3
                let airDropMaxX = split - gap / 2
                let shelfMinX = split + gap / 2
                airDropRect = NSRect(
                    x: bounds.minX,
                    y: bounds.minY,
                    width: max(airDropMaxX - bounds.minX, 0),
                    height: bounds.height
                )
                gapRect = NSRect(
                    x: airDropMaxX,
                    y: bounds.minY,
                    width: max(shelfMinX - airDropMaxX, 0),
                    height: bounds.height
                )
                shelfRect = NSRect(
                    x: shelfMinX,
                    y: bounds.minY,
                    width: max(bounds.maxX - shelfMinX, 0),
                    height: bounds.height
                )
            } else {
                airDropRect = .zero
                gapRect = .zero
                shelfRect = bounds
            }
            let zone: ShelfDropZone
            if !bounds.contains(location) {
                zone = .none
            } else if !airDropEnabled {
                zone = shelfRect.contains(location) ? .shelf : .none
            } else if airDropRect.contains(location) {
                zone = .airDrop
            } else if shelfRect.contains(location) {
                zone = .shelf
            } else if gapRect.contains(location) {
                zone = .gap
            } else {
                zone = .none
            }
            print(
                "[ShelfBar] activeDropZone=\(zone.rawValue) dragLocationX=\(String(format: "%.2f", location.x)) "
                    + "airDropRect=\(airDropRect) shelfRect=\(shelfRect) gapRect=\(gapRect)"
            )
            return ShelfDropZoneSnapshot(
                zone: zone,
                locationX: location.x,
                airDropRect: airDropRect,
                shelfRect: shelfRect,
                gapRect: gapRect
            )
        }
    }

    private(set) var isOverlayVisible = false
    private(set) var isEnabled: Bool
    private(set) var heightInPixels: Int
    var isAirDropEnabledProvider: (() -> Bool)? {
        didSet {
            dropView.isAirDropEnabledProvider = isAirDropEnabledProvider
        }
    }
    var onConfigurationChange: (() -> Void)?

    private let dropView: OverlayDropView
    private var pendingHide: DispatchWorkItem?

    init(delegate: OverlayDropDelegate) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.enabledKey) == nil {
            isEnabled = true
        } else {
            isEnabled = defaults.bool(forKey: Self.enabledKey)
        }
        let storedHeight = defaults.integer(forKey: Self.heightKey)
        heightInPixels = Self.supportedHeights.contains(storedHeight) ? storedHeight : 5

        let dropView = OverlayDropView(delegate: delegate)
        self.dropView = dropView
        let panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = dropView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false

        super.init(window: panel)
        dropView.onDragFinished = { [weak self] in
            self?.scheduleHide()
        }
        updateFrame()
        hideOverlayImmediately()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showOverlayForFinderDrag() {
        guard isEnabled else { return }
        pendingHide?.cancel()
        pendingHide = nil
        updateFrame()
        window?.orderFrontRegardless()
        isOverlayVisible = true
    }

    func scheduleHide(after delay: TimeInterval = 0.3) {
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideOverlayImmediately()
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hideOverlayImmediately() {
        pendingHide?.cancel()
        pendingHide = nil
        window?.orderOut(nil)
        isOverlayVisible = false
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled {
            hideOverlayImmediately()
        }
        onConfigurationChange?()
    }

    func setHeightInPixels(_ pixels: Int) {
        guard Self.supportedHeights.contains(pixels) else { return }
        heightInPixels = pixels
        UserDefaults.standard.set(pixels, forKey: Self.heightKey)
        updateFrame()
        onConfigurationChange?()
    }

    private func updateFrame() {
        guard let screen = NSScreen.main else { return }
        let width = min(CGFloat(1085), screen.frame.width)
        let scale = max(screen.backingScaleFactor, 1)
        let heightInPoints = CGFloat(heightInPixels) / scale
        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.minY,
            width: width,
            height: heightInPoints
        )
        window?.setFrame(frame, display: true)
    }
}
