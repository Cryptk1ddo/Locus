# Connected inspiration and design research

Native workflow evidence captured 2026-10-01. These images render the actual
SwiftUI Wall/inspectors in an isolated hidden debug app. The Atlas/Patterns page
is a local sample fixture, and the AI response comes from a local mock server.
Pinterest/Are.na cards are saved links; no authenticated boards or external Pin
content were imported. Browser data is removed after the run.

Reproduce with `./build.sh debug` then `python3 Tests/inspiration_graph.py`.
Provenance is saved in `artifacts/inspiration/manifest.json`.

## Collect a visual reference

Open Wall → Add → Collect Inspiration from Page. The loaded WKWebView supplies
bounded title/description and an optional owned viewport PNG. Inspect shows the
provider, saved URL, coverage reason and editable personal notes. An entered link
is saved without loading it; its preview stays unavailable until a visited page
is explicitly collected.

![Native inspiration inspector](../artifacts/inspiration/01-inspiration-inspector.png)

## Connect the evidence on a Space canvas

Right-click a card → Connections… to link objects as Related to, Inspired by,
Supports or Contradicts. Dashed wires represent immutable source provenance.
Removing a card leaves its semantic links intact. Replacing it restores the
wires; deleting its object removes incoming links. Its PNG remains recoverable
for one previous revision before cleanup; damaged archives protect assets for
manual repair. See [STORAGE_RECOVERY.md](STORAGE_RECOVERY.md).
Drag the corner to resize; pan/zoom is remembered per window and Space. Cards
and wires never create a WebView or ask a model simply by appearing.

![Connected research and design canvas](../artifacts/inspiration/02-connected-wall.png)

![Native connections inspector](../artifacts/inspiration/03-connections.png)

## Save an attributed AI answer

Use the existing page AI action. After a successful answer completes and its
source checks finish, explicitly choose Save to Wall. The stored object retains
the answer, question, provider/model, source title/URL, reading timestamp and
cautions. Open Read Source uses its original reading URL, even when the related
page reference is updated later. It contains no keys, full page body or conversation history. Private
conversations and failed answers cannot be saved.

The fixture deliberately includes an invented address. It remains plain text,
and its caution persists alongside the saved evidence.

![Native AI evidence inspector](../artifacts/inspiration/04-ai-evidence.png)

## Validation and limits

The revised sources passed 80 non-download Swift tests, including nine new
object/asset/graph/viewport/AI fixtures. Six of seven existing download tests
passed in the full run; the one WebKit timeout passed individually on retry.
The initial feature build also passed all 87 Swift tests in one run.

29 native inspiration/graph checks passed, including owned previews, source
identity, unchanged WebKit ownership, preview suppression, deterministic stale
navigation/Space cancellation, private AI, source cautions, immutable read-source navigation after reference updates, independent Spaces,
restart, viewport restoration and asset cleanup. Existing Wall (15), UI capture
(20), bindings (20), lifecycle (27) and object-search (22) checks also passed.
Nine native AppKit gesture checks passed for resize vs. move, zoom-scaled sizing,
pan/zoom controls, Space separation and full app restart. The Xcode app build and
17 bundled startup/WebKit recovery checks passed on the final sources.

Storage still uses the bounded synchronous main-actor writer described in
[WALL_MVP.md](WALL_MVP.md). Account sync, bulk imports, files/PDFs, large-workspace
storage hardening, graph-wide AI and production MCP/agents remain separate
milestones. See [DEVELOPMENT_ROADMAP.md](DEVELOPMENT_ROADMAP.md).
