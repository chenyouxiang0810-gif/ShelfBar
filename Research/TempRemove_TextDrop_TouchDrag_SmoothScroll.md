# Temp Remove, Text Drop, Touch Drag and Smooth Scroll

Date: 2026-07-08

## Backup

The mandatory pre-change backup is:

`/Users/seannb/ShelfBar_backup_before_remove_temp_items_touch_drag_scroll_smooth_20260708_222311`

It contains 751 files, including `build/Release/ShelfBar.app`, README and Research. Source and backup README SHA-256 were both `f6f0c83f8d3e01cbb5378c605382eeca7f840ef902ef8b0c8790cef1682d1d66`.

## Generated-file removal

Explicit item removal now reads persisted ownership metadata before changing the model:

- `localURL != nil && originalFileURL == nil`: remove the Shelf/Stack entry, then delete the ShelfBar-generated file;
- `originalFileURL != nil`: remove only the Shelf/Stack entry and keep the original file;
- legacy URL-only item with neither field: keep the file because ownership cannot be proven.

Moving an item during reorder, Stack creation or Stack add does not run this cleanup. Old URL-only persistence is now migrated as an original file reference, preventing an original PNG/JPEG/TXT from being mistaken for a generated temp file. Stack auto-dissolve preserves the complete item metadata rather than converting the remaining item back to a bare URL.

Developer logs use `remove shelf item`, `delete temp file success`, `delete temp file failed` and `keep original file`.

## Safari text versus URL

Non-file selection order in `FileDropReader` is:

1. file URL processing in `inspect`;
2. readable image;
3. explicit UTF-8/plain/legacy string text;
4. RTF or HTML;
5. non-file URL;
6. generic string fallback.

When explicit text and `public.url` coexist, text becomes TXT unless it is itself the same absolute URL or the advertised link name. The display name is a whitespace-normalized 18-character prefix plus `.txt`. URL title selection remains pasteboard-only; there is no network request.

An isolated `NSPasteboard` test verified:

- selected words + page URL -> `ShelfItemKind.text`, `.txt`;
- identical URL text + advertised URL -> `ShelfItemKind.url`, `.webloc`.

Logs include all pasteboard types, selected kind and the stored reason string.

## Stack ready timing

- file onto file: immediate soft highlight, ready after 0.55 seconds;
- file onto existing Stack: immediate soft highlight, ready after 0.35 seconds.

Changing or leaving the target cancels its work item. Mouse-up before ready performs only the calculated reorder; it does not create or add to a Stack.

## Physical Touch Bar item drag

Every `ShelfScrubberItemView` installs an `NSPressGestureRecognizer` with a 0.18-second press duration and 8-point allowable pre-recognition movement. This choice preserves quick native scrubber swipes while providing press-then-drag interaction on the physical Touch Bar.

After recognition, the item delegates to `ShelfMouseBridgeController`'s existing internal drag primitives:

- stable source ID and parent container;
- floating snapshot, shadow and placeholder;
- full physical Touch Bar X/Y point;
- shared insertion-index calculation;
- shared file/Stack target validation and ready delays;
- shared reorder, Stack create and Stack add delegate methods;
- cancellation cleanup.

The same reusable item view is used by root, Stack and nested Stack scrubbers. Hit-region rebuild attachment is deferred while a direct-touch session is active.

## Smoother displacement

The floating card still follows every pointer/finger update. Neighbor cards now update only when the source or insertion index changes. Each item remembers its current shift and ignores identical assignments. New gaps use a 0.15-second ease-out transition, eliminating repeated animation restarts from every mouse-moved event. Target hover changes do not rebuild the Touch Bar data source.

## Mouse and trackpad horizontal scroll

`BridgeView.scrollWheel` accepts:

- trackpad horizontal `scrollingDeltaX`;
- Shift + vertical mouse-wheel delta.

Scroll is ignored during an active mouse or direct-touch item drag. Otherwise ShelfBar finds the current scrubber's `NSScrollView`, clamps and updates its horizontal content offset, and logs delta, resulting offset and current container ID. If AppKit does not expose the scrubber's internal scroll view, it uses the public `scrollItem(at:to:)` API with a maintained logical offset. The desktop Shelf Preview receives the same offset.

## Verification

- arm64 Swift typecheck: passed.
- x86_64 Swift typecheck: passed.
- isolated pasteboard routing test: passed.
- Universal Release build: passed; `lipo -archs` reports `x86_64 arm64`.
- `codesign --verify --deep --strict`: passed.
- Release `Info.plist` validation: passed.
- Existing public Quick Look deprecation warning remains unchanged.

Physical Touch Bar gesture arbitration and trackpad scroll direction were not claimed as Intel-tested on the M5. Intel regression should verify quick finger swipe versus 0.18-second hold, root/nested reorder, both ready timers, cancellation, trackpad natural direction, Shift-wheel direction, and unchanged MouseBridge/FilePromise behavior.
