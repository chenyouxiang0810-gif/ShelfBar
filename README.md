# ShelfBar

Your Touch Bar, your workflow.

ShelfBar is a native macOS utility for Intel MacBook Pro models with a physical Touch Bar. It turns the Touch Bar into a fast shelf for files, clips, search, stacks, pinned work, recent items, and drop targets.

[![Download ShelfBar](https://img.shields.io/badge/Download-ShelfBar.dmg-007AFF?style=for-the-badge&logo=apple)](https://github.com/chenyouxiang0810-gif/ShelfBar/releases/download/v1.0.0-beta.2/ShelfBar.dmg)
[![Version](https://img.shields.io/badge/version-v1.0.0--beta.2-111111?style=for-the-badge)](https://github.com/chenyouxiang0810-gif/ShelfBar/releases/tag/v1.0.0-beta.2)
[![License](https://img.shields.io/badge/license-Proprietary-lightgrey?style=for-the-badge)](LICENSE)

## Website

- Product site: https://chenyouxiang0810-gif.github.io/ShelfBar/
- GitHub repository: https://github.com/chenyouxiang0810-gif/ShelfBar
- Latest DMG: https://github.com/chenyouxiang0810-gif/ShelfBar/releases/download/v1.0.0-beta.2/ShelfBar.dmg

## What ShelfBar Does

- Keeps files one touch away on the Touch Bar.
- Saves clipboard clips for quick return.
- Searches shelf items directly from the Touch Bar.
- Groups related work into stacks.
- Pins important files separately from the changing shelf.
- Shows recent work without opening a separate history window.
- Provides a Touch Bar drop target for moving work into ShelfBar quickly.

## Installation

1. Download `ShelfBar.dmg` from the latest GitHub Release.
2. Open the DMG.
3. Drag `ShelfBar.app` into Applications.
4. Launch ShelfBar.

macOS may show an app verification warning because this beta build is not notarized yet. If you trust this repository, open System Settings, go to Privacy & Security, and choose Open Anyway for ShelfBar.

## Supported Macs

ShelfBar is designed for Intel MacBook Pro models with a physical Touch Bar. The app window can open on other Macs, including Apple Silicon Macs, but the real Touch Bar shelf experience requires Touch Bar hardware.

Minimum macOS target: macOS 15.7.

## Current Release

Current public beta: `v1.0.0-beta.2`

Build identifier: `StabilityFix9`

Release artifact:

- `ShelfBar.dmg`

The DMG contains:

- `ShelfBar.app`
- Applications shortcut
- ShelfBar DMG background
- Universal app binary for `x86_64` and `arm64`

## Development

This project is an AppKit macOS app built with Xcode.

Main areas:

- `TouchBarPrivateResearch/` - app source.
- `TouchBarPrivateResearch/Resources/` - app icon and image resources.
- `Resources/DMG/` - DMG background assets.
- `scripts/create_dmg.sh` - DMG packaging script.
- `web/shelfbar-v2-preview/` - static product website.

The website is a static HTML/CSS/JavaScript site. For local preview:

```sh
cd web/shelfbar-v2-preview
python3 -m http.server 4174
```

Then open:

```text
http://127.0.0.1:4174/
```

## Beta Limitations

- Requires a physical Intel Touch Bar for the full experience.
- Uses private Touch Bar APIs, so App Store distribution is not expected.
- This build is ad-hoc signed and not notarized.
- Physical Touch Bar behavior should be verified on real hardware before treating a build as final.

## License

Proprietary. All rights reserved.
