# Obsidian Canvas parity contract

Target recorded 2026-10-02 before implementation: the desktop core Canvas in
the installed Obsidian 1.13.7, checked against the official
[Canvas guide](https://obsidian.md/help/Plugins/Canvas) and
[JSON Canvas 1.0](https://jsoncanvas.org/spec/1.0/). Community plugins and vault-wide
Obsidian features are separate from core Canvas. The installed Canvas was
inspected without changing its contents or copying private reference material.

## Interaction and presentation acceptance

- Dotted canvas; compact floating creation tools at bottom centre; settings,
  zoom, fit, undo/redo and help at the upper right. No full-width Wall toolbar or
  permanently visible card action buttons. Selection controls appear locally.
- Click selects/fronts a card, Shift toggles membership, ground drag makes a
  selection box, Command-A selects all. Move/duplicate a selection together;
  constrain movement with Shift. Delete removes selected canvas cards/edges,
  retaining referenced Locus objects. Undo/redo restores complete actions.
- Double-click ground creates a text card; double-click text enters an inline
  Markdown editor. Escape/outside click ends editing. Explicit links and richer
  Locus capture/AI inspectors remain contextual actions.
- Space-drag and middle-button drag pan. Scroll pans; Shift-scroll is horizontal.
  Command/Space-scroll and pinch zoom around the pointer. Shift-1 fits all;
  Shift-2 fits selection. Grid/object snapping can be switched off; Space
  temporarily bypasses snapping. Resize every edge/corner with Shift preserving
  aspect ratio.
- Four edge handles create placement-to-placement connections. Dropping on
  ground creates a connected text card. Lines are selectable, removable,
  relabelled, recoloured, reconnectable and navigable to either endpoint.
- Groups enclose cards, move enclosed cards as a region and have editable
  labels/colours. Card and edge colours use the six Canvas presets plus custom
  colours. Selection supports contextual duplication, grouping and zooming.
- Text, note references, file/media/PDF cards and web cards; native file/drop
  selection, clipboard text/URLs/images, file swapping and text-to-file
  conversion. A file is accessed only after explicit selection/import; unknown
  files remain reopenable references. Live web content uses existing WebKit
  configuration and Space sign-in boundaries; it is activated explicitly.
- JSON Canvas import/export preserves placement identities/order, text, file/
  link/group records, endpoint sides/directions, colours and labels. Unsupported
  data is retained or reported explicitly rather than silently discarded.

## Data and ownership

Browser/Tab keep their existing ownership, sessions and WKWebView configuration.
Wall remains native tab content. The durable object envelope remains the source
of content, provenance and semantic relationships. Visual Canvas connections
belong to `WallDocument.edges` and reference **placement IDs**, since two cards
can reference one object. They do not silently rewrite semantic/provenance links.

Add optional placement colour fields and supported group/file object payloads.
Legacy schema-1 documents decode with defaults; unknown envelope and placement
fields survive writes. Known new records receive bounded validation. Groups use
geometry for containment, avoiding a second persistent membership graph.

Introduce a native canvas surface/controller dedicated to hit testing, selection,
transient gesture previews, inline editing and keyboard focus. One completed
gesture is one durable mutation; previews never write intermediate positions.
Store undo/redo is bounded by count/bytes, commits before publication, rejects
stale writers and retains owned previews needed by history. Failed commits do
not consume history. File references use bookmarks/security-scoped access;
paths imported from JSON are data and grant no automatic filesystem authority.

Read-only/snap preferences and viewport stay per window/Space. Selection and
inline note edit state are transient and are cleared on tab/Space departure. File drafts persist separately across departure and restart. Canvas
key commands apply only while this surface owns focus; browser navigation,
address editing, other tabs and modal panels retain their normal commands.

## Parity tracking

This contract is an acceptance checklist, not a claim of completed parity.
Implementation evidence and any remaining differences must be recorded here
after native validation. Full parity requires comparing actual interactions,
not merely using matching menu labels or exporting a `.canvas` file.


## Implemented in this change

The previous SwiftUI card/ground renderer is replaced by `CanvasSurface`, with
`CanvasController` providing window/Space viewport and selection state. The
browser tab lifecycle and WebKit configuration factory are retained.

- Floating creation/navigation controls, local selection tools, dotted ground,
  contextual menus, native inline text/group/edge-label editing and cursor hints.
- Box/Shift/all selection; multi-card movement, Option-drag duplication,
  Shift axis/aspect constraints, grid/object snapping and Space bypass.
- Space/middle panning, wheel/pinch/pointer-centred zoom, fit-all/selection and
  reset zoom preserving the current centre. Zoom range is 5–400%.
- Placement connections, directed endpoints, labels, colour, hit testing,
  reconnection, endpoint navigation and undo/redo. A connection dragged onto
  ground creates a connected text card in one revision.
- Geometric groups, moving enclosed cards, renaming, preset/custom colours and
  user-selected cover/ratio/repeat image backgrounds.
- Native Markdown headings, inline styles/code/links and bullets; selected-card
  scrolling and Command-click links; plain source editing in `NSTextView`.
- File/folder selection, bookmarks, image/PDF previews and activated PDF/audio/
  video controls; native live web embeds, file swapping, text-to-file conversion,
  text/URL/image paste, and dragging any creation tool to choose its destination.
- JSON Canvas nodes/edges, order, original string IDs, endpoint directions,
  colours, labels and unknown document/node/edge fields round-trip. File paths
  from imported JSON require explicit location before access. Browser/Locus
  objects without a Canvas equivalent export as descriptive text/link cards.
- Durable shared-Space undo/redo, bounded to 50 entries and 16 MB. Preview assets
  needed by undo or an opaque historical object are retained. History is
  session-local; saved content survives restart.

## Remaining differences: exact parity is not complete

This implementation must not be presented as an exact Obsidian clone yet.

1. Native previews now include tables, granted local images and bounded note/heading/block transclusion, with source links and cycle limits. Mathematics, embedded canvases, plugin syntax and full Obsidian rendering remain incomplete. Granted UTF-8 Markdown/text files edit inline with recoverable drafts; connected-vault files autosave with conflict protection. See [vault and embeds](CANVAS_VAULT_AND_EMBEDS.md) and [file editing](CANVAS_FILE_EDITING.md).
2. Each Space can connect one folder as a vault. Settings offer a native file picker for adding vault notes, and wiki links resolve relative paths or unambiguous indexed basenames. Full vault-wide search, renaming/backlink maintenance and Obsidian metadata/plugin behavior remain further work.
3. Live web embeds are limited to eight visible cards and recreated when culled.
   PDF/audio/video controls activate on double-click. These limits preserve the
   browser's resource budget but differ from Obsidian's embed lifecycle.
4. A reconnect dragged to empty ground currently cancels; detached endpoints
   need the final interaction pass. Arrow editing is available in the local
   selection tools and the line context menu. Moving a card fronts it; simply
   selecting it does not yet persist a new stacking order.
5. Imported file paths can be located inside an explicitly connected vault through Canvas settings; other paths remain references until selected. Plain `.canvas` export remains references only. Portable-folder export copies directly granted files and validated saved captures/previews, reports unresolved references, and retains subpaths. Portable-folder import now connects contained direct files and group backgrounds in one undoable transaction. PNG/PDF static overviews and selection export are available; recursive Markdown/vault dependency packaging, general vault background-path binding remain incomplete. Portable saved link previews now restore as owned inspiration images; see [preview/PiP polish](CANVAS_PREVIEWS_PIP_POLISH.md). See [CANVAS_EXPORTS.md](CANVAS_EXPORTS.md).
6. The release matrix still needs large-canvas performance, VoiceOver action
   coverage, macOS versions and detailed comparison with Obsidian's theme/zoom
   behavior. Locus's browser shell and structured capture/AI inspectors remain
   Locus-specific.

Reference: [Obsidian Canvas documentation](https://obsidian.md/help/Plugins/Canvas)
and [JSON Canvas 1.0](https://jsoncanvas.org/spec/1.0/).

## Validation evidence

The original Canvas slice passed 130 model tests. Its native suites passed 19 Canvas,
9 gesture, 25 drop and 29 Wall-tab checks (82 total), using disposable profiles.
The signed debug app and Locus Xcode target build. The saved-page regression
waits for the restored document to load before checking preservation of live
page state; its earlier fixed-delay fixture could set a marker in about:blank.
These checks do not establish complete Obsidian parity or the release matrix.

See [the workflow gallery](CANVAS_WORKFLOW.md) and
`artifacts/canvas/validation.json`. The images are native AppKit app renders,
not screen captures. The final desktop comparison remains pending because
the Mac was locked during the last visual pass.

The subsequent content/PiP refinement is documented in
[CANVAS_PIP_REFINEMENT.md](CANVAS_PIP_REFINEMENT.md). Its separate verification
record lives in `artifacts/refinement/validation.json`.

The subsequent native file editor contract and validation are in
[CANVAS_FILE_EDITING.md](CANVAS_FILE_EDITING.md).

The vault/embed slice passes 162 model tests and 67 native checks, with signed debug and Xcode builds. See [Vault autosave and embeds](CANVAS_VAULT_AND_EMBEDS.md) and `artifacts/vault-embeds/validation.json`.

The latest import/PiP slice passes 191 model tests and 109 native checks. See [Canvas import and PiP refinement](CANVAS_IMPORT_PIP_REFINEMENT.md) for the contract, workflow renders and remaining limits.

The saved-preview/PiP polish slice is verified on 2026-10-12 with 198 model and 128 native checks. See [saved previews and PiP polish](CANVAS_PREVIEWS_PIP_POLISH.md).
