# Center Expand Timing and AirDrop Active-State Fix

Date: 2026-07-09

## Backup

Before this change, the project was backed up to:

`/Users/seannb/ShelfBar_backup_before_center_expand_timing_airdrop_active_20260709_110633`

The backup contains the complete ShelfBar project folder, the current Release app bundle, README and Research directory.

## Scope

This is a focused UI/UX fix. It does not change:

- AutoDrop payload handling;
- Universal Drop reader priority;
- AirDrop sharing API;
- MouseBridge drag / scroll architecture;
- Stack logic;
- DragOut / FilePromise;
- menu bar, theme or Dock-hidden behavior;
- Floating Button saved position.

## 1. Removed the branded preflight pill

File:

- `TouchBarPrivateResearch/PrivateTouchBarController.swift`

The previous temporary Touch Bar view displayed an icon and `ShelfBar` text during Center Expand. That caused a visible preflight state before the actual Shelf appeared.

This build changes `CenterExpandPillView` to an empty pill:

- no `ShelfBar` text;
- no drawer icon;
- initial width: 34 points;
- height: 30 points;
- rounded accent-tinted pill only.

The Touch Bar is not presented until the Floating Button finishes its screen flight and bounce. After that, only the small empty center pill appears and expands.

## 2. Floating Button flight timing

File:

- `TouchBarPrivateResearch/FloatingShelfButtonController.swift`

The Center Expand flight now uses:

- duration: 1.0 second;
- timing: ease-in;
- effect: slow start, accelerating toward bottom-center;
- glow remains on during flight;
- bounce/squash total: about 0.20 seconds.

The floating panel remains a larger transparent 96-point container around the circular button, so the glow/shadow are not clipped by a square boundary. The animated bottom-center position is temporary and is not persisted.

## 3. Touch Bar expansion timing and item fade

File:

- `TouchBarPrivateResearch/PrivateTouchBarController.swift`

After the Floating Button reaches bottom-center:

1. ShelfBar presents a temporary empty `CenterExpandPillView`.
2. The pill width animates from 34 points to 520 points.
3. Expansion duration is 1.0 second.
4. Timing is ease-out.
5. After expansion, the normal Shelf UI replaces the temporary item.
6. Visible Shelf item views fade in from left to right with a 40 ms cascade and 0.16-second fade duration per item.

This is still a private Touch Bar approximation. DFRFoundation does not expose a stable documented API for system-modal Touch Bar item-width animation, so the implementation uses an animating `NSCustomTouchBarItem` view constraint, then switches to the real Shelf.

## 4. AirDrop active-state fix

Files:

- `TouchBarPrivateResearch/FileDropEventRouting.swift`
- `TouchBarPrivateResearch/ScreenEdgeDropOverlayController.swift`
- `TouchBarPrivateResearch/TouchBarDropButton.swift`
- `TouchBarPrivateResearch/PrivateTouchBarController.swift`

The previous version logged active zone changes but could leave the visible Touch Bar Drop Bar unchanged because NSTouchBar can keep the existing item view cached.

This build fixes that by making `TouchBarDropButton` stateful:

- `applyActiveZone(_:)` updates the existing Drop Bar view in place;
- AirDrop active state brightens the left zone and scales the AirDrop icon to 1.08;
- Shelf active state brightens the right zone and scales the drawer icon to 1.05;
- gap / none returns both zones to normal.

The Overlay now sends a `ShelfDropZoneSnapshot` containing:

- active zone;
- drag location x;
- AirDrop rect;
- Shelf rect;
- gap rect.

Developer log includes:

- `activeDropZone`;
- `drag location x`;
- `airDrop rect`;
- `shelf rect`;
- `gap rect`;
- `UI active zone applied`.

## Intel verification needed

M5 can compile and validate the AppKit code paths, but these UI behaviors still need Intel Touch Bar verification:

- Floating Button 1.0-second ease-in flight feel;
- empty center pill appears only after the button reaches bottom-center;
- Touch Bar 1.0-second pill expansion is visible on DFRFoundation hardware;
- Shelf item cascade appears after expansion rather than before it;
- AirDrop/Shelf/gap active state matches drag position on the bottom Overlay.

