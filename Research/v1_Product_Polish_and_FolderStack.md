# ShelfBar v1.0 Product Polish and Folder Stack

## Backup

Mandatory backup completed before edits:

`/Users/seannb/ShelfBar_backup_before_v1_product_polish_and_folder_stack_20260707_010016`

Verification:

- complete project copied with `ditto`;
- source files: 739;
- backup files: 739;
- README SHA-256 matched: `79d5d93d7a87e9119dfe6599ce56f99cf7af14bd218e5c6a9b0a073d12012e5a`;
- Research directory: 20 files;
- both prior Release bundles were present in the backup.

## Menu Bar product mode

`AppDelegate` reads `ShelfBar.showInDock`, which defaults to false.

- false: `NSApplication.ActivationPolicy.accessory`, no launch window, status item remains active, closing preferences does not terminate the app;
- true: `.regular`, Dock/Cmd+Tab return and the preferences window opens.

`MenuBarController` owns the `NSStatusItem` and transient `NSPopover`. Its template image is drawn as a monochrome file stack above a Touch Bar bar. Popover actions are Present Shelf, Overlay, Theme, Open ShelfBar, Preferences and Quit.

The policy change applies immediately, so no restart prompt is necessary in this implementation.

## Preferences and Theme

Preferences tabs are General, Appearance, Shelf and Developer. Developer is absent by default and is revealed only by the General `Show Developer Tab` switch. Research and prototype controls remain hidden until `Enable Developer Tools` is also on.

Theme persists as `ShelfBar.theme`:

- Auto (default)
- Light
- Dark

Sidebar, window, cards, toolbar, buttons, table, About and Dock icon update immediately. Approved light/dark logo files are used directly.

## Touch Bar polish

Only the approved Apple-minimal style was implemented:

- 30pt control height;
- 8pt scrubber spacing;
- proportional image thumbnails;
- folder, movie, archive and PDF-oriented SF Symbols;
- 0.32-alpha blue hover;
- 0.96 pressed scale;
- 1.06 drag image scale;
- soft accent Drop glow;
- Trash symbol for REMOVE;
- title-cased empty-state copy.

No B/C visual variants exist.

## Folder Stack model

New `ShelfStackModel` stores Codable arrays under `ShelfBar.folderStacks.v1`:

- Stack UUID;
- name;
- stable entry UUID;
- file URL string.

No file content is copied. Create, rename, remove, add URL and remove entry all commit immediately to UserDefaults.

## Touch Bar Stack routing

The main scrubber data source combines normal `FileShelfItem` values followed by `ShelfStack` values. Stack cards use `square.stack.3d.up.fill`, display their name and a count badge.

MouseBridge changes are narrow:

- `ShelfBridgeHit` may identify a file or Stack;
- starting on a file and releasing horizontally on a Stack moves that URL into the Stack;
- upward movement still enters the existing FilePromise DragOut path;
- clicking a Stack enters the Stack child view.

The Stack child view reuses the shelf scrubber and existing action-menu bridge. It adds only a Back item. OPEN / REMOVE / BACK work on stable Stack entry IDs. FilePromise success removes the entry from its owning Stack; cancellation/failure keeps it.

## Desktop Stack UI

The Shelf Preview includes Stack cards and counts. New Stack creates a persistent stack. Clicking a Stack changes Current Files to the Stack contents and exposes Back, Rename and Remove Stack. Table metadata remains Thumbnail, Name, Kind, Size and Path.

## Validation completed on M5

- backup integrity checks;
- arm64 and x86_64 typecheck;
- Universal Release compilation;
- menu-bar-only process launches with no key window when Dock is off;
- Dock-on preferences launch;
- Developer tab hidden by default;
- create Stack UI;
- Stack card/count and desktop child view;
- Stack persistence across process restart;
- Light/Dark/Auto UI and logos;
- codesign and launch smoke.

## Intel validation still required

- physical Touch Bar Stack card/count layout;
- MouseBridge horizontal file-to-Stack drop and highlight;
- Stack child Back hit region;
- Stack child action menu;
- Stack child DragOut and remove-on-success;
- regression of main Shelf DragOut, AutoDrop and Y-axis behavior.

## Known public/private API boundary

The physical Touch Bar does not receive Finder drag-destination callbacks in the prior Intel tests. Therefore external Finder files still enter through the bottom Overlay. The new direct Stack drop means an internal MouseBridge move from an existing main-Shelf file to a Stack; it does not claim that Finder can drop directly onto the Touch Bar Stack.
