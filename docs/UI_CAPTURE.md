# Native UI capture — first slice

Invoke Capture UI from the View menu or command field, then click a rendered
page element. The existing WKWebView is inspected in Search's isolated content
world. No extension, new web view or AI request is needed.

A version-1 `uiCapture` object holds bounded structured DOM, computed CSS,
custom properties, pseudo-element styles, geometry/viewport, font information,
asset references, declared interaction/motion and inferred DOM accessibility.
A visible element crop is an optional owned PNG asset. Form controls, editable
subtrees, custom elements and truncated DOM captures conservatively omit pixels.
DOM serialization omits form controls, editable content, scripts and hidden text.

Each section records coverage/limits. Cross-origin frames, closed shadow roots,
event listener internals, native AX fidelity, font binaries and downloaded image
assets are unavailable in this slice. Source/asset URL credentials, queries and
fragments are redacted. Captured content is inert data, never agent authority.

A capture pins Space, active Tab, its existing PageView and a document generation.
Navigation, tab/Space switches, sleep, close, Escape and timeout cancel it. Late
callbacks cannot persist into another document or a deleted Space. Picker
listeners, its outline and its isolated-world handler are removed on completion
or cancel. This is bounded native functionality; no external UI Sniper source
or license has been supplied, and no external implementation is claimed.

The asset is staged before the workspace snapshot commits. Failed snapshot
writes remove the newly staged asset. Deleting a capture retains its owned asset while the previous revision refers
to it, then reconciles it after that backup advances. Damaged archives protect
assets for manual repair. New previews record byte counts and SHA-256 digests;
missing or damaged images leave structured metadata available. See
[STORAGE_RECOVERY.md](STORAGE_RECOVERY.md). Maximum metadata payload is 256 KB; maximum
PNG is 4 MB. Raster encoding runs away from the main actor. Snapshot and extraction
have separate timestamps and are not claimed to be an atomic visual observation.

## Implemented scope

Computed CSS and pseudo-element styles describe the selected root; the DOM tree
contains at most 200 nodes across eight levels. Asset references are limited to
40 entries and include sanitized inline SVG structure where available. Font
information records declarations and document font faces, not resolved glyph
fallbacks or font files. Section statuses expose truncation and missing coverage.
Open shadow trees can be serialized; picker targeting remains subject to DOM
event retargeting. Cross-origin frame contents are not inspected.

Pixels cover only the visible intersection with the existing WKWebView. Native
pinch magnification suppresses the crop; page zoom and magnification are recorded.
PNG limits are 2,000 by 4,000 pixels. DOM and pixels can differ if the page changes
between extraction and snapshot. Screenshots are visual references, not a general
redaction system for unrelated content overlapping the chosen element.

The capture and its source page are committed together, joined by a
`capturedFrom` relationship. A native modal inspector displays inert structured
data and the optional PNG. The picker is exposed through View → Capture UI and
the explicit `capture ui` command. Test-only Bench probes exercise the same
extractor; the production automation interface is unchanged.

Capture cards also expose **Open Source Page** and **Capture Again** in their
context menus. Capture Again requires the loaded, active bound source page and
starts a fresh element selection. The new observation links its source through
`capturedFrom` and its predecessor through `derivedFrom`, without modifying old
evidence or assets. Deleting either target during capture prevents publication.
See [PAGE_REFERENCE_LIFECYCLE.md](PAGE_REFERENCE_LIFECYCLE.md) for the lifecycle
contract and additional validation.

## Validation

Validated on 2026-09-30:

- Debug app built successfully with ad-hoc signing.
- Swift suite: **60 tests passed**, including four capture tests.
- Native capture integration: **20 checks passed**.
- Wall regression: **15 checks passed**; close-panel regression: **9 passed**.
- Native inspector preview inspected at `/tmp/locus-capture-preview.png`.

`Tests/ui_capture.py` uses a dedicated isolated browser world. It covers CSS,
tokens, pseudo-elements, geometry, source relationships, editable-content
exclusion, picker event suppression and cleanup, tab/SPA/navigation cancellation,
private-page exclusion and restart persistence of capture metadata and assets.
Unit tests cover crop conversion, payload limits, asset persistence/deletion and
rollback after snapshot write failure. No production browser data was used.
