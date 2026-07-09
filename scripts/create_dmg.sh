#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/build/Release"
APP_PATH="$RELEASE_DIR/ShelfBar.app"
FINAL_DMG="$RELEASE_DIR/ShelfBar.dmg"
TEMP_DMG="$RELEASE_DIR/ShelfBar.tmp.dmg"
STAGING_DIR="$ROOT_DIR/build/dmg-stage"
BACKGROUND_DIR="$ROOT_DIR/Resources/DMG"
BACKGROUND_1X="$BACKGROUND_DIR/Background.png"
BACKGROUND_2X="$BACKGROUND_DIR/Background@2x.png"
VOLUME_NAME="ShelfBar"
MOUNT_DIR=""
WINDOW_LEFT=120
WINDOW_TOP=80
WINDOW_WIDTH=768
WINDOW_HEIGHT=512
ICON_SIZE=128
TEXT_SIZE=16
SHELFBAR_X=237
SHELFBAR_Y=286
APPLICATIONS_X=592
APPLICATIONS_Y=286

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  echo "Build ShelfBar.app before running this script." >&2
  exit 1
fi

if [[ ! -f "$BACKGROUND_1X" || ! -f "$BACKGROUND_2X" ]]; then
  echo "Missing DMG background assets:" >&2
  echo "  $BACKGROUND_1X" >&2
  echo "  $BACKGROUND_2X" >&2
  exit 1
fi

cleanup_mount() {
  if [[ -n "${MOUNT_DIR:-}" ]] && mount | grep -q "$MOUNT_DIR"; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
}
trap cleanup_mount EXIT

rm -rf "$FINAL_DMG" "$TEMP_DMG" "$STAGING_DIR"
mkdir -p "$RELEASE_DIR" "$STAGING_DIR"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -size 128m \
  -fs HFS+ \
  -ov \
  "$TEMP_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach "$TEMP_DMG" \
  -readwrite \
  -noverify \
  -noautoopen)"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | awk 'index($0, "/Volumes/") { print substr($0, index($0, "/Volumes/")); exit }')"
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
  echo "Unable to determine DMG mount point." >&2
  printf '%s\n' "$ATTACH_OUTPUT" >&2
  exit 1
fi

ditto "$APP_PATH" "$MOUNT_DIR/ShelfBar.app"
ln -s /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"
cp "$BACKGROUND_1X" "$MOUNT_DIR/.background/Background.png"
cp "$BACKGROUND_2X" "$MOUNT_DIR/.background/Background@2x.png"
chflags hidden "$MOUNT_DIR/.background" || true

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    delay 1
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set bounds of theWindow to {$WINDOW_LEFT, $WINDOW_TOP, $((WINDOW_LEFT + WINDOW_WIDTH)), $((WINDOW_TOP + WINDOW_HEIGHT))}
    set theOptions to icon view options of theWindow
    set arrangement of theOptions to not arranged
    set icon size of theOptions to $ICON_SIZE
    set text size of theOptions to $TEXT_SIZE
    set color of theOptions to {0, 0, 0}
    set background picture of theOptions to POSIX file "$MOUNT_DIR/.background/Background.png"
    set position of item "ShelfBar.app" to {$SHELFBAR_X, $SHELFBAR_Y}
    set position of item "Applications" to {$APPLICATIONS_X, $APPLICATIONS_Y}
    update without registering applications
    delay 1
    close theWindow
  end tell
end tell
APPLESCRIPT

sync
sleep 1
if [[ ! -f "$MOUNT_DIR/.DS_Store" ]]; then
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    delay 1
    close container window
  end tell
end tell
APPLESCRIPT
  sync
  sleep 1
fi

if ! PYTHONPATH="$ROOT_DIR/build/dmg-python" python3 -c 'import ds_store' >/dev/null 2>&1; then
  rm -rf "$ROOT_DIR/build/dmg-python"
  python3 -m pip install --target "$ROOT_DIR/build/dmg-python" ds-store mac-alias >/dev/null
fi

PYTHONPATH="$ROOT_DIR/build/dmg-python" python3 - "$MOUNT_DIR" <<'PY'
import os
import sys
from ds_store import DSStore
from mac_alias import Alias

mount_dir = sys.argv[1]
ds_path = os.path.join(mount_dir, ".DS_Store")
background_path = os.path.join(mount_dir, ".background", "Background.png")
background_alias = Alias.for_file(background_path).to_bytes()

with DSStore.open(ds_path, "w+") as store:
    store["."]["bwsp"] = {
        "ContainerShowSidebar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
        "ShowStatusBar": False,
        "ShowTabView": False,
        "ShowToolbar": False,
        "WindowBounds": "{{120, 80}, {768, 512}}",
    }
    store["."]["icvp"] = {
        "arrangeBy": "none",
        "backgroundImageAlias": background_alias,
        "backgroundColorBlue": 0.03137254901960784,
        "backgroundColorGreen": 0.023529411764705882,
        "backgroundColorRed": 0.01568627450980392,
        "backgroundType": 2,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "iconSize": 128.0,
        "labelOnBottom": True,
        "showIconPreview": True,
        "showItemInfo": False,
        "textSize": 16.0,
        "viewOptionsVersion": 1,
    }
    store["ShelfBar.app"]["Iloc"] = (237, 286)
    store["Applications"]["Iloc"] = (592, 286)
    store.flush()
PY

sync
hdiutil detach "$MOUNT_DIR" -quiet

hdiutil convert "$TEMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG" >/dev/null

rm -f "$TEMP_DMG"
xattr -dr com.apple.quarantine "$FINAL_DMG" 2>/dev/null || true

echo "Created $FINAL_DMG"
