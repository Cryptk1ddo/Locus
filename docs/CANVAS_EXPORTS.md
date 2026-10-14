# Canvas exports

Exports read a fixed snapshot and never mutate the Wall or its history. Existing JSON Canvas exchange remains available. A new Export menu adds whole-Wall or expanded-selection exports as a portable folder, PNG or PDF.

Portable folders contain `Wall.canvas`, `assets/` and `manifest.json`. Directly referenced files with existing user-granted bookmarks, reachable local Markdown dependencies within existing grants, and validated workspace-owned previews are copied. Paths imported from JSON are references, never grants. Markdown links, images, wiki references and reference definitions are followed recursively. Only referenced files are copied; remote URLs are left alone. An individual file bookmark never authorizes adjacent files: dependencies require another existing file bookmark or the connected vault folder grant. Missing/ungranted references remain in the document and are listed in the manifest. The folder must be new; staging is removed on failure and no existing destination is replaced. Assets have neutral names, explicit byte/count limits and no executable processing. Subpaths, unknown JSON fields, node geometry and contained connections survive export. PNG/PDF are static overviews with labels, notes, saved images and connections; live web/video content is represented by its saved preview or title/URL.

Bounds include only exported cards and connected edges. Selection expands selected groups using the current Canvas rule. Empty selections/documents fail clearly for portable and overview exports; ordinary JSON Canvas can represent an empty document. Raster output is bounded by pixel dimensions and area; PDF page geometry is bounded. Neither export creates a Tab or WKWebView, reads recovery drafts, saves source notes or grants new file authority.

JSON Canvas reference: [specification](https://jsoncanvas.org/spec/1.0/).

## Controls and limits

Open the Wall's existing options menu, then **Export**. Choose JSON Canvas, Portable folder, PNG overview or PDF overview. With cards selected, the nested **Selection** menu exports the expanded selection and only its contained connections. Portable export requires a new folder name; unresolved references are reported after export and listed in `manifest.json`.

Limits: 200 copied assets, 20 MB per asset and 100 MB combined; JSON Canvas output is at most 2 MB. Static overviews fit within 4,096 pixels/points per side and approximately 12 million raster pixels, and reject world bounds over 100,000 units per side. Reading/copying/rendering currently runs synchronously and needs large-export performance QA. Dependency traversal scans at most 1 MB of Markdown, 256 local references per document and 32 levels; cycles reuse the same copied asset. Files above the scan/depth bound stay copied with an unresolved manifest entry. HTML, nested unescaped Markdown URL parentheses and indented Markdown references are outside this parser. PDF/PNG use the current browser appearance and native basic Markdown; live embeds, recovery drafts and richer note transclusion are excluded.

The implementation is `CanvasExport.swift` and `CanvasPortableFiles.swift`, called by the existing Wall options menu. Test-only file-export probes are guarded by `Store.testing`. Existing JSON export also rejects oversized output and allocates unique node/edge IDs when imported IDs collide with placement IDs.

## Workflow evidence

These exports and the chart view use a disposable signed app copy, isolated profiles and synthetic local files/pages. The chart image is a native AppKit render; PNG/PDF are actual exports from the app. No user browser data is included. Hidden-window motion probes explicitly advance authored animation/transition clocks and check frames, timing, transforms and paint; actual visible hover/clock behavior remains part of release QA.

![SVG chart and modern colors](../artifacts/color-export-refinement/night-chart-native-render.png)

![Canvas overview export](../artifacts/color-export-refinement/canvas-overview.png)

[PDF overview](../artifacts/color-export-refinement/canvas-overview.pdf) · [Portable example](../artifacts/color-export-refinement/portable-example/Wall.canvas) · [Validation](../artifacts/color-export-refinement/validation.json)

Validated on 2026-10-05: **182 model tests**, **124 native checks**, a signed debug app and the Locus Xcode target build. Final logs, executable hash and output provenance are in the validation record above.

Portable folders can now be opened through Wall options → Import → Portable folder. Direct local file/background references are granted only within the explicitly chosen folder. Missing references stay unresolved; imported notes use manual saving unless separately connected to a vault. See [import contract](CANVAS_IMPORT_PIP_REFINEMENT.md).

Saved link previews and their bounded titles now restore from portable manifests as workspace-owned inspiration images, preserving the link without requiring a page load. See [preview ownership contract](CANVAS_PREVIEWS_PIP_POLISH.md).

## Portable dependency restoration

Export copies use neutral filenames and rewritten relative references, preserving heading fragments, wiki aliases and Markdown titles. Source notes, recovery drafts and workspace history are unchanged. Inline Canvas notes use paths relative to the portable folder; copied Markdown uses paths relative to its own asset directory.

The version-1 manifest's optional `dependencies` array lists assets without a Wall card. Import grants only regular, non-symlink files contained in the folder the user chose, under the shared asset count/size budget. Dependency objects restore without additional cards and belong to the same single undo/redo operation. References resolve within each import's generated context, so two imports with identical neutral filenames stay separate. The imported folder must remain available for its file bookmarks; it is not copied into the workspace and does not enable vault autosave. Legacy manifests without dependencies remain supported.

Regression coverage: `CanvasPortableDependencyTests` exercises vault and individual-file authority, cycles/media, syntax preservation, inline notes, scoped import/re-export, undo/redo and atomic failure. `Tests/canvas_dependencies.py` exercises native nested preview rendering using an isolated profile and synthetic files.

Validated for v0.1.4 on 2026-10-14: 210 model/security tests passed using the hosted-CI command; 9 native dependency checks, 9 existing portable-import checks and 17 packaged startup/navigation/restoration checks passed. Package identity, architecture, development signature and archive hashes were verified. The full 217-test attempt encountered an existing live WebKit download timeout; those seven tests remain excluded from hosted CI.
