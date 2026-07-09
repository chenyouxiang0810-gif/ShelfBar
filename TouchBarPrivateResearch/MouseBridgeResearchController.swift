import AppKit
import UniformTypeIdentifiers

// The source exports the original URL. Finder owns any destination-side copy.
// Advertising .link caused Finder folder drops to create an alias instead of a normal file.
private let dragBackAllowedOperations: NSDragOperation = .copy

private func dragPointDescription(_ point: NSPoint) -> String {
    String(format: "(%.1f, %.1f)", point.x, point.y)
}

private func dragOperationDescription(_ operation: NSDragOperation) -> String {
    guard !operation.isEmpty else { return "none" }
    var names: [String] = []
    if operation.contains(.copy) { names.append("copy") }
    if operation.contains(.link) { names.append("link") }
    if operation.contains(.generic) { names.append("generic") }
    if operation.contains(.move) { names.append("move") }
    if operation.contains(.delete) { names.append("delete") }
    if operation.contains(.private) { names.append("private") }
    return names.isEmpty ? "raw=\(operation.rawValue)" : names.joined(separator: "+")
}

@MainActor
private final class FinderFilePromiseWriter: NSObject, NSFilePromiseProviderDelegate {
    nonisolated let sourceURL: URL
    private let logHandler: (String) -> Void
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "TouchBarPrivateResearch.FinderPromiseWriter"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(sourceURL: URL, logHandler: @escaping (String) -> Void) {
        self.sourceURL = sourceURL
        self.logHandler = logHandler
        super.init()
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        logHandler("File Promise filename requested | type=\(fileType) name=\(sourceURL.lastPathComponent)")
        return sourceURL.lastPathComponent
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        let filename = sourceURL.lastPathComponent
        Task { @MainActor [weak self] in
            self?.logHandler(
                "writePromiseTo called | destinationURL=\(url.absoluteString) "
                    + "filename=\(filename) source=\(self?.sourceURL.path ?? "<released>")"
            )
        }

        do {
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileNoSuchFileError,
                    userInfo: [
                        NSFilePathErrorKey: sourceURL.path,
                        NSLocalizedDescriptionKey: "Promise source file no longer exists."
                    ]
                )
            }
            try FileManager.default.copyItem(at: sourceURL, to: url)
            Task { @MainActor [weak self] in
                self?.logHandler(
                    "File Promise success | destinationURL=\(url.absoluteString) "
                        + "filename=\(filename) success=true"
                )
            }
            completionHandler(nil)
        } catch {
            let nsError = error as NSError
            Task { @MainActor [weak self] in
                self?.logHandler(
                    "File Promise failure | destinationURL=\(url.absoluteString) "
                        + "filename=\(filename) success=false "
                        + "error=\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
                )
            }
            completionHandler(error)
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        promiseQueue
    }
}

private func filePromiseType(for url: URL) -> String {
    let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
    if values?.isDirectory == true {
        return UTType.folder.identifier
    }
    return values?.contentType?.identifier ?? UTType.data.identifier
}

private struct BridgeDragPayload {
    let url: URL
    let image: NSImage
    let useFilePromise: Bool
}

final class ResearchFilePasteboardWriter: NSObject, NSPasteboardWriting {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .fileURL ? url.absoluteString : nil
    }

    func writingOptions(
        forType type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        []
    }
}

private func addURLRepresentations(to session: NSDraggingSession, url: URL) {
    let pasteboard = session.draggingPasteboard
    pasteboard.addTypes([.URL], owner: nil)
    pasteboard.setString(url.absoluteString, forType: .URL)
}

@MainActor
private protocol MouseBridgeEdgeDelegate: AnyObject {
    func bridgeMouseEntered(at x: CGFloat)
    func bridgeMouseMoved(to x: CGFloat)
    func bridgeMouseExited()
    func bridgeMouseClicked(at x: CGFloat)
    func bridgeDragPayload(at x: CGFloat) -> BridgeDragPayload?
    func bridgeDragStarted(url: URL)
    func bridgeDragEvent(_ message: String)
    func bridgeDragEnded(url: URL, operation: NSDragOperation)
}

@MainActor
private final class MouseBridgeEdgeController: NSWindowController {
    private final class EdgePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class EdgeView: NSView, NSDraggingSource {
        weak var delegate: MouseBridgeEdgeDelegate?
        private var trackingAreaReference: NSTrackingArea?
        private var mouseDownX: CGFloat?
        private var activeDragURL: URL?
        private var activePromiseWriter: FinderFilePromiseWriter?

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
            delegate?.bridgeMouseEntered(at: event.locationInWindow.x)
        }

        override func mouseMoved(with event: NSEvent) {
            delegate?.bridgeMouseMoved(to: event.locationInWindow.x)
        }

        override func mouseExited(with event: NSEvent) {
            delegate?.bridgeMouseExited()
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownX = event.locationInWindow.x
            activeDragURL = nil
            activePromiseWriter = nil
        }

        override func mouseUp(with event: NSEvent) {
            defer { mouseDownX = nil }
            guard activeDragURL == nil else { return }
            delegate?.bridgeMouseClicked(at: event.locationInWindow.x)
        }

        override func mouseDragged(with event: NSEvent) {
            guard activeDragURL == nil,
                  let x = mouseDownX,
                  let payload = delegate?.bridgeDragPayload(at: x)
            else { return }

            let url = payload.url
            activeDragURL = url
            let item: NSDraggingItem
            if payload.useFilePromise {
                let writer = FinderFilePromiseWriter(sourceURL: url) { [weak self] message in
                    self?.delegate?.bridgeDragEvent(message)
                }
                activePromiseWriter = writer
                let provider = NSFilePromiseProvider(
                    fileType: filePromiseType(for: url),
                    delegate: writer
                )
                provider.userInfo = url
                item = NSDraggingItem(pasteboardWriter: provider)
                delegate?.bridgeDragEvent(
                    "File Promise Copy enabled | type=\(provider.fileType) source=\(url.path)"
                )
            } else {
                item = NSDraggingItem(pasteboardWriter: ResearchFilePasteboardWriter(url: url))
            }
            let size = NSSize(width: 36, height: 36)
            item.setDraggingFrame(
                NSRect(
                    x: event.locationInWindow.x - size.width / 2,
                    y: event.locationInWindow.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                contents: payload.image
            )
            delegate?.bridgeDragStarted(url: url)
            let session = beginDraggingSession(with: [item], event: event, source: self)
            if !payload.useFilePromise {
                addURLRepresentations(to: session, url: url)
            }
            let types = (session.draggingPasteboard.types ?? []).map(\.rawValue).joined(separator: ", ")
            delegate?.bridgeDragEvent("Pasteboard ready | types=[\(types)]")
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            let isLocal = context == .withinApplication
            let contextName = isLocal ? "withinApplication" : "outsideApplication"
            delegate?.bridgeDragEvent(
                "Operation Mask | context=\(contextName) isLocal=\(isLocal) "
                    + "allowed=\(dragOperationDescription(dragBackAllowedOperations))"
            )
            return dragBackAllowedOperations
        }

        func draggingSession(
            _ session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint
        ) {
            let types = (session.draggingPasteboard.types ?? []).map(\.rawValue).joined(separator: ", ")
            delegate?.bridgeDragEvent(
                "Drag Begin | route=MouseBridge point=\(dragPointDescription(screenPoint)) "
                    + "pasteboard=[\(types)]"
            )
            delegate?.bridgeDragEvent(
                "Drag Enter Destination | unavailable to NSDraggingSource; destination callbacks stay in target app"
            )
        }

        func draggingSession(
            _ session: NSDraggingSession,
            movedTo screenPoint: NSPoint
        ) {
            delegate?.bridgeDragEvent(
                "Drag Update | route=MouseBridge point=\(dragPointDescription(screenPoint))"
            )
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            let accepted = !operation.isEmpty
            delegate?.bridgeDragEvent(
                "Drag End | route=MouseBridge point=\(dragPointDescription(screenPoint)) "
                    + "Operation=\(dragOperationDescription(operation)) "
                    + "FinderAccepted=\(accepted) FinderRejected=\(!accepted) Cancelled=\(!accepted)"
            )
            if let activeDragURL {
                delegate?.bridgeDragEnded(url: activeDragURL, operation: operation)
            }
            activeDragURL = nil
            mouseDownX = nil
        }
    }

    init(width: CGFloat, delegate: MouseBridgeEdgeDelegate) {
        let panel = EdgePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let edgeView = EdgeView(frame: panel.contentRect(forFrameRect: panel.frame))
        edgeView.autoresizingMask = [.width, .height]
        edgeView.delegate = delegate
        panel.contentView = edgeView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false

        super.init(window: panel)
        if let screen = NSScreen.main {
            panel.setFrame(
                NSRect(
                    x: screen.frame.midX - width / 2,
                    y: screen.frame.minY,
                    width: width,
                    height: 10
                ),
                display: true
            )
        }
        panel.orderFrontRegardless()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func closeBridge() {
        window?.orderOut(nil)
        close()
    }
}

@MainActor
private final class DirectTouchBarFileButton: NSButton, NSDraggingSource {
    var fileURL: URL?
    var onStatus: ((String) -> Void)?
    var onDragEvent: ((String) -> Void)?
    var useFilePromise = false
    private var startedSession = false
    private var activePromiseWriter: FinderFilePromiseWriter?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        addGestureRecognizer(pan)
    }

    @objc private func panned(_ recognizer: NSPanGestureRecognizer) {
        guard recognizer.state == .began, !startedSession, let fileURL else { return }
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDragged,
              window != nil
        else {
            onStatus?("Direct Touch Bar drag unavailable: no desktop mouseDragged event.")
            return
        }

        startedSession = true
        activePromiseWriter = nil
        let draggingItem: NSDraggingItem
        if useFilePromise {
            let writer = FinderFilePromiseWriter(sourceURL: fileURL) { [weak self] message in
                self?.onDragEvent?(message)
            }
            activePromiseWriter = writer
            let provider = NSFilePromiseProvider(
                fileType: filePromiseType(for: fileURL),
                delegate: writer
            )
            provider.userInfo = fileURL
            draggingItem = NSDraggingItem(pasteboardWriter: provider)
            onDragEvent?("File Promise Copy enabled | type=\(provider.fileType) source=\(fileURL.path)")
        } else {
            draggingItem = NSDraggingItem(
                pasteboardWriter: ResearchFilePasteboardWriter(url: fileURL)
            )
        }
        draggingItem.setDraggingFrame(convert(bounds, to: nil), contents: image)
        onDragEvent?("Drag Begin requested | route=Direct URL=\(fileURL.path)")
        onStatus?("Direct Touch Bar NSDraggingSession started.")
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        if !useFilePromise {
            addURLRepresentations(to: session, url: fileURL)
        }
        let types = (session.draggingPasteboard.types ?? []).map(\.rawValue).joined(separator: ", ")
        onDragEvent?("Pasteboard ready | types=[\(types)]")
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        let isLocal = context == .withinApplication
        let contextName = isLocal ? "withinApplication" : "outsideApplication"
        onDragEvent?(
            "Operation Mask | route=Direct context=\(contextName) isLocal=\(isLocal) "
                + "allowed=\(dragOperationDescription(dragBackAllowedOperations))"
        )
        return dragBackAllowedOperations
    }

    func draggingSession(
        _ session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint
    ) {
        let types = (session.draggingPasteboard.types ?? []).map(\.rawValue).joined(separator: ", ")
        onDragEvent?(
            "Drag Begin | route=Direct point=\(dragPointDescription(screenPoint)) "
                + "pasteboard=[\(types)]"
        )
        onDragEvent?(
            "Drag Enter Destination | unavailable to NSDraggingSource; destination callbacks stay in target app"
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        movedTo screenPoint: NSPoint
    ) {
        onDragEvent?("Drag Update | route=Direct point=\(dragPointDescription(screenPoint))")
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        startedSession = false
        let accepted = !operation.isEmpty
        onDragEvent?(
            "Drag End | route=Direct point=\(dragPointDescription(screenPoint)) "
                + "Operation=\(dragOperationDescription(operation)) "
                + "FinderAccepted=\(accepted) FinderRejected=\(!accepted) Cancelled=\(!accepted)"
        )
        onStatus?("Direct Touch Bar drag ended operation=\(operation.rawValue).")
    }
}

@MainActor
final class MouseBridgeResearchController: NSObject, NSTouchBarDelegate, MouseBridgeEdgeDelegate {
    private enum ItemID {
        static let a = NSTouchBarItem.Identifier("com.prototype.MouseBridge.A")
        static let b = NSTouchBarItem.Identifier("com.prototype.MouseBridge.B")
        static let c = NSTouchBarItem.Identifier("com.prototype.MouseBridge.C")
        static let file = NSTouchBarItem.Identifier("com.prototype.MouseBridge.file")
        static let status = NSTouchBarItem.Identifier("com.prototype.MouseBridge.status")
    }

    let touchBar = NSTouchBar()
    var fileURLProvider: (() -> URL?)?
    var onModeChange: ((Bool) -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onDragLogEntry: ((String) -> Void)?
    private(set) var isEnabled = false
    private(set) var isFinderPromiseProbeEnabled = false

    private var edgeController: MouseBridgeEdgeController?
    private weak var physicalTouchBarView: NSView?
    private weak var cursorView: NSImageView?
    private weak var statusLabel: NSTextField?
    private weak var directFileButton: DirectTouchBarFileButton?
    private var buttons: [NSButton] = []
    private var hoveredButton: NSButton?
    private var bridgeWidth: CGFloat = 1085
    private var hasPhysicalTouchBarView = false

    override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [ItemID.a, ItemID.b, ItemID.c, ItemID.file, ItemID.status]
        touchBar.principalItemIdentifier = ItemID.status
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        onModeChange?(enabled)
        if enabled {
            presentResearchTouchBar()
        } else {
            tearDownResearchMode()
        }
    }

    func setFinderPromiseProbeEnabled(_ enabled: Bool) {
        isFinderPromiseProbeEnabled = enabled
        directFileButton?.useFilePromise = enabled
        logDrag(
            enabled
                ? "Finder File Promise Copy ON — writes source to Finder destination"
                : "Finder File Promise Copy OFF — URL drag mode"
        )
    }

    private func presentResearchTouchBar() {
        setStatus("MouseBridge enabled — move to screen bottom")
        for identifier in [ItemID.a, ItemID.b, ItemID.c, ItemID.file, ItemID.status] {
            _ = touchBar.item(forIdentifier: identifier)
        }
        refreshDirectFileButton()
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        NSTouchBar.presentSystemModalTouchBar(
            touchBar,
            placement: 1,
            systemTrayItemIdentifier: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.attachBridgeToPhysicalTouchBar()
        }
    }

    private func attachBridgeToPhysicalTouchBar() {
        guard isEnabled else { return }
        guard let parent = NSFunctionRow._topLevelViews().last else {
            setStatus("Private NSFunctionRow returned no Touch Bar view")
            return
        }
        physicalTouchBarView = parent
        hasPhysicalTouchBarView = parent.visibleRect.width > 100
        bridgeWidth = hasPhysicalTouchBarView ? parent.visibleRect.width : 1085
        edgeController?.closeBridge()
        edgeController = MouseBridgeEdgeController(width: bridgeWidth, delegate: self)
        setStatus(
            hasPhysicalTouchBarView
                ? "Physical MouseBridge ready"
                : "Desktop bridge routing simulation; no physical Touch Bar"
        )
    }

    private func tearDownResearchMode() {
        edgeController?.closeBridge()
        edgeController = nil
        removeCursor()
        clearHighlight()
        physicalTouchBarView = nil
        hasPhysicalTouchBarView = false
        NSTouchBar.dismissSystemModalTouchBar(touchBar)
        setStatus("MouseBridge disabled")
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        switch identifier {
        case ItemID.a, ItemID.b, ItemID.c:
            let title = identifier == ItemID.a ? "A" : (identifier == ItemID.b ? "B" : "C")
            let button = makeButton(title: title, tag: buttons.count)
            buttons.append(button)
            item.view = button
        case ItemID.file:
            let button = DirectTouchBarFileButton(frame: .zero)
            let url = researchFileURL
            button.title = url.lastPathComponent
            button.image = NSWorkspace.shared.icon(forFile: url.path)
            button.imagePosition = .imageLeading
            button.fileURL = url
            button.useFilePromise = isFinderPromiseProbeEnabled
            button.target = self
            button.action = #selector(testButtonPressed(_:))
            button.tag = 3
            button.onStatus = { [weak self] message in self?.setStatus(message) }
            button.onDragEvent = { [weak self] message in self?.logDrag(message) }
            constrain(button, width: 230)
            directFileButton = button
            buttons.append(button)
            item.view = button
        case ItemID.status:
            let label = NSTextField(labelWithString: "MouseBridge starting")
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.widthAnchor.constraint(equalToConstant: 390),
                label.heightAnchor.constraint(equalToConstant: 30)
            ])
            statusLabel = label
            item.view = label
        default:
            return nil
        }
        return item
    }

    private var researchFileURL: URL {
        fileURLProvider?()
            ?? Bundle.main.bundleURL
    }

    private func refreshDirectFileButton() {
        let url = researchFileURL
        directFileButton?.title = url.lastPathComponent
        directFileButton?.image = NSWorkspace.shared.icon(forFile: url.path)
        directFileButton?.fileURL = url
        directFileButton?.useFilePromise = isFinderPromiseProbeEnabled
    }

    private func makeButton(title: String, tag: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(testButtonPressed(_:)))
        button.tag = tag
        constrain(button, width: 105)
        return button
    }

    private func constrain(_ button: NSButton, width: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    @objc private func testButtonPressed(_ button: NSButton) {
        let name = button.tag == 3 ? "FILE \(researchFileURL.lastPathComponent)" : button.title
        setStatus("Clicked \(name)")
    }

    func bridgeMouseEntered(at x: CGFloat) {
        showCursor(at: x)
        updateHover(at: x)
    }

    func bridgeMouseMoved(to x: CGFloat) {
        showCursor(at: x)
        updateHover(at: x)
    }

    func bridgeMouseExited() {
        removeCursor()
        clearHighlight()
    }

    func bridgeMouseClicked(at x: CGFloat) {
        button(at: x)?.performClick(nil)
    }

    fileprivate func bridgeDragPayload(at x: CGFloat) -> BridgeDragPayload? {
        guard button(at: x)?.tag == 3 else { return nil }
        let url = researchFileURL
        return BridgeDragPayload(
            url: url,
            image: NSWorkspace.shared.icon(forFile: url.path),
            useFilePromise: isFinderPromiseProbeEnabled
        )
    }

    func bridgeDragStarted(url: URL) {
        logDrag("Drag Begin requested | route=MouseBridge URL=\(url.path)")
        setStatus("MouseBridge NSDraggingSession started: \(url.lastPathComponent)")
    }

    func bridgeDragEvent(_ message: String) {
        logDrag(message)
    }

    func bridgeDragEnded(url: URL, operation: NSDragOperation) {
        setStatus("MouseBridge drag ended operation=\(operation.rawValue)")
    }

    private func updateHover(at edgeX: CGFloat) {
        let target = button(at: edgeX)
        guard target !== hoveredButton else { return }
        clearHighlight()
        hoveredButton = target
        hoveredButton?.isHighlighted = true
        if let target {
            let name = target.tag == 3 ? "FILE" : target.title
            setStatus("Hover \(name)")
        }
    }

    private func clearHighlight() {
        hoveredButton?.isHighlighted = false
        hoveredButton = nil
    }

    private func button(at edgeX: CGFloat) -> NSButton? {
        guard let parent = physicalTouchBarView else { return nil }
        let sortedButtons = buttons.sorted { $0.tag < $1.tag }

        if hasPhysicalTouchBarView {
            let touchX = edgeX / max(bridgeWidth, 1) * max(parent.bounds.width, 1)
            let point = NSPoint(x: touchX, y: parent.bounds.midY)
            if let actual = sortedButtons.first(where: { button in
                guard let superview = button.superview else { return false }
                return superview.convert(button.frame, to: parent).contains(point)
            }) {
                return actual
            }
        }

        let interactiveWidth = max(bridgeWidth * 0.62, 1)
        guard edgeX >= 0, edgeX < interactiveWidth else { return nil }
        let index = min(Int(edgeX / (interactiveWidth / 4)), 3)
        return sortedButtons.indices.contains(index) ? sortedButtons[index] : nil
    }

    private func showCursor(at edgeX: CGFloat) {
        guard let parent = physicalTouchBarView else { return }
        let touchX = edgeX / max(bridgeWidth, 1) * max(parent.bounds.width, 1)
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
            x: min(max(touchX, 0), max(parent.bounds.width - cursor.frame.width, 0)),
            y: 6
        )
    }

    private func removeCursor() {
        cursorView?.removeFromSuperview()
        cursorView = nil
    }

    private func setStatus(_ message: String) {
        print("[MouseBridgeResearch] \(message)")
        statusLabel?.stringValue = message
        onStatusChange?(message)
    }

    private func logDrag(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let entry = "\(formatter.string(from: Date()))  \(message)"
        print("[Prototype9.DragBack] \(entry)")
        onDragLogEntry?(entry)
    }
}
