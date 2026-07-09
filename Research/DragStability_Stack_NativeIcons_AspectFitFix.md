# Drag Stability, Stack, Native Icons and Aspect-Fit Fix

## Scope

This change is deliberately limited to Shelf MouseBridge gesture state, Folder Stack creation, file image selection and DragOut preview geometry. AutoDrop, the 5px Overlay, FilePromise fulfillment, Menu Bar, Theme and Dock policy were not redesigned.

## 1. Drag stability

`ShelfMouseBridgeController.BridgeView` now locks `ShelfBridgeHit` at `mouseDown`. Later hover updates cannot change the source file.

- threshold: 5 physical pixels;
- movement below threshold remains a click;
- horizontal movement can arm an internal Stack target;
- upward movement, or leaving the virtual Touch Bar through its upper edge, starts external DragOut;
- MouseBridge does not collapse its panel while a mouse-down gesture is active;
- once `NSDraggingSession` begins, the source item and promise ID remain locked;
- cancellation keeps the source item;
- only successful FilePromise fulfillment invokes removal.

Drag start logging includes source item UUID, complete file URL and the resulting dragging pasteboard types. Drag end reports accepted/cancelled state and operation.

## 2. Drag one file onto another to create Stack

On the main Shelf only:

1. mouse-down locks source file A;
2. moving onto file B makes B a valid internal target;
3. B displays a 1.05 scale, stronger shadow and soft blue outline;
4. the target must remain armed for 0.35 seconds;
5. mouse-up creates a Stack containing B then A;
6. A and B are removed from the main Shelf in one model commit;
7. a 0.22-second merge transition finishes as the Stack card appears.

Dragging onto an existing Stack adds the source URL to it and removes the source from the main Shelf. Nested Stack creation from inside a Stack is rejected.

Required logs are emitted for `stack create source item`, `stack target item`, `stack add item`, `stack enter` and `stack back`.

## 3. Stack presentation and persistence

The Stack card uses the first entry's Quick Look thumbnail or Finder/macOS icon, with a layered-card treatment and count badge. It no longer substitutes a generic file-type symbol for the first file.

The Stack child Touch Bar includes Back, Stack name, child file scrubber and Close. Child files preserve existing click action menu, Remove and DragOut behavior. Successful FilePromise copy removes only that Stack entry.

Each Stack entry persists:

- stable UUID;
- original file URL;
- macOS bookmark data when bookmark generation succeeds.

No source file is copied into ShelfBar.

## 4. Native file icons and thumbnails

`FileShelfModel` no longer maps folders, PDFs, movies or archives to custom SF Symbol file icons.

- image and movie: public Quick Look thumbnail first;
- Quick Look failure: `NSWorkspace.shared.icon(forFile:)`;
- PDF, ZIP/archive, folder, app, regular and unknown file: `NSWorkspace.shared.icon(forFile:)`.

The newer `QuickLookThumbnailing` Swift module could not be imported with the installed Command Line Tools because the SDK module and Swift compiler have different Apple patch revisions. The implementation uses the older public `QLThumbnailImageCreate` API instead. It is deprecated as of macOS 15, but it is not private API and remains available for the 15.7 deployment target.

## 5. Aspect-fit DragOut preview

The old code always supplied a 38.2×38.2 dragging frame, which stretched every source image into a square.

The new DragOut image uses the source image's fitted dimensions:

- maximum width: 96;
- maximum height: 56;
- scale is capped at 1, so small images are not enlarged;
- width and height use the same scale factor;
- the dragging frame is centered on the pointer;
- no crop or aspect-fill is used.

Touch Bar item thumbnails retain their existing 48×28 maximum and proportional-down image view.

## Validation boundary

Completed on M5:

- arm64 and x86_64 typecheck;
- Universal Release compilation;
- model and persistence code review;
- bundle architecture, plist and ad-hoc signature checks;
- accessory/Menu Bar launch smoke.

Still requires Intel Touch Bar verification:

- 5px gesture threshold feel;
- 0.35-second target arming;
- physical hover outline and merge animation;
- file-to-file Stack creation;
- existing-Stack add;
- DragOut reliability and very-wide preview appearance.
