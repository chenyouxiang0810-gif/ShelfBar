# App Bundle, Icon and Finder Forbidden Badge Fix

Date: 2026-07-09

## Scope

This pass only touched Release packaging, icon resources, code signing, quarantine cleanup and LaunchServices registration.

No app functionality was changed:

- AutoDrop unchanged
- Universal Drop unchanged
- AirDrop unchanged
- MouseBridge unchanged
- Stack unchanged
- FilePromise unchanged
- UI animation logic unchanged

## Observed problem

Finder sometimes showed a prohibited / forbidden badge on `ShelfBar.app` immediately after the app was copied or appeared in Finder. Opening **Show Package Contents** and returning to the parent folder caused the badge to disappear.

That pattern is consistent with a Finder / LaunchServices bundle metadata refresh issue rather than an executable failure: the app launched and worked, but Finder initially did not have clean or current metadata for the bundle.

## Likely causes found

The previous Release app had these issues:

1. Some copied PNG resources inside `ShelfBar.app/Contents/Resources` carried `com.apple.quarantine`.
2. The Release app was being updated in place, leaving Finder / LaunchServices room to show stale app metadata or stale icon state.
3. Finder had to rediscover the app bundle after the user opened package contents, which explains why the badge disappeared after manual inspection.
4. The app is ad-hoc signed. `codesign` validates it, but `spctl` rejects it because it is not Developer ID signed/notarized. This does not by itself prove the Finder icon badge cause, but it is relevant for distribution.

`LSUIElement` was not present in `Info.plist`; the app's runtime Dock-hidden behavior is controlled by activation policy and should not cause Finder's prohibited icon badge.

## Changes made

### 1. Clean bundle rebuild

The old `build/Release/ShelfBar.app` is removed before rebuilding.

The bundle is recreated with:

- `Contents/Info.plist`
- `Contents/MacOS/ShelfBar`
- `Contents/Resources/ShelfBar.icns`
- `Contents/Resources/ShelfBar.png`
- `Contents/Resources/ShelfBarLight.png`
- `Contents/Resources/ShelfBarDark.png`
- `Contents/PkgInfo`

### 2. Icon regeneration

`ShelfBar.icns` was regenerated from a complete `.iconset`:

- `icon_16x16.png`
- `icon_16x16@2x.png` = 32 px
- `icon_32x32.png`
- `icon_32x32@2x.png` = 64 px
- `icon_128x128.png`
- `icon_128x128@2x.png` = 256 px
- `icon_256x256.png`
- `icon_256x256@2x.png` = 512 px
- `icon_512x512.png`
- `icon_512x512@2x.png` = 1024 px

`iconutil -c iconset` successfully expanded the final `ShelfBar.icns` back into 10 icon files, confirming the `.icns` structure is readable.

### 3. Info.plist verification

Current bundle values:

```text
CFBundleExecutable = ShelfBar
CFBundleIdentifier = com.prototype.TouchBarPrivateResearch
CFBundlePackageType = APPL
CFBundleIconFile = ShelfBar.icns
LSMinimumSystemVersion = 15.7
LSUIElement = not present
```

The bundle identifier was kept unchanged to preserve the current UserDefaults domain and existing ShelfBar persistence. It is syntactically valid and is not a Finder prohibited-badge trigger.

### 4. Permissions

The executable is explicitly set executable:

```text
-rwxr-xr-x@ 1 seannb staff ... build/Release/ShelfBar.app/Contents/MacOS/ShelfBar
```

Resource files are set to normal readable file permissions.

### 5. Signing

The app is ad-hoc signed:

```text
codesign --force --deep --sign - build/Release/ShelfBar.app
```

Verification result:

```text
build/Release/ShelfBar.app: valid on disk
build/Release/ShelfBar.app: satisfies its Designated Requirement
```

`codesign -dv` confirms:

```text
Signature=adhoc
TeamIdentifier=not set
```

### 6. Quarantine / xattr cleanup

The local Release bundle is cleaned with:

```text
xattr -cr build/Release/ShelfBar.app
```

Validation:

```text
quarantine-absent
```

After signing, macOS still attaches `com.apple.provenance` on this local machine. Explicit deletion did not remove it. That attribute is not `com.apple.quarantine`; it is a local provenance attribute and the app still passes `codesign --verify`.

### 7. Finder / LaunchServices refresh

After signing and xattr cleanup:

```text
touch build/Release/ShelfBar.app
touch build/Release/ShelfBar.app/Contents/Info.plist
touch build/Release/ShelfBar.app/Contents/Resources/ShelfBar.icns
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/Release/ShelfBar.app
```

This is intended to avoid requiring the user to open **Show Package Contents** just to make Finder refresh the bundle.

### 8. Clean zip

Created:

```text
build/Release/ShelfBar.zip
```

The zip was created after signing, xattr cleanup and LaunchServices refresh.

## Verification log

### file

```text
build/Release/ShelfBar.app/Contents/MacOS/ShelfBar: Mach-O universal binary with 2 architectures: [x86_64] [arm64]
```

### lipo

```text
x86_64 arm64
```

### ls -l executable

```text
-rwxr-xr-x@ 1 seannb staff 2118848 ... build/Release/ShelfBar.app/Contents/MacOS/ShelfBar
```

### plutil

```text
build/Release/ShelfBar.app/Contents/Info.plist: OK
```

### icon file

```text
build/Release/ShelfBar.app/Contents/Resources/ShelfBar.icns exists
iconutil expansion produced 10 iconset files
```

### codesign verify

```text
build/Release/ShelfBar.app: valid on disk
build/Release/ShelfBar.app: satisfies its Designated Requirement
```

### xattr

```text
com.apple.quarantine: absent
com.apple.provenance: present after signing on this local machine
```

### spctl

```text
build/Release/ShelfBar.app: rejected
```

Reason: the app is ad-hoc signed and not notarized. Gatekeeper assessment requires Developer ID signing and notarization for a distributable app.

## Developer ID option

For distribution, replace ad-hoc signing with:

```text
codesign --force --deep --options runtime --timestamp --sign "Developer ID Application: <Name> (<TeamID>)" build/Release/ShelfBar.app
ditto -c -k --keepParent build/Release/ShelfBar.app build/Release/ShelfBar-notarize.zip
xcrun notarytool submit build/Release/ShelfBar-notarize.zip --keychain-profile <profile> --wait
xcrun stapler staple build/Release/ShelfBar.app
spctl -a -vv --type execute build/Release/ShelfBar.app
```

That is the correct path if the goal is for downloaded/copied apps to pass Gatekeeper without user override.

## Expected result

For the local Release build, Finder should no longer need package-content inspection to refresh the icon because:

- the app bundle is rebuilt cleanly;
- the icon file is valid and complete;
- quarantine has been removed from the bundle;
- bundle mtimes are updated;
- LaunchServices is explicitly registered.

