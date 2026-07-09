# DMG Notarization and Distribution

Date: 2026-07-09

## Goal

Produce a clean `ShelfBar.dmg` distribution artifact and verify whether this machine can complete a Developer ID + Apple notarization release flow.

## Result summary

Artifacts created:

- `build/Release/ShelfBar.app`
- `build/Release/ShelfBar.dmg`
- `build/Release/ShelfBar.zip`

Distribution status:

- Developer ID Application certificate found: **No**
- App notarization completed: **No**
- App stapled: **No**
- DMG signed with Developer ID: **No**
- DMG notarization completed: **No**
- DMG stapled: **No**

Reason:

This machine has no valid code signing identity and no Apple notarization credentials configured. Therefore it cannot produce a Gatekeeper-clean public distribution build. The generated DMG is a clean local artifact, but it is not a notarized distribution DMG.

## 1. Signing identity detection

Command:

```text
security find-identity -v -p codesigning
```

Result:

```text
0 valid identities found
```

Developer ID Application identity:

```text
not found
```

Consequence:

`codesign --sign "Developer ID Application: ..."` cannot be run on this machine.

## 2. Notarization credential detection

Environment variable status:

```text
APPLE_ID=missing
APPLE_TEAM_ID=missing
APPLE_APP_SPECIFIC_PASSWORD=missing
```

`notarytool` exists:

```text
/Library/Developer/CommandLineTools/usr/bin/notarytool
```

Consequence:

`xcrun notarytool submit ... --wait` cannot be completed without either:

- a stored keychain profile, or
- `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`.

No notarization was attempted because the required credentials are absent.

## 3. Clean Release build

Cleaned before rebuild:

- `build/Release/ShelfBar.app`
- `build/Release/ShelfBar.dmg`

Built Universal executable:

```text
x86_64 arm64
```

Build warning:

```text
QLThumbnailImageCreate was deprecated in macOS 15.0
```

This warning is known and unrelated to packaging or Gatekeeper.

## 4. App bundle validation

### Info.plist

Command:

```text
plutil -lint build/Release/ShelfBar.app/Contents/Info.plist
```

Result:

```text
build/Release/ShelfBar.app/Contents/Info.plist: OK
```

Important values:

```text
CFBundleExecutable = ShelfBar
CFBundleIdentifier = com.prototype.TouchBarPrivateResearch
CFBundlePackageType = APPL
CFBundleIconFile = ShelfBar.icns
LSMinimumSystemVersion = 15.7
LSUIElement = not present
```

`LSUIElement` is intentionally absent. Dock/menu-bar behavior is controlled at runtime through `NSApp.setActivationPolicy`, not by making Finder treat the app as an agent-only bundle.

### Executable

Command:

```text
file build/Release/ShelfBar.app/Contents/MacOS/ShelfBar
```

Result:

```text
build/Release/ShelfBar.app/Contents/MacOS/ShelfBar: Mach-O universal binary with 2 architectures: [x86_64] [arm64]
```

Command:

```text
ls -l build/Release/ShelfBar.app/Contents/MacOS/ShelfBar
```

Result:

```text
-rwxr-xr-x@ 1 seannb staff 2118848 ... build/Release/ShelfBar.app/Contents/MacOS/ShelfBar
```

### Icon

`ShelfBar.icns` was regenerated from a complete iconset containing:

- 16 px
- 32 px
- 64 px
- 128 px
- 256 px
- 512 px
- 1024 px

Validation:

```text
iconutil -c iconset -o build/Release/validation/ShelfBar_validated.iconset build/Release/ShelfBar.app/Contents/Resources/ShelfBar.icns
```

Result:

```text
10 iconset files produced
```

Icon file:

```text
build/Release/ShelfBar.app/Contents/Resources/ShelfBar.icns exists
```

## 5. Code signing

Because no Developer ID identity exists, the app was not formally Developer ID signed.

An ad-hoc signature was applied only for local bundle consistency:

```text
codesign --force --deep --sign - build/Release/ShelfBar.app
```

Verification:

```text
codesign --verify --deep --strict --verbose=4 build/Release/ShelfBar.app
```

Result:

```text
build/Release/ShelfBar.app: valid on disk
build/Release/ShelfBar.app: satisfies its Designated Requirement
```

Signature details:

```text
Signature=adhoc
TeamIdentifier=not set
```

Gatekeeper assessment:

```text
spctl -a -vv build/Release/ShelfBar.app
build/Release/ShelfBar.app: rejected
```

This rejection is expected for an ad-hoc signed, non-notarized app.

## 6. Notarization

Skipped.

Reason:

- no Developer ID Application certificate;
- no Apple notarization credentials;
- no notarization profile supplied.

Therefore:

- `xcrun stapler staple ShelfBar.app` was not run;
- `xcrun stapler validate ShelfBar.app` was not run;
- no notarization ticket exists.

## 7. DMG packaging

`create-dmg` was not installed, so packaging used `hdiutil` fallback.

DMG path:

```text
build/Release/ShelfBar.dmg
```

DMG content:

- `ShelfBar.app`
- `Applications` symlink

Command class:

```text
hdiutil create -volname "ShelfBar" -srcfolder build/dmg-stage -ov -format UDZO build/Release/ShelfBar.dmg
```

Image info:

```text
Format: UDZO
Format Description: read-only compressed UDIF
```

Size:

```text
build/Release/ShelfBar.dmg  8.0M
```

## 8. DMG signing and notarization

Skipped.

Reason:

- no Developer ID Application identity;
- no notarization credentials.

Gatekeeper assessment:

```text
spctl -a -vv -t open build/Release/ShelfBar.dmg
build/Release/ShelfBar.dmg: rejected
source=Insufficient Context
```

This is expected for an unsigned, non-notarized DMG.

## 9. Quarantine / xattr

Local build cleanup:

```text
xattr -dr com.apple.quarantine build/Release/ShelfBar.app || true
xattr -dr com.apple.quarantine build/Release/ShelfBar.dmg || true
```

Validation:

```text
app_quarantine_absent
dmg_quarantine_absent
```

Note:

When another user downloads the DMG from a browser, macOS will normally add quarantine again. That is expected. The correct distribution fix is Developer ID signing + notarization + stapling, not relying on local xattr removal.

This local machine also attaches `com.apple.provenance`. It is not `com.apple.quarantine`, and `codesign --verify` still passes.

## 10. Correct release flow once credentials exist

With Developer ID and a notarytool keychain profile:

```text
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: <NAME> (<TEAMID>)" \
  build/Release/ShelfBar.app

ditto -c -k --keepParent build/Release/ShelfBar.app build/Release/ShelfBar.zip

xcrun notarytool submit build/Release/ShelfBar.zip \
  --keychain-profile "<PROFILE>" \
  --wait

xcrun stapler staple build/Release/ShelfBar.app
xcrun stapler validate build/Release/ShelfBar.app

hdiutil create -volname "ShelfBar" \
  -srcfolder build/dmg-stage \
  -ov -format UDZO \
  build/Release/ShelfBar.dmg

codesign --force --timestamp \
  --sign "Developer ID Application: <NAME> (<TEAMID>)" \
  build/Release/ShelfBar.dmg

xcrun notarytool submit build/Release/ShelfBar.dmg \
  --keychain-profile "<PROFILE>" \
  --wait

xcrun stapler staple build/Release/ShelfBar.dmg
xcrun stapler validate build/Release/ShelfBar.dmg

spctl -a -vv --type execute build/Release/ShelfBar.app
spctl -a -vv -t open build/Release/ShelfBar.dmg
```

## 11. Test plan

Because this build is not Developer ID signed or notarized, this test plan cannot be guaranteed to pass on another Mac.

Once Developer ID signing and notarization are complete:

1. Send `build/Release/ShelfBar.dmg` to another Mac.
2. Open the DMG.
3. Drag `ShelfBar.app` to Applications.
4. Open ShelfBar from Applications.
5. Gatekeeper should not show:
   - "cannot verify developer";
   - "is damaged and should be moved to the Trash";
   - similar quarantine trust errors.

Current non-notarized DMG may still trigger Gatekeeper warnings after browser download.

