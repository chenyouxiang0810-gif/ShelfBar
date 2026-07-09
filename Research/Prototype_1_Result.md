# Prototype 1 Result — HELLO + TEST

## Scope

Only tests creation and private system-modal presentation of an `NSTouchBar` containing:

1. `HELLO` label
2. `TEST` button

No File Shelf and no Finder drag code exists in this Prototype.

## Implementation

- Public content construction: `TouchBarPrivateResearch/PrivateTouchBarController.swift`
- Private declarations: `TouchBarPrivateResearch/PrivateTouchBarAPI.h`
- Private framework link: `TouchBarPrivateResearch.xcodeproj/project.pbxproj`
- Entry point: `TouchBarPrivateResearch/main.swift`

Call path:

1. Construct public `NSTouchBar` and two `NSCustomTouchBarItem` objects.
2. Call `DFRSystemModalShowsCloseBoxWhenFrontMost(false)` from DFRFoundation.
3. Call private `NSTouchBar.presentSystemModalTouchBar(... placement: 1 ...)`.
4. On termination, call private `dismissSystemModalTouchBar`.

## Verification performed on M5

- arm64 type check: passed.
- x86_64 type check with macOS 15.7 target: passed.
- arm64 link against private DFRFoundation: passed.
- Xcode project plist syntax: passed.
- App bundle launched on M5: passed.
- Log immediately before private presentation call: reached.
- Private presentation call returned without exception/crash.
- Normal Apple-event quit invoked `applicationWillTerminate`.
- Private dismissal call returned without exception/crash.

Observed log:

```text
[TouchBarPrivateResearch] About to call private system-modal presentation.
[TouchBarPrivateResearch] Called private system-modal presentation. Hardware visibility is unverified.
[TouchBarPrivateResearch] About to call private system-modal dismissal.
[TouchBarPrivateResearch] Called private system-modal dismissal.
```

## Intel hardware follow-up

The user subsequently confirmed that Prototype 1 displayed `HELLO` and `TEST` successfully on an Intel Mac with a physical Touch Bar. This upgrades system-modal presentation from unverified to hardware-confirmed. Prototype 1 did not yet establish the complete dynamic counter/CLEAR/timer behavior introduced in Prototype 2.

## Result classification

**Successful for system-modal presentation.**

The private symbols resolve, the program links, and both presentation/dismissal calls return on the M5. Because this Mac has no Touch Bar, this does not prove that `HELLO` and `TEST` were rendered, nor that `TEST` receives touch input.

The original M5 run could not verify hardware output; the later Intel result was provided by the user rather than executed in this workspace.

## Stop boundary

Prototype 1 is complete. Its system-modal result is the basis for the separate dynamic-update Prototype 2.
