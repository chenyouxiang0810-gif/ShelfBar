# MouseBridge Research

## Scope and source snapshot

This report covers only the opt-in MouseBridge research branch. It does not change the normal AutoDrop shelf path.

- Pock: `ResearchSources/Pock`, commit `127aac1986e2dc5a3d6995ddbd35e19bf2f0c85a`
- PockKit: `ResearchSources/PockKit`, commit `335bc4c0edb4c9ad1beabe294f70cd39300dc577`
- Both repositories are retained as read-only research sources; no Pock source was modified.

## What Pock actually does

Pock does not inject a desktop mouse event into the Touch Bar daemon. It creates a thin desktop window at the bottom screen edge, maps that window's x coordinate into the real Touch Bar view, draws a cursor image inside that view, and manually forwards hover/click behavior to widget views.

### 1. Desktop mouse capture

`ResearchSources/PockKit/PockKit/Sources/Protocols/PKScreenEdgeController/PKScreenEdgeController.swift`

- `ScreenEdgeWindow` (lines 15–37) is a transparent, nonactivating `NSPanel` with mouse events enabled.
- `screenBottomEdgeRect` (lines 48–50) uses a 10-point-high bottom strip.
- `init` (lines 61–73) orders the panel front and positions it at the bottom edge.
- `updateTrackingArea()` (lines 91–100) installs `NSTrackingArea` with mouse-enter, exit, and move tracking.
- `mouseEntered`, `mouseMoved`, `mouseUp`, and `mouseExited` (lines 108–142) forward desktop events to a delegate.

These are public AppKit APIs.

### 2. Obtaining and decorating the physical Touch Bar view

`ResearchSources/Pock/Pock/UI/TouchBar/PockTouchBarController/PockTouchBarController.swift`

- `touchBarView` (lines 34–39) calls private `NSFunctionRow._topLevelViews()` and uses the last returned `NSView`.
- `parentView` (lines 41–46) exposes that physical Touch Bar view to `PKTouchBarMouseController`.
- `makeTouchBar()` / presentation code (lines 80–85) uses private system-modal Touch Bar presentation and presentation mode APIs.

`ResearchSources/PockKit/PockKit/Sources/Controllers/PKTouchBarMouseController.swift`

- `screenEdgeController` is created at lines 63–65.
- mouse entry and movement are mapped at lines 81–90.
- `addCursor()` and `moveCursor()` (lines 174–196) add `NSCursor.arrow.image` to `parentView` and move it horizontally.

Getting the physical Touch Bar top-level view is private API. Adding and moving an `NSImageView` is public AppKit once that private view has been obtained.

### 3. Hover and click routing

`ResearchSources/Pock/Pock/Extensions/NSView+Extensions.swift`

- `childView(at:)` (lines 36–50) converts descendant frames into the top view and performs custom x-coordinate hit testing at Touch Bar y = 12.

`ResearchSources/Pock/Pock/UI/TouchBar/EmptyTouchBarController/EmptyTouchBarController.swift`

- `mouseClickAtLocation` (lines 82–87) finds the mapped button and calls its action.
- `mouseMovedAtLocation` (lines 89–95) changes the mapped button highlight.
- `buttonAtLocation` (lines 97–101) searches an `NSTouchBarItemContainerView` for an `NSButton`.

`ResearchSources/Pock/Pock/UI/TouchBar/PockTouchBarController/PockTouchBarController.swift`

- controller callbacks at lines 174–206 forward entered, moved, clicked, and exited states to widgets.

Therefore the apparent Touch Bar mouse is synthetic UI state: Pock highlights a real Touch Bar subview and manually invokes the selected action. The physical Touch Bar is not a desktop `NSWindow`, and Pock is not making it receive ordinary mouse events.

## API inventory for the MouseBridge path

| Technology | Used? | Evidence and role |
|---|---:|---|
| DFRFoundation | Yes | `ApplePrivate.h` lines 64–68 declares DFR functions; private NSTouchBar presentation is used by `PockTouchBarController`. This presents/manages Touch Bar content, not desktop mouse routing. |
| NSFunctionRow | Yes | `PockTouchBarController.touchBarView` lines 34–39 calls `_topLevelViews()` to obtain the physical Touch Bar view. |
| DFRElement | Declared | `ApplePrivate.h` line 68 declares `DFRElementSetControlStripPresenceForIdentifier`. No call from the reviewed MouseBridge path was found. |
| Private selectors | Yes | `ApplePrivate.h` lines 36–61 declares private NSTouchBar and NSFunctionRow selectors. `TouchBarHelper.swift` lines 140–169 presents/dismisses system-modal bars. |
| Objective-C runtime/swizzling | Yes, outside core coordinate routing | `TouchBarHelper.swift` lines 177–223 uses class/method lookup and `method_exchangeImplementations` for NSFunctionRow behavior. |
| Event tap | No evidence | No `CGEvent.tapCreate` or equivalent event-tap implementation was found in the reviewed Pock/PockKit snapshot. |
| Accessibility / AXUIElement | No evidence | No `AXUIElement` use was found in the reviewed snapshot. |
| CGEvent injection | No evidence | No CGEvent mouse-event injection was found. |
| NSTouchBar item view hit testing | Yes | `NSView+Extensions.childView(at:)` and `EmptyTouchBarController.buttonAtLocation` map x position to Touch Bar item subviews. |
| Global NSEvent monitor | Unrelated use exists | `Utilities/HotKey.swift` line 24 monitors `.flagsChanged`; it is not the MouseBridge implementation. |

## Local MouseBridge prototype

Implementation: `TouchBarPrivateResearch/MouseBridgeResearchController.swift`.

The App window contains a `MouseBridge + DragOut Research` switch. It defaults to OFF and is not persisted. When enabled:

1. The normal AutoDrop monitor is stopped and its Touch Bar is dismissed.
2. A research-only system-modal Touch Bar displays `A`, `B`, `C`, `FILE`, and status text.
3. A 10-point transparent bottom-edge `NSPanel` tracks desktop mouse movement.
4. On Intel, private `NSFunctionRow._topLevelViews()` supplies the physical Touch Bar view. The controller maps the bottom-edge x coordinate into that view, adds a cursor image, finds item subviews, and updates button highlight.
5. A desktop click calls `NSButton.performClick`, so A/B/C update the status text.
6. Disabling the switch removes the edge window and research Touch Bar, then restores the AutoDrop monitor.

On an M5 without Touch Bar, NSFunctionRow provides no usable physical view. The implementation deliberately falls back to a coordinate-routing simulation so A/B/C and bridge drag logic can be tested without claiming physical Touch Bar success.

## Results

### Verified on M5

- Research mode can be enabled and disabled without modifying the persisted AutoDrop shelf.
- Bottom-edge x mapping selected and clicked A, B, and C in simulation.
- The FILE region started a desktop `NSDraggingSession` through the bridge path.

### Requires Intel Touch Bar

- Whether `NSFunctionRow._topLevelViews()` still returns the expected physical view on the target macOS build.
- Whether the cursor image is visible on the physical Touch Bar.
- Whether actual item view frames map correctly across the full Touch Bar.
- Whether A/B/C highlight and click reliably while Pock yields to the research system-modal bar.

## Public/private API conclusion

The desktop edge panel, tracking area, coordinate mapping, highlighting, `performClick`, and `NSDraggingSession` are public AppKit APIs. The behavior cannot be presented as an entirely public Touch Bar solution because obtaining the physical Touch Bar view and presenting a persistent system-modal bar use private NSFunctionRow/NSTouchBar/DFRFoundation APIs.

Primary risks are OS-version breakage, App Store rejection, changing private view hierarchy/class names, and conflict with other system-modal Touch Bar owners. No Accessibility permission, AX hack, event tap, or CGEvent injection was added.

