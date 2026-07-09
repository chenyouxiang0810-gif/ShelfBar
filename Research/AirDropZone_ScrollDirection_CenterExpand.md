# AirDrop Zone, Scroll Direction and Center Expand

Date: 2026-07-09

## Backup

Before this change, the project was backed up to:

`/Users/seannb/ShelfBar_backup_before_airdrop_dropzone_scroll_direction_center_expand_20260709_103327`

The backup contains the full ShelfBar project folder, the current Release app, README and Research directory.

## Scope

This change is limited to UI/UX routing around:

- MouseBridge trackpad horizontal scroll direction;
- split Touch Bar Drop Bar with an AirDrop Drop Zone;
- Floating Button open animation;
- Preferences defaults and controls for the new behavior.

The following established paths were not rewritten: AutoDrop, Universal Drop payload parsing, MouseBridge drag decisions, Dock-like internal drag, Stack model, FilePromise copy fulfillment, menu bar mode, theme, Dock hidden mode, native icons and aspect-fit rendering.

## 1. Trackpad horizontal scroll direction

Files:

- `TouchBarPrivateResearch/ShelfMouseBridgeController.swift`
- `TouchBarPrivateResearch/PrivateTouchBarController.swift`

The previous MouseBridge scroll path sent raw `scrollingDeltaX` / Shift+vertical delta into `shelfMouseBridgeDidScroll(...)`. The controller converted that to content movement with:

`contentDelta = inverted ? rawDelta : -rawDelta`

This build reverses that mapping:

`contentDelta = inverted ? -rawDelta : rawDelta`

This only affects MouseBridge / trackpad scroll driving the Touch Bar Shelf or Stack scrubber. It does not change native finger scrolling directly on the physical Touch Bar.

Developer log now includes:

- raw `deltaX`;
- raw `deltaY`;
- applied horizontal delta;
- new scroll offset;
- current container id.

## 2. AirDrop Drop Zone

Files:

- `TouchBarPrivateResearch/FileDropEventRouting.swift`
- `TouchBarPrivateResearch/ScreenEdgeDropOverlayController.swift`
- `TouchBarPrivateResearch/TouchBarDropButton.swift`
- `TouchBarPrivateResearch/PrivateTouchBarController.swift`
- `TouchBarPrivateResearch/DebugWindowController.swift`

The Drop Bar is now split into:

- left 1/3: AirDrop;
- 8-point inactive gap;
- right 2/3: Drop your file here.

The bottom Overlay computes the active zone from the drag location:

- `x <= width / 3 - gap / 2`: `.airDrop`
- `x >= width / 3 + gap / 2`: `.shelf`
- between them: `.gap`

When the AirDrop Zone is disabled in Preferences > General, the overlay treats the full supported area as the Shelf drop zone.

### Shelf drop

Dropping on the Shelf zone keeps the existing Universal Drop behavior:

- inspect pasteboard;
- materialize non-file content to `~/Library/Application Support/ShelfBar/Items/`;
- add `ShelfImport` values to `FileShelfModel`;
- present / refresh the Shelf.

### AirDrop drop

Dropping on the AirDrop zone:

- inspects the same pasteboard;
- uses the parsed or materialized local file URLs from `ShelfImport.url`;
- does not add the items to the Shelf;
- calls `NSSharingService(named: NSSharingService.Name.sendViaAirDrop)?.perform(withItems:)`.

Developer log includes:

- `activeDropZone=airDrop / shelf / gap / none`;
- pasteboard types;
- AirDrop URLs;
- AirDrop success/failure.

Notes:

- `NSSharingService.perform(withItems:)` opens the system AirDrop sharing flow; it does not provide a synchronous "recipient accepted" result to this controller.
- If the service is unavailable, the app logs failure and dismisses/cancels cleanly.
- M5 cannot validate the physical Touch Bar split UI or AirDrop interaction on Intel Touch Bar hardware; Intel regression should verify active-zone highlighting and the AirDrop sheet.

## 3. Floating Button center-expand animation

Files:

- `TouchBarPrivateResearch/FloatingShelfButtonController.swift`
- `TouchBarPrivateResearch/AppDelegate.swift`
- `TouchBarPrivateResearch/PrivateTouchBarController.swift`
- `TouchBarPrivateResearch/DebugWindowController.swift`

Preferences > General adds:

- `Enable AirDrop Zone` default ON;
- `Floating Button Open Animation`: `Instant` or `Center Expand`, default `Center Expand`.

When Center Expand is enabled:

1. clicking the floating button sets a glow state;
2. the non-activating panel animates to the screen bottom-center with ease-in timing;
3. the circular button performs a short squash/bounce;
4. the floating panel fades out and restores its saved user position without writing the animation destination to defaults;
5. ShelfBar presents a compact centered Touch Bar pill;
6. the pill expands to a wider ShelfBar pill over 0.28 seconds;
7. the normal Shelf UI replaces the temporary pill.

The floating panel was enlarged to a transparent 96-point container around the circular vibrancy button so the glow and shadow are not clipped by a square edge.

### Touch Bar width-expand limitation

DFRFoundation system-modal Touch Bar does not expose a documented public animation API for item-width expansion. This build uses the closest controllable approach:

- a temporary centered `NSCustomTouchBarItem`;
- a custom `CenterExpandPillView`;
- an animating width constraint from compact to wide;
- replacement with the normal Shelf after the animation completes.

If Intel shows that the Touch Bar runtime snaps width changes instead of animating constraints smoothly, the fallback is still a visible centered compact state before normal Shelf presentation rather than a fake external screen animation.

## Build status

Built on M5 only. Intel physical Touch Bar behavior was not claimed as tested in this change.

Release target:

`build/Release/ShelfBar.app`

