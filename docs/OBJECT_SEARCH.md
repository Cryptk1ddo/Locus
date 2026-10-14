# Space object search

Implemented: the existing address field now accepts an explicit `wall:` scope.
`wall: research` searches the current Space's saved pages, notes, UI captures, inspiration and AI answers;
`wall:` offers a bounded recent list. Plain `wall art`, URL input, site search and
the open-tab switcher keep their existing behavior. Objects → Find Object from
the Wall enters this scope without changing preferences or navigating a tab.

Suggestions carry typed `(spaceID, objectID)` targets. Commands and objects have
no navigation URL; consumers must handle their typed intent before navigation.
Results are limited to five and ranked by title, then bounded page URL/note text/inspiration metadata/AI question and answer text. Capture
DOM/CSS and unknown payloads are not searched. IDs distinguish identical titles
and duplicate URLs. Query terms match case/diacritic-insensitively; note indexing
is bounded to 8,192 characters and queries to 256. Normalized text is cached in
memory per workspace revision; failed writes never publish a new search index.
Search is local and never evaluates a page or wakes a tab. No search-index file
or workspace schema migration is introduced.

Return reveals the first result, arrow keys choose another, and a click chooses
that row. No matches remain in the field without issuing a web search. The target
is resolved again against the current Space and store before acting; stale or
cross-Space suggestions cannot select another Space or navigate a page.

Reveal opens the existing native Wall and centers an existing placement, or adds
one if the object was removed from the Wall. It never creates a duplicate object.
A read-only store may reveal an existing placement but cannot create a new one.
The node is highlighted until the Wall closes; its existing Open/Edit/Inspect
action remains explicit. Durable tab bindings were added in the subsequent
[binding slice](TAB_OBJECT_BINDING.md). Search does not change saved references
automatically or expand production Bench/MCP.

## Validation

Validated on 2026-09-30 using isolated test storage:

- Swift suite: **65 tests passed**, including five object-search tests.
- Object search: **22 integration checks passed**, using real native field
  input, arrow keys and Return alongside direct click-action probes.
- Existing capture: **20 checks passed**; Wall: **15**; panel-close: **9**.
- Standalone History URL identity/completion regressions passed.
- A far-away node was revealed and its centered native preview inspected at
  `/tmp/locus-object-search-preview.png`.

Coverage includes title/body/URL matching, diacritics, duplicate titles, bounded
results, typed targets without URLs, commit-aware index invalidation, deleted
and cross-Space targets, placement reuse, restart restoration, and unchanged
tab/WebKit identities. Capture payloads and unsupported objects remain opaque.

Run `python3 Tests/object_search.py` after `./build.sh debug`. Test-only Wall
probes remain behind `Store.testing`; no installed browser data is used.
