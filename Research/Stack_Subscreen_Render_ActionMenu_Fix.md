# Stack Subscreen Render and Action Menu Fix

## Scope

This change is limited to Stack child-view construction, click validation logging and file action-menu presentation. MouseBridge coordinate mapping and drag decisions, DragOut, FilePromise, AutoDrop, Menu Bar, Theme, Dock policy and the floating button are unchanged.

## Root cause

The main Shelf and Stack child screen both used `ItemID.shelf`. `NSTouchBar` caches custom items by identifier, so the first Stack entry could reuse the already-created main Shelf `NSScrubber`. The Stack model had entries, but the expected Stack view/data lifecycle had not been forced before hit testing.

The prior `currentStackItems` snapshot also made it possible for render code to observe an older copy instead of the latest persisted Stack entries.

## Stack render fix

`PrivateTouchBarController.ItemID.stackShelf` is a dedicated custom Touch Bar identifier. Stack screens use it as both the visible scrubber item and principal item.

On `enterStack(id:)`:

1. validate and read the latest `ShelfStack` directly from `ShelfStackModel`;
2. log `enter stack id` and `stack item count`;
3. clear prior rendered-item tracking;
4. install Stack-specific Touch Bar identifiers;
5. after the existing 70ms layout debounce, create/reload the Stack scrubber;
6. visit each model index to force its item view to be requested;
7. restore item zero to leading alignment;
8. log `rendered stack item count` and every rendered filename.

If the model count is positive while rendered count is zero, ShelfBar emits:

`ERROR stack item count > 0 but rendered stack item count = 0`

The data-source count and per-index item creation now read the current Stack model rather than a long-lived child-screen cache.

## Thumbnail placeholder and local update

The existing asynchronous Quick Look cache remains unchanged:

- initial item: `NSWorkspace.shared.icon(forFile:)` native placeholder;
- image/movie thumbnail generation: background Quick Look request;
- completion: `reloadItems(at:)` for only matching Stack indexes;
- no full child-screen rebuild.

## Blank click fix

The existing MouseBridge mouse-up validation remains structurally unchanged. It performs a new hit test at the current virtual X/Y and dispatches a click only when the release hit ID equals the locked mouse-down hit ID.

This update adds explicit evidence logs:

- `click point=(x, y)`;
- `hit item id=<uuid>` or `nil`;
- `action menu opened item id=<uuid>`.

Blank mouse-up clears hover, logs the ignored click and does not use a prior hovered or selected item.

## Action menu icon

The file action screen now contains:

- 42×28 icon view using proportional-down/aspect-fit scaling;
- filename;
- OPEN;
- DRAG OUT;
- REMOVE;
- BACK.

The icon uses the selected item's existing display image rules: Quick Look for images/movies when ready, otherwise `NSWorkspace.shared.icon(forFile:)`. Thumbnail completion updates only the operation icon view.

DRAG OUT exits the action screen back to the exact item so the existing upward MouseBridge/FilePromise gesture can be used without modifying DragOut internals.

## Empty Stack

The existing atomic Stack removal outcome is retained. Removing or successfully dragging out the last entry deletes the Stack, saves persistence, clears an open Stack screen and returns to the main Shelf. Existing one-item dissolve preference behavior is unchanged.

## Validation boundary

Completed on M5:

- arm64 and x86_64 typecheck;
- Universal Release build;
- project/app plist validation;
- code-sign verification;
- accessory/Menu Bar launch smoke.

Intel validation still required:

- first Stack entry shows every expected visible file item;
- render logs match the model count;
- blank Touch Bar click never opens an action screen;
- action icon appearance and action-button MouseBridge hit regions;
- no regression in Stack DragOut/FilePromise.
