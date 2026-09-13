# ShelfBar v2 Local Website Preview

This is a local-only static product page preview for ShelfBar. It intentionally does not publish GitHub Pages and does not modify the macOS app project.

## Product Display Direction

The page now focuses on:

- Real Touch Bar screenshots or recordings.
- Real ShelfBar app screenshots.
- Apple-style black/white layout, large spacing, restrained motion, and small ShelfBar-blue highlights.

It no longer uses a full MacBook product image, CSS laptop mockup, generated laptop art, or fake app UI.
Touch Bar screenshots share one black rounded rectangle frame. The frame adds quiet shape and spacing without covering or cropping the Touch Bar media.
The `Get a highlighter.` section keeps the highlighter moment clean; Touch Bar media appears in the highlights carousel and story sections.
The highlights carousel now sits in that same section under the highlighter moment. Its previous/next controls use CSS solid triangle icons. The controls appear as an Apple-style floating capsule, opening from a bouncing ball as the section scrolls into view. Feature changes use paired horizontal slide panels: the old feature exits left or right while the next feature enters from the opposite side. The blue `Get a highlighter.` mark draws once when the section scrolls into view and stays visible.

## Main Files

- `index.html` - landing page structure.
- `styles.css` - visual system, responsive layout, highlighter, carousel, story, and app showcase styling.
- `script.js` - carousel, scroll story, highlighter drawing, tab switching, and optional video loading.

## Touch Bar Media

Fallback still images live in `assets/touchbar/`:

- `assets/touchbar/files.png` - Files shelf with file items.
- `assets/touchbar/clips.png` - Clipboard shelf with clip items.
- `assets/touchbar/search.png` - Search results for `shelf`.
- `assets/touchbar/stack.png` - Stack feature.
- `assets/touchbar/pin.png` - Pinned items.
- `assets/touchbar/recent.png` - Recent shelf.
- `assets/touchbar/drop.png` - AirDrop / Drop your file here.

Optional real recordings go in:

```text
assets/videos/
```

Use these filenames and the page will auto-load them when served over HTTP:

```text
assets/videos/files.mp4
assets/videos/clips.mp4
assets/videos/search.mp4
assets/videos/stack.mp4
assets/videos/pin.mp4
assets/videos/recent.mp4
assets/videos/drop.mp4
```

Supported extensions are `.mp4`, `.webm`, and `.mov`. You can also map custom filenames in `assets/videos/manifest.json`:

```json
{
  "files": "assets/videos/my-files-demo.mp4",
  "search": "assets/videos/my-search-demo.mp4"
}
```

The Touch Bar media is displayed inside the shared long, thin Touch Bar frame at the real `2008 x 60` screenshot ratio with `object-fit: contain`, so still screenshots are not stretched or cropped.

## App Screenshots

Current app screenshots live in:

```text
assets/app-pages/general.png
assets/app-pages/appearance.png
assets/app-pages/features.png
assets/app-pages/shelf.png
assets/app-pages/about.png
```

The Workflow section is already wired for:

- General
- Appearance
- Features
- Shelf
- About

The carousel also reuses these same real app captures beside the matching Touch Bar feature. Replace the files with the same filenames to update the preview without editing the page.

## Local Preview

From this folder:

```sh
python3 -m http.server 4174
```

Then open:

```text
http://127.0.0.1:4174/
```
