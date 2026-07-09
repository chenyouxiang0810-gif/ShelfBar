# Stack Stability, Drag Animation and Floating Shelf Button

## Backup

The project was backed up before source changes:

`/Users/seannb/ShelfBar_backup_before_stack_mousebridge_floating_button_20260707_200448`

Verification completed before editing:

- complete project copied with `ditto`;
- source files: 745;
- backup files: 745;
- Release `ShelfBar.app`, README and Research are present;
- source and backup README SHA-256 values matched.

## MouseBridge stability

`ShelfMouseBridgeController.present(mode:)` is now idempotent. A Touch Bar refresh no longer recreates the bridge panel when the same presentation is active.

Hit-region enumeration uses a 70ms debounce. If `BridgeView` reports an active mouse-down or external drag, the rebuild is deferred instead of clearing gesture state. Shelf and Stack mode changes first lay out the new Touch Bar hierarchy, then enumerate its item views.

The bridge log records:

- `bridge active`;
- `current mode`;
- `hitRegions count`;
- `hovered item id`;
- `active drag item id`;
- `last rebuild time`;
- rebuild/hover/drag reason.

The source item remains locked from mouse-down through drag-session end. Drag completion explicitly releases the gesture state and schedules one final debounced hit-region pass.

## Blank mouse-up action-menu fix

`BridgeView.mouseUp` performs a fresh hit test using the release coordinate. A click is dispatched only when the current hit ID matches the locked mouse-down hit ID.

Releasing on blank space:

- performs no action;
- clears hover;
- clears the pending gesture;
- logs `MouseBridge blank mouseUp ignored`.

The previous hovered item is never used as a click fallback.

## Stack first-frame and transition fix

Entering a Stack now resolves its entries into `currentStackItems` before `currentStackID` changes and before the child Touch Bar identifiers are installed. Data-source calls therefore use one stable snapshot rather than repeatedly rebuilding items from persistence.

Images and movies use an asynchronous Quick Look cache:

1. the native `NSWorkspace` Finder icon is returned immediately;
2. Quick Look generation runs outside the main thread;
3. completion updates the cached image;
4. only affected `NSScrubber` indexes reload;
5. hit regions rebuild after layout.

The full-bar alpha flash was removed. Enter, Back and model updates retain unchanged identifier arrays and coalesce scrubber reloads through the 70ms content-refresh debounce.

## Empty and single-item Stack behavior

`ShelfStackModel.removeFile` returns a normalization outcome in the same persistence commit:

- zero entries: remove Stack;
- one entry with Auto Dissolve ON: remove Stack and return the remaining URL;
- otherwise: keep Stack.

`PrivateTouchBarController` returns a dissolved remaining URL to the main Shelf. If the removed Stack was open, its model callback clears the Stack snapshot and returns the Touch Bar and app list to the main Shelf.

`ShelfBar.autoDissolveSingleItemStack` defaults to true and is exposed under Preferences > Shelf. Startup normalization removes legacy empty Stacks and, when enabled, dissolves persisted single-entry Stacks.

No original file is removed. Persistence still stores bookmark/URL references only.

## DragOut animation

The existing FilePromise copy path is unchanged. Animation surrounds it:

- start: source item scales to 1.06, opacity becomes 0.92 and shadow increases over 0.14s;
- success: source fades and scales to 0.84 over 0.18s, then the existing success callback removes it;
- cancellation/failure: source returns to scale 1.0, full opacity and no shadow over 0.18s; the model is not changed.

The dragging image continues to use the 96×56 maximum aspect-fit frame.

## Floating Shelf button

`FloatingShelfButtonController` owns a 58×58 borderless non-activating panel at floating window level. It uses the ShelfBar app image, translucent HUD material, continuous corners and a small shadow.

- click hides the panel and calls `presentSystemModal()`;
- drag moves the panel using screen coordinates and stores its clamped origin;
- right-click menu provides Show App, Hide Button and Quit ShelfBar;
- all-Spaces/full-screen auxiliary collection behavior is enabled;
- the bottom AutoDrop overlay remains at the higher main-menu window level.

`ShelfBar.showFloatingAfterClose` defaults to true. Only explicit user Close actions show the button; Clear, cancelled AutoDrop and app termination do not. Any later Shelf presentation, including AutoDrop, hides it.

## M5 validation

- arm64 and x86_64 typecheck;
- Universal Release compilation;
- project and app plist validation;
- ad-hoc signature verification;
- Preferences switches visible;
- Close Shelf produces the floating ShelfBar button;
- clicking the floating button hides it and calls Shelf presentation;
- Dock OFF, Auto theme and 5px Overlay delivery defaults restored after testing.

## Intel validation still required

- repeated MouseBridge entry/exit stability;
- first Stack entry rendering with multiple files;
- blank click does not open an action menu;
- empty and single-entry Stack return behavior;
- DragOut start/success/cancel animation on the physical Touch Bar;
- no regression in Finder FilePromise fulfillment or AutoDrop.
