# Universal Drop and Dock-like Drag

Date: 2026-07-08

## Scope and backup

This change extends the existing ShelfBar implementation without replacing AutoDrop, MouseBridge, FilePromise, menu bar, theme, Dock-hidden mode, floating button, native icons or aspect-fit rendering.

The mandatory pre-change backup is:

`/Users/seannb/ShelfBar_backup_before_universal_drop_and_docklike_drag_20260708_214610`

It contains 748 files. The source and backup README SHA-256 at backup time were both `77eeb4ffb986eef377566c995fd00110788f95d78126c8ce4d99db01961bdb`.

## Universal Drop

`FileDropEventRouting.swift` registers and inspects:

- files: `public.file-url` / `.fileURL`, `NSURLPboardType`, `NSFilenamesPboardType`;
- images: `public.image`, `public.png`, `public.jpeg`, TIFF and `NSImage(pasteboard:)`;
- links: `public.url`, `NSURLPboardType`, and URL strings;
- text: `public.utf8-plain-text`, `public.plain-text`, `.string`, `NSStringPboardType`;
- rich content: `public.rtf`, `public.html`.

The Overlay returns `.copy` only when at least one registered type is advertised. Unsupported drags return `[]`, so they do not present or intercept ShelfBar.

Real file URLs remain references to their original files. Non-file payloads are written atomically under:

`~/Library/Application Support/ShelfBar/Items/`

Images become PNG, text becomes TXT, links become WEBLOC, and rich content becomes RTF or HTML. URL display names use pasteboard `public.url-name`, then host, then the URL string; no network title request is made.

`FileShelfItem` now records a stable ID, display name, `ShelfItemKind`, pasteboard source description, optional original file URL, optional generated local URL, and display image. Version-3 JSON persistence keeps that metadata and still writes the previous URL list for compatibility. Existing v2 URL persistence is migrated on load.

All accepted items ultimately point to a real file URL. The established `NSFilePromiseProvider` therefore copies original files or ShelfBar-generated files through the same fulfillment path.

## Dock-like internal drag engine

`ShelfMouseBridgeController.BridgeView` locks the mouse-down hit and starts no action until movement exceeds 5 physical pixels. Movement that remains inside the virtual Touch Bar enters internal mode:

1. ShelfBar snapshots the source card.
2. A floating `NSImageView` is added above the physical Touch Bar at z-position 1000.
3. It follows the full virtual X/Y point at 1.06 scale, 0.94 opacity and increased shadow.
4. The source view fades to 0.20 as a stable placeholder.
5. The floating X position is compared with visible card midpoints to obtain `insertionIndex`.
6. Intervening cards translate 18 points with a 0.14-second ease-in/out animation.
7. Mouse-up outside an armed target persists the reorder through `FileShelfModel.move` or `ShelfStackModel.moveFile`.

No data-source rebuild occurs for each mouse move. Existing 70ms content refresh coalescing remains, and physical Touch Bar hit-region attachment defers while `BridgeView.hasActiveGesture` is true.

Moving upward switches from internal mode to the existing external drag implementation. The floating snapshot and placeholder are removed first, then the unchanged FilePromise session begins.

## Stack target timing

The target is identified by the existing full-rectangle MouseBridge hit test, not X-only hit testing.

- File target: soft highlight immediately; ready after continuous 2.0-second hover.
- Existing Stack target: soft highlight immediately; ready after continuous 0.6-second hover.
- Moving to a different target cancels the old work item and resets its ready state.
- Ready state uses a stronger blue border/glow and emits a `stack ready` log.
- Releasing before the delay commits only the calculated reorder.

After the delay, file-to-file drop creates a Stack; file-to-Stack drop adds to that Stack and removes the source from its original container.

## Nested Stack persistence and navigation

`ShelfStack` now has an optional `parentStackID`. Existing persisted Stacks decode as roots because the field is optional. Entries also retain kind, display name, source description, original URL and local URL in addition to bookmark/URL fallback.

Merging files inside a Stack creates a child Stack with the current Stack as parent. The UI renders the current Stack's files and direct child Stacks. `stackNavigationPath` pushes on entry and pops on Back, so nested navigation returns to the actual parent.

The same file interactions work at every level: reorder, merge into another child Stack, add to an existing child Stack, Open, Remove and external DragOut. Successful external copy removes the file from its current container. Auto-dissolve is disabled specifically for that success path so a one-item parent Stack remains; an empty Stack is still removed.

## Developer logs

Logs include pasteboard types, detected kinds, generated local paths, locked source ID/index, parent container, insertion index, hovered target, ready delay/state, stack create/add, reorder, external operation result and FilePromise success/cancellation.

## Verification

- arm64 Swift typecheck: passed.
- x86_64 Swift typecheck: passed.
- Only the existing public `QLThumbnailImageCreate` deprecation warning remains.
- Universal Release build: passed; `lipo -archs` reports `x86_64 arm64`.
- Bundle validation: `plutil -lint` passed and ad-hoc `codesign --verify --deep --strict` passed.

Physical Touch Bar behavior was not claimed as tested on the M5. Intel verification should cover image/text/link drags from representative apps, continuous internal dragging, the 2.0/0.6-second target timing, nested navigation, reordering, cancellation and the preserved Finder FilePromise path.

## Known boundaries

- One non-file representation is materialized per drop operation; multi-file URL drops remain fully supported.
- Universal Drop depends on what the source app publishes to the macOS drag pasteboard. An app advertising no supported/readable representation is rejected.
- Generated files are intentionally retained because Shelf persistence and later DragOut reference them. Shelf removal does not currently garbage-collect the generated file.
- Nested child Stacks are rendered after direct file entries in each container. Direct files can be freely reordered; Stack container ordering is not independently user-sortable in this version.
