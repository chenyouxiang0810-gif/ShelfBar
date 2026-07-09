# Prototype 7 — MouseBridge Drag Out

## Goal

Test two distinct routes for exporting one file from Touch Bar UI without long press:

1. **Direct route:** an `NSPanGestureRecognizer` on the Touch Bar file button attempts to start `NSDraggingSession`.
2. **MouseBridge route:** pressing the mapped FILE region in the desktop bottom-edge window and dragging upward starts `NSDraggingSession` at desktop coordinates.

No drag-out behavior was added to the normal AutoDrop shelf. Both routes exist only while the research switch is ON.

## Implementation

`TouchBarPrivateResearch/MouseBridgeResearchController.swift`

- `ResearchFilePasteboardWriter` supplies the first shelf URL, or the running App bundle URL as an always-existing fallback when the shelf is empty.
- It declares/writes:
  - `.fileURL` (`public.file-url`)
  - `.URL`, which is the current Swift/AppKit replacement for unavailable `NSURLPboardType`
  - literal `NSFilenamesPboardType` for legacy consumers
- `DirectTouchBarFileButton` owns the direct pan gesture and calls `beginDraggingSession` only if AppKit supplies a desktop `.leftMouseDragged` event and a window.
- `MouseBridgeEdgeController.EdgeView` is an `NSDraggingSource`; dragging upward from the mapped FILE zone creates an `NSDraggingItem` and starts a copy session.

The fallback is not a separate on-screen drag handle. The same invisible research bottom-edge bridge that controls hover/click is the drag source.

## Pasteboard result on M5

The MouseBridge route started a real AppKit drag session. Inspection of `NSPasteboard(name: .drag).types` included:

- `public.file-url`
- `public.url`
- Apple's URL pasteboard flavor emitted for `.URL`
- literal `NSFilenamesPboardType`

An explicit M5 pasteboard test also attempted literal `NSPasteboard.PasteboardType("NSURLPboardType")`. AppKit logged that it is not a valid UTI, did not retain that literal type, and returned nil when it was read back. The `NSURLPboardType` symbol itself is unavailable in current Swift and the SDK directs callers to `.URL`; `.URL` produced `public.url` plus Apple's URL pasteboard flavor. Therefore the prototype uses that supported replacement and does **not** claim that a literal `NSURLPboardType` entry exists.

Literal `NSFilenamesPboardType` was retained and read back as a filename array, although AppKit still logs an invalid-UTI warning for it. `.fileURL` remains the correct modern representation.

## Results

### MouseBridge route — successful on M5

- Pressing FILE in the bottom-edge research region and moving upward called `beginDraggingSession`.
- The drag operation advertised `.copy`.
- The drag pasteboard contained the URL and legacy filename representations listed above.

This verifies that a desktop bridge view can become the real `NSDraggingSource`. It does not yet prove acceptance by every target app; Finder/Desktop, LINE, Discord, and Mail must each be checked on an Intel machine because destination acceptance depends on their pasteboard handling.

### Direct Touch Bar route — Intel result pending

The direct route cannot be exercised on an M5 without a physical Touch Bar. It is intentionally guarded and reports a clear failure if the Touch Bar gesture does not provide a desktop `.leftMouseDragged` event or usable window.

If direct drag fails on Intel, the concrete boundary is event routing: a Touch Bar interaction is delivered by the DFR/system-modal Touch Bar path, while `NSView.beginDraggingSession` expects a desktop AppKit drag event and desktop window coordinate context. A Touch Bar pan gesture alone does not establish that such an event/session exists. This statement is a test criterion, not a claim that Intel has already failed.

## Intel test procedure

1. Launch the Release App and enable `MouseBridge + DragOut Research`.
2. Confirm A/B/C/FILE and status appear on the physical Touch Bar.
3. Move the desktop pointer into the screen bottom edge and verify Touch Bar hover/highlight follows it.
4. Click A, B, and C; verify the Touch Bar and App window status changes.
5. Select FILE and attempt a physical Touch Bar pan upward. Record whether `Direct Touch Bar NSDraggingSession started` appears.
6. From the desktop bottom edge, press in the FILE-mapped region and drag upward into Finder/Desktop, LINE, Discord, and Mail.
7. Verify the destination receives the original file URL/file, not copied text.

## Intel result fields

- Physical cursor visible: **Pending**
- A/B/C hover: **Pending**
- A/B/C click: **Pending**
- Direct Touch Bar drag session: **Pending**
- MouseBridge drag to Finder/Desktop: **Pending**
- MouseBridge drag to LINE: **Pending**
- MouseBridge drag to Discord: **Pending**
- MouseBridge drag to Mail: **Pending**

## Conclusion

MouseBridge drag-out is technically feasible as a desktop AppKit drag source and has passed M5 session/pasteboard validation. Direct drag from a physical Touch Bar item remains unverified and must not be reported as successful until Intel testing. No long press, animation, Accessibility hack, CGEvent injection, or standalone screen drag handle is used.
