import AppKit

@MainActor
final class FinderDragMonitor {
    private let overlayController: ScreenEdgeDropOverlayController
    var onFileDragDetected: (() -> Void)?
    var onFileDragEnded: (() -> Void)?
    private var globalMonitor: Any?
    private var isDragging = false
    private var lastObservedPasteboardChangeCount = 0

    init(overlayController: ScreenEdgeDropOverlayController) {
        self.overlayController = overlayController
    }

    func start() {
        guard globalMonitor == nil else { return }
        lastObservedPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = nil
        isDragging = false
        overlayController.hideOverlayImmediately()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            isDragging = false
        case .leftMouseDragged:
            let dragPasteboard = NSPasteboard(name: .drag)
            let pasteboardChanged = dragPasteboard.changeCount
                != lastObservedPasteboardChangeCount
            let hasSupportedPayload = FileDropReader.supports(dragPasteboard)
            guard overlayController.isEnabled,
                  hasSupportedPayload,
                  (isDragging || pasteboardChanged)
            else { return }
            if !isDragging {
                onFileDragDetected?()
            }
            isDragging = true
            lastObservedPasteboardChangeCount = dragPasteboard.changeCount
            overlayController.showOverlayForFinderDrag()
        case .leftMouseUp:
            if isDragging {
                overlayController.scheduleHide()
                onFileDragEnded?()
            }
            lastObservedPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
            isDragging = false
        default:
            break
        }
    }
}
