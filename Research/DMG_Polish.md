# DMG Polish

Date: 2026-07-09

## Scope

This pass only changes DMG packaging and install-window presentation. It does not change ShelfBar runtime features, signing identity, notarization status, AutoDrop, Universal Drop, AirDrop, MouseBridge, Stack or FilePromise.

## Output

Final DMG:

`build/Release/ShelfBar.dmg`

Packaging script:

`scripts/create_dmg.sh`

Background assets:

- `Resources/DMG/Background.png`
- `Resources/DMG/Background@2x.png`

## Window design

The DMG Finder window is configured to approximately:

- width: 768 px
- height: 512 px
- view mode: icon view
- toolbar: hidden
- status bar: hidden
- icon size: 128 px
- text size: 16 px
- arrangement: not arranged

Icon positions:

- `ShelfBar.app`: `{237, 286}`
- `Applications`: `{592, 286}`

The DMG contains:

- `ShelfBar.app`
- `Applications` symlink
- `.background/Background.png`
- `.background/Background@2x.png`
- `.DS_Store` with Finder window settings

## Background design

The background uses the supplied final DMG artwork from the user instead of a generated placeholder.

Visual direction:

- dark ShelfBar style;
- subtle blue glow;
- ShelfBar logo / Touch Bar visual language;
- center arrow cue from ShelfBar.app to Applications;
- supplied Retina artwork stored at 1536 × 1024.

The Finder background picture is set to the 768 × 512 PNG derived from the supplied 1536 × 1024 artwork. The original supplied artwork is preserved as `Background@2x.png`.

## Script behavior

`scripts/create_dmg.sh`:

1. checks that `build/Release/ShelfBar.app` exists;
2. checks that the supplied 1x and 2x DMG background assets exist;
3. removes old `build/Release/ShelfBar.dmg` and temp DMG;
4. creates a temporary writable HFS+ disk image;
5. mounts it through the standard `/Volumes` path so Finder can address `disk "ShelfBar"`;
6. copies `ShelfBar.app`;
7. creates the `/Applications` symlink;
8. copies background files into hidden `.background`;
9. uses Finder AppleScript to set:
   - icon view;
   - hidden toolbar;
   - hidden status bar;
   - 768 x 512 bounds;
   - fixed icon size;
   - dark icon-view background color hint for better Finder label contrast;
   - background picture;
   - icon positions;
10. writes `.DS_Store` metadata using the local `ds-store` Python package, including:
   - stable icon positions;
   - icon size;
   - `backgroundType=2`;
   - `backgroundImageAlias` pointing to `.background/Background.png`;
11. detaches the temporary image;
12. converts to compressed UDZO;
13. removes local quarantine from the output DMG.

`create-dmg` is not required. The script uses built-in macOS tools:

- `swift`
- `hdiutil`
- `osascript`
- `ditto`
- Python `ds-store` package installed under `build/dmg-python` when missing

## Verification

The generated DMG was mounted and inspected.

Content:

```text
/DMG/.DS_Store
/DMG/.background/Background.png
/DMG/.background/Background@2x.png
/DMG/Applications
/DMG/ShelfBar.app
```

DMG format:

```text
Format: UDZO
Format Description: read-only compressed UDIF
```

Size:

```text
build/Release/ShelfBar.dmg  about 11M
```

Local xattr:

```text
com.apple.quarantine: absent
```

The local machine still adds `com.apple.provenance` and Finder metadata xattrs. These are not notarization tickets and do not replace Developer ID signing.

## Gatekeeper status

Unchanged from `DMG_Notarization_Distribution.md`.

This DMG is visually polished, but it is still not a notarized public distribution artifact because this machine has no Developer ID Application certificate or notarytool credentials.

For public distribution, the app and DMG must still be Developer ID signed, notarized and stapled.
