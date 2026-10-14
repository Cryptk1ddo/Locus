# Inspiration, canvas relationships and saved AI answers

Contract dated 2026-10-01, written before this feature slice. This extends the
existing Space-keyed object sidecar and native invoked Wall. Browser/Tab,
WKWebView ownership, sessions, extensions and Space swipes stay with Search.

## Product boundary

Collect inspiration from the current normal web page or an explicitly entered
link. Recognize Pinterest, Are.na, Behance, Dribbble and Awwwards, with a generic
web fallback. A Pinterest Pin or board is a saved source reference; saving a
board does not imply importing all its Pins. Provider entry points live inside
Wall's Add menu. No dashboard or permanent inspiration/AI sidebar is added.

For a visited page, read bounded title/description metadata in `Web.world` and
optionally save a visible WKWebView snapshot as a local PNG. Do not request remote
preview images, scrape a board feed, or access a provider's private API. Suppress
the snapshot if populated editable fields/password fields, embedded frames or
opaque custom components are visible (or inspection exceeds its bounded scan). The user
can still capture a particular safe component with the existing UI picker.

Pinterest account/board synchronization is a separate adapter requiring an
approved developer app, OAuth/Keychain credentials, scoped read access,
pagination, cancellation, deduplication and an explicit import preview. Current
requirements: [Pinterest developer tools](https://developer.pinterest.com/docs/developer-tools/quickstart-tools/).
Are.na offers a channel-content API with visibility rules and pagination:
[official API](https://www.are.na/developers/explore/channel/contents).
Account sync and bulk imports are not represented as completed by this slice.

## Data contract

Keep workspace schema version 1 and the existing forward-preserving envelope.
Add supported payload version 1 types:

- `inspiration`: saved `url`, provider key, resource kind/optional provider ID,
  bounded description and editable personal `text`; optional local `screenshot`
  section using the same asset-ID/MIME shape as UI capture. `collectedFrom`
  references the source page when collected from a live tab.
- `aiOutput`: plain answer `text`, question, provider/model, source title/URL,
  reading timestamp and coverage/caution flags. `generatedFrom` references a
  durable page object representing the page actually read. No API key, prompt
  history, full page body or executable action is stored.

Page/inspiration URLs admit HTTP(S), remove URL credentials, and require a host.
Saving a link creates an object without loading the link or fetching its preview.
Web links can also be dropped onto a native Wall canvas with world-space placement
and an atomic bounded batch; see [WALL_LINK_DROPS.md](WALL_LINK_DROPS.md).
New previews reuse the bounded PNG writer/validator (4 MB, 2,000 × 4,000 pixels).
The object, source relationship and placement publish in one workspace mutation;
a failed write removes its staged asset and leaves the previous snapshot intact.
Previews on canvas use downsampled local assets with a bounded cache.

Collection pins Space UUID, runtime tab ID, committed address and existing view
identity. Recheck before committing asynchronous metadata/snapshot results.
Navigation, Space/tab changes, sleep, closure and a deleted workspace must not
receive stale results. Private, automation and held sign-in pages are excluded.

AI remains the existing invoked page assistant. Only a completed, successful
answer from that assistant can be explicitly saved in its original Space.
Private conversations, which allow only a local provider, stay ephemeral. Saving retains source
provenance, model attribution and cautions; it does not rerun the model or grant
an object browser authority. Stored AI text renders verbatim and remains labeled
as potentially wrong. Open Read Source uses the immutable reading URL even if
its related page reference is explicitly updated later. A stale or duplicate
save cannot silently change evidence.

## Graph and canvas contract

Object relationships are semantic, Space-local links between durable IDs. Add
user-editable kinds `relatedTo`, `inspiredBy`, `supports`, and `contradicts`.
Provenance kinds `capturedFrom`, `derivedFrom`, `collectedFrom`, and
`generatedFrom` are shown but not edited through the relationship UI.

The graph on Wall is a projection of these semantic links onto the first
placement of each object. Removing a placement hides its wires and keeps the
semantic links. Placing that object again restores them. Deleting an object
removes all incoming links, as before. Multiple placements do not create
duplicate semantic records. The existing opaque `wall.edges` array is preserved
for future presentation-only edges; this slice does not reinterpret it.

Connect/inspect/disconnect through a card's context menu and an invoked native
sheet. Connections reject missing/self/unsupported targets and duplicate links;
bounded labels are data. Existing unknown relationship fields and types survive
round trips. Supported links have valid targets and bounded per-object counts.
Geometry-only graph drawing never opens tabs, executes a capture or asks AI.

Cards can be resized with a native corner handle and accessibility actions;
size constraints remain the store's existing 100–2,000 by 80–2,000 bounds. Canvas
view state is remembered per browser window and Space in the existing isolated
settings store, independently of shared object coordinates. The primary window
reuses the UUID already saved in `windows.json`; only identity is restored here,
while upstream session files retain ownership of that window’s tabs. Validate saved
pan/zoom values before using them. Panning inside Wall remains separate from
Space gestures in tab chrome.

## Acceptance checks

1. Provider recognition rejects lookalike hosts; source URL credentials and
   unsupported schemes cannot enter saved references.
2. Page collection produces a persisted inspiration object/local preview, with
   tab/view ownership unchanged; populated forms suppress previews.
3. Stale collection after navigation/Space switch cannot commit to either Space;
   private tabs cannot produce durable inspiration or AI objects.
4. User/provenance graph links survive restart, move/resize and placement removal;
   failures and object deletion preserve referential integrity and unknown data.
5. Canvas uses owned local preview assets, displays capture thumbnails and
   remembers validated per-window/Space view state.
6. Explicit AI saving records the source actually read and retains cautions;
   incomplete/failed/stale/private answers cannot be saved. Test through the
   existing local mock-provider pattern, with no cloud key or account access.
7. Native integration checks Wall close/focus behavior, Space isolation and
   restoration; visually inspect a fixture workflow with connected inspiration,
   notes, UI capture and saved AI content. Existing browser regressions pass.

Release storage hardening, files/PDFs, cross-Space copy, inferred graph links,
graph-wide AI context, full UI Sniper frame/motion export, authenticated provider
sync and agent/MCP runtime remain later milestones.

## Implemented module boundary

- `Inspiration.swift`: provider-aware references and a bounded collection pinned
  to a committed existing WKWebView. No OAuth tokens or account scraping.
- `AIWall.swift`: completed-answer factory, explicit save and immutable read-source
  navigation. The assistant snapshots provenance before asking its provider.
- `WallGraph.swift`: semantic-link projection and validated per-window/Space
  view preferences. The existing `wall.edges` representation stays opaque.
- `WallEvidence.swift`: invoked native inspiration/AI and connection inspectors.
- `WorkspaceImage.swift`: bounded owned PNG encoding and local thumbnail cache.
- Existing `WorkspaceStore` retains atomic publication and rollback, adds the
  two payloads and connection/resize operations, and preserves unknown records.

No new dependencies, browser engine, Space schema or production control/MCP
transport is introduced. Primary-window restoration copies its saved UUID;
existing session rows, WebKit creation, cookie/extension stores and tab ownership
continue to use the upstream paths.
