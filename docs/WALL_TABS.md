# Native Wall tabs

The Wall is a native content kind in Search's existing `Tab` model. Each window
keeps at most one Wall tab per Space. The toolbar button beside Bookmarks and
View → Open Wall select that tab, creating it when needed. Switching pages leaves
it open. The tab's close control, header close control and Command-W close it;
Escape dismisses temporary UI without closing a tab. Reopen Closed Tab restores
the same Space's Wall, without duplicating an already open Wall. Normal tab
groups and their restoration remain available.

`WallView` occupies the page stage only while its tab is selected. It does not
overlay a webpage. Native Wall tabs never build a WKWebView, navigate, sleep,
pin, split, or move to another Space/window. Existing page views remain owned by
their original tabs, preserving documents and navigation history.

Session entries carry an optional `nativeKind: "wall"` marker and an inert
`locus://wall/<space UUID>` address. Restoration requires both to match the
session's Space. Unknown native kinds and invalid native addresses are skipped
without discarding ordinary tabs; older web entries are unchanged. The URI alone
never grants native access. No object schema or workspace file changes are needed.

The Wall remembers the normal page from which it was opened for this live tab.
Its Add menu names that source. Saving a page returns to the Wall; capture and
inspiration collection select the source page first and return to the same Wall
on success. Sources must still exist in the same window and Space and satisfy
existing privacy, document and storage guards. Private pages never become sources.
After restart, open the Wall from a normal page to choose a source again.

Address/search commands remain available on a Wall tab. Web navigation opens an
ordinary page tab, leaving the Wall intact. Object search reveals objects in the
existing Wall tab. Workspace objects, relationships, recovery and viewport storage
retain their existing ownership and persistence rules.

[Native workflow screenshots](WALL_TAB_WORKFLOW.md) show the toolbar, selected
Wall, return to a page and object search.


## Validation (2026-10-01)

- Debug app and Xcode Debug build passed.
- Final standalone Swift suite: 105 tests passed.
- Native Wall tabs: 29 checks passed; object search: 22; page lifecycle: 27.
- Existing Wall, page binding, UI capture, inspiration and recovery checks passed.
- Split View: 91/92 checks passed on the broad run. The leave-animation sample
  had no frames; its focused nine-check moving suite passed on a separate rerun.
- Earlier parallel Swift verification timed out in two existing download tests;
  the final sequential full-suite run passed without failures.
- Native renders were inspected; no production browser profile was used.

The machine-readable results are in
[validation.json](../artifacts/wall-tabs/validation.json). Rendering and regression
checks complement the existing macOS/gesture/accessibility release QA.
