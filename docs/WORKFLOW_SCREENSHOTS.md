# Native Locus workflow screenshots

Captured on 2026-09-30 from the debug app, still named Search. The first four
images capture the native browser window with its existing WKWebView; the fifth
renders the actual native inspector separately. These are app renders, not
mockups. The Atlas/Patterns webpage is a local sample fixture; it is not Locus's
start page or new browser chrome. No personal browsing data appears.

Reproduce with `./build.sh debug` then `python3 Tests/workflow_screenshots.py`.
The runner uses a dedicated hidden browser world and removes its temporary
browser data afterwards. Images and provenance remain in `artifacts/workflow/`.

## 1. Browse a reference

The webpage remains primary. Existing tabs and navigation stay in the restrained
native sidebar.

![Browser with local component reference](../artifacts/workflow/01-browser.png)

## 2. Invoke Capture UI

The picker outlines the hovered element and briefly exposes click/Escape guidance.
It runs in the existing WKWebView's isolated content world.

![Native UI capture picker](../artifacts/workflow/02-ui-picker.png)

## 3. Keep context on the Space's Wall

The captured component, its source page and a note are structured objects. The
Wall is invoked over the mounted page and closes back to browsing.

![Space Wall containing capture, page and note](../artifacts/workflow/03-space-wall.png)

## 4. Find an object in the same field

`wall: navigation` finds the note. Choosing it centers the card without creating
another webpage or tab.

![Explicit Space object search](../artifacts/workflow/04-object-search.png)

## 5. Inspect captured evidence

The actual native inspector displays the cropped PNG and bounded structured
evidence. This is a standalone render of the inspector view, not a screenshot
of the entire browser window; lower sections are reachable by scrolling.

![Native capture inspector](../artifacts/workflow/05-capture-inspector.png)
