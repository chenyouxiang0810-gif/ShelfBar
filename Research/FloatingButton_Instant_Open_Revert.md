# Floating Button Instant Open Revert

Date: 2026-07-09

## Scope

This is a focused UX change. It disables the Center Expand / flying orb opening effect and restores a direct floating-button open flow.

No changes were made to:

- AutoDrop;
- Universal Drop;
- AirDrop perform API;
- MouseBridge;
- Stack;
- DragOut;
- FilePromise;
- menu bar mode;
- theme;
- Dock hidden mode;
- Floating Button saved position.

## Behavior

Clicking the Floating Button now:

1. fades the Floating Button panel out;
2. hides the panel;
3. presents the normal Touch Bar Shelf directly.

It no longer:

- flies to bottom-center;
- shows a glowing launch animation;
- shows a temporary empty Touch Bar pill;
- expands a pill;
- performs item cascade fade.

## Implementation

Files:

- `TouchBarPrivateResearch/AppDelegate.swift`
- `TouchBarPrivateResearch/FloatingShelfButtonController.swift`
- `TouchBarPrivateResearch/DebugWindowController.swift`
- `README.md`

`FloatingShelfButtonController.presentShelf()` now forces `ShelfBar.floatingOpenAnimation` to `instant` and calls the existing instant fade-out path.

`AppDelegate` now routes Floating Button presentation directly to `presentSystemModal()` regardless of any older saved `centerExpand` preference value.

Preferences now exposes only `Instant` for Floating Button open behavior.

## Build

Release target:

`build/Release/ShelfBar.app`

