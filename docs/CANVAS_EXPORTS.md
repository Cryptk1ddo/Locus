# Canvas exports

Exports read a fixed snapshot and never mutate the Wall or its history. Existing JSON Canvas exchange remains available. A new Export menu adds whole-Wall or expanded-selection exports as a portable folder, PNG or PDF.

Portable folders contain `Wall.canvas`, `assets/` and `manifest.json`. Only directly referenced files with existing user-granted bookmarks, and validated workspace-owned previews, are copied. Paths imported from JSON are references, never grants. No remote URLs are loaded, no vault is recursively copied, and no Markdown dependency traversal is performed. Missing/ungranted references remain in the document and are listed in the manifest. The folder must be new; staging is removed on failure and no existing destination is replaced. Assets have neutral names, explicit byte/count limits and no executable processing. Subpaths, unknown JSON fields, node geometry and contained connections survive export. PNG/PDF are static overviews with labels, notes, saved images and connections; live web/video content is represented by its saved preview or title/URL.

Bounds include only exported cards and connected edges. Selection expands selected groups using the current Canvas rule. Empty selections/documents fail clearly for portable and overview exports; ordinary JSON Canvas can represent an empty document. Raster output is bounded by pixel dimensions and area; PDF page geometry is bounded. Neither export creates a Tab or WKWebView, reads recovery drafts, saves source notes or grants new file authority.

JSON Canvas reference: [specification](https://jsoncanvas.org/spec/1.0/).

## Controls and limits

Open the Wall's existing options menu, then **Export**. Choose JSON Canvas, Portable folder, PNG overview or PDF overview. With cards selected, the nested **Selection** menu exports the expanded selection and only its contained connections. Portable export requires a new folder name; unresolved references are reported after export and listed in `manifest.json`.

Limits: 200 copied assets, 20 MB per asset and 100 MB combined; JSON Canvas output is at most 2 MB. Static overviews fit within 4,096 pixels/points per side and approximately 12 million raster pixels, and reject world bounds over 100,000 units per side. Reading/copying/rendering currently runs synchronously and needs large-export performance QA. Markdown dependencies and full vault packaging remain separate work. PDF/PNG use the current browser appearance and native basic Markdown; live embeds, recovery drafts and richer note transclusion are excluded.

The implementation is `CanvasExport.swift`, called by the existing Wall options menu. Test-only file-export probes are guarded by `Store.testing`. Existing JSON export also rejects oversized output and allocates unique node/edge IDs when imported IDs collide with placement IDs.

## Workflow evidence

These exports and the chart view use a disposable signed app copy, isolated profiles and synthetic local files/pages. The chart image is a native AppKit render; PNG/PDF are actual exports from the app. No user browser data is included. Hidden-window motion probes explicitly advance authored animation/transition clocks and check frames, timing, transforms and paint; actual visible hover/clock behavior remains part of release QA.

![SVG chart and modern colors](../artifacts/color-export-refinement/night-chart-native-render.png)

![Canvas overview export](../artifacts/color-export-refinement/canvas-overview.png)

[PDF overview](../artifacts/color-export-refinement/canvas-overview.pdf) · [Portable example](../artifacts/color-export-refinement/portable-example/Wall.canvas) · [Validation](../artifacts/color-export-refinement/validation.json)

Validated on 2026-10-05: **182 model tests**, **124 native checks**, a signed debug app and the Locus Xcode target build. Final logs, executable hash and output provenance are in the validation record above.

Portable folders can now be opened through Wall options → Import → Portable folder. Direct local file/background references are granted only within the explicitly chosen folder. Missing references stay unresolved; imported notes use manual saving unless separately connected to a vault. See [import contract](CANVAS_IMPORT_PIP_REFINEMENT.md).

Saved link previews and their bounded titles now restore from portable manifests as workspace-owned inspiration images, preserving the link without requiring a page load. See [preview ownership contract](CANVAS_PREVIEWS_PIP_POLISH.md).
