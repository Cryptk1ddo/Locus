# Wall MVP — development status

The first Space → Wall slice is implemented on top of the Search browser.
Open its own tab with the **Wall** button beside Bookmarks, **View → Open Wall**, the Space menu, or **open wall** when address
bar commands are enabled. Spaces need not be enabled: the first Space has a Wall.

## What works

- Explicitly save the current normal web page; add/edit plain-text notes.
- Right-click empty ground to create a note or inspiration link at that world
  position, find objects, fit all cards or reset the view. New notes remain drafts
  until Save; Cancel creates nothing. Card menus expose primary/source actions,
  searchable connections and a deletion confirmation naming the object/card count.
  See [WALL_CONTEXT_MENUS.md](WALL_CONTEXT_MENUS.md).
- Collect visual inspiration from the loaded page, save provider-aware links and
  annotate them. Whole-page previews omit populated forms, embedded frames and
  opaque custom components. See [INSPIRATION_GRAPH.md](INSPIRATION_GRAPH.md).
- Connect objects using semantic relationships, inspect provenance links,
  resize cards, and explicitly save a completed AI answer with its read source.
- Drag cards and the empty ground; use pinch or the zoom controls to zoom.
  Reset returns to the origin. Only placements near the viewport are rendered.
- Drop up to 20 web links onto the canvas as structured inspiration references,
  positioned using the current pan/zoom and saved in one revision. Leaving the
  tab or Space cancels pending drag-data reads. See [WALL_LINK_DROPS.md](WALL_LINK_DROPS.md).
- Open a page object through Browser's existing navigation/selection paths.
  It selects the bound live tab, including after session restoration; if the
  tab is absent it reopens the saved URL. Wall never owns or embeds a WKWebView.
- Page context menus explicitly open the saved address or update the reference
  from its bound tab. Close/undo and Clear undo preserve valid bindings.
- Capture context menus open the source page or start a new element selection
  with `derivedFrom` provenance. Existing evidence and assets remain unchanged.
- Remove a placement while keeping its object; the Objects menu places it again.
  Delete Object asks for confirmation, removes every placement and incoming
  relationship, and leaves any live browser tab open.
- Space-keyed persistence shared by windows, with validated per-window/Space viewport
  preferences that survive restart. Notes refuse stale saves if another window changed the same object.
- Command-W closes a panel first, then the selected Wall tab. Escape dismisses
  temporary UI. Switching tabs leaves Wall open; web navigation from Wall opens
  an ordinary page tab. See [Wall tabs](WALL_TABS.md) for source-page actions.
- Private and Bench pages cannot be saved through Add Page. Held sign-in
  callbacks are excluded; URL user/password components are stripped.

## Implementation boundary

`LocusObject.swift` defines the extensible object envelope and WallDocument.
`WorkspaceStore.swift` owns one bounded, atomic snapshot writer per Space.
`BrowserWall.swift` resolves browser actions; `WallBinding.swift` and the optional
Session.Entry object ID preserve deliberately saved bindings across restoration.
`WallView.swift` renders native cards without accessing `Tab.web`.
`WallDrop.swift` handles native URL drag data, bounded batches and world positions
through the existing atomic writer; no object or session schema changes.
`WallInteractions.swift` supplies the ground's invoked native menu, fit geometry
and connection-target filtering. One Wall sheet route owns creation, inspection,
editing and connection dialogs. Explicit-position creation uses one store commit.
`WallBench.swift` provides **test-only** probes, with no production automation
permission expansion. Existing Bench transport remains unchanged.

Browser.swift uses the existing row, selection, closing and session restoration.
App.swift selects native Wall content in the page stage. Tab.swift adds a native
kind without changing the web configuration or building a WKWebView for Wall.
Space deletion invalidates the writer and removes the Space's owned sidecar;
held editor callbacks cannot recreate it. Existing cookies/session ownership,
Space swipes, extensions and Tab configuration are unchanged.

On disk:

```text
Store.folder/workspaces/<Space UUID>/workspace.json
  schemaVersion = 1
  spaceID
  revision
  objects = [id, type, payloadVersion, title, createdAt, updatedAt,
             source, metadata, content, relationships, capabilities]
  wall = { id, placements = [id, objectID, x, y, width, height], edges }
```

Unknown object types/fields, Wall fields and placement fields survive mutations.
Unsupported objects render without editor/open actions. Larger signed/unsigned
integer metadata is preserved without converting it to a lossy Double.
Unreadable and newer-version files remain untouched and block writes; this MVP
preserves the original in place until explicit recovery is confirmed. A validated
previous revision is then restored only after the damaged file is archived. Failed
writes do not publish a changed snapshot. The UI displays the failure and a
note editor retains its draft until Save succeeds or Cancel is chosen.

Snapshots are limited to 2 MB, 2,000 objects and 4,000 placements. Commits are
synchronous on the main actor before publication. This is deliberately a small
initial store; background encoding/writes with explicit flush/error handling
should precede larger capture assets. There is no pending quit write to lose.
A previous-revision backup, explicit corruption recovery, preview quotas and
checksum-aware images are implemented; see [STORAGE_RECOVERY.md](STORAGE_RECOVERY.md).
Stale external edits are detected before writes. Cross-process locking and
automatic recovery are not supported.

## Deferred features

- Automatic title/URL synchronization. Durable session IDs, undo-close bindings
  and same-Space window transfer are implemented; see
  [TAB_OBJECT_BINDING.md](TAB_OBJECT_BINDING.md). Saved references retain their
  title/URL until explicitly updated; opening a bound object selects its current
  page. See [PAGE_REFERENCE_LIFECYCLE.md](PAGE_REFERENCE_LIFECYCLE.md).
- File/PDF imports and independent screenshot/token object workflows. UI capture
  and collected inspiration already support local PNG previews.
- Internal object/file drag imports, richer keyboard canvas navigation and routing/presentation
  controls for large graphs. Semantic connections, resize and viewport persistence
  are implemented; movement/resize/connection accessibility actions are available.
- Space-specific history, production object automation/MCP, graph-wide AI and
  agent/task runtime. AI remains invoked page understanding with explicit saving.
- Authenticated provider synchronization and bulk import previews. Current
  Pinterest/Are.na support collects visited pages or saves reference links.
- Locus branding, bundle/Keychain identities and release/update distribution.
  The debug app is still named Search; this is not a production release.

## Validation

Use named isolated SEARCH_PROBE worlds for browser regressions, never the
installed Search browser's data. The new unit fixtures live in temporary folders.

```sh
swift test
./build.sh debug
python3 Tests/wall.py
python3 Tests/close_panel.py
python3 Tests/fresh_window.py
```

The Wall integration suite exercises unchanged tab/view identities, explicit
save and reuse, close precedence, in-run tab binding, separate Spaces, restart
restoration and private-page exclusion. Its offscreen native preview is written
to `/tmp/locus-wall-preview.png` for inspection. Rendering verification does not
replace hands-on trackpad, drag, fullscreen and accessibility release QA.

Validated on 2026-09-30 with the available macOS/Xcode environment:

- Debug app built successfully (ad-hoc signing; upstream warnings remain).
- Swift suite: **56 tests passed**, including 9 workspace tests.
- Wall integration: **15 checks passed**.
- Fresh-window regression: **7 checks passed**.
- Close-panel regression: **9 checks passed**.
- Offscreen native preview inspected; `git diff --check` passed.

The first restricted full-suite attempt failed because its existing fixtures
could not write to macOS test containers. The permitted run used those isolated
test containers and passed. No production browser session was used for testing.
