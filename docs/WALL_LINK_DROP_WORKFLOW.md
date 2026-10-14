# Native Wall link-drop workflow

Validated 2026-10-02. These are native app renders from a disposable test profile.
They show deliberately supplied reference URLs and a local research fixture;
the runner does not fetch provider pages or use the user's browser session.

## Inspiration references on their own tab

Drag web links onto the canvas to create Pinterest, Are.na, Dribbble and other
inspiration references. Inspect their structured source data or open a source
when needed. The reference-only cards have no preview until a page is explicitly
visited and collected. A batch is saved in one revision; invalid and duplicate
items within that batch are skipped with feedback.

![Native Wall containing dropped inspiration and a note](../artifacts/wall-drops/01-dropped-inspiration-links.png)

## Restored workspace

Objects, placement sizes/positions and the window's pan/zoom survive restart.
Restoring the native Wall tab creates no web view for those links.

![Restored native Wall tab](../artifacts/wall-drops/02-restored-wall.png)

## Evidence and scope

`Tests/wall_drops.py` exercises real NSItemProvider URL callbacks through the
production reader: **25 checks passed**. The screen images are native root-view
renders. The fixture repositions its saved cards for the gallery after testing
the exact transformed drop location. `manifest.json` records their provenance.

Separately, desktop automation performed three real macOS mouse drags from a
native URL source into the actual WallView, including a drop over an existing
card. With pan `(60, 20)` and zoom `1.25`, canvas locations `(160, 145)`,
`(650, 325)` and `(260, 225)` produced world positions `(80, 100)`, `(472, 244)`
and `(160, 164)`. Each deliberate drop created a fresh object. Selection, viewport
and the existing WebKit view list remained unchanged. The seven assertions are
recorded in [desktop-qa.json](../artifacts/wall-drops/desktop-qa.json).

Visible native QA explicitly sets both `SEARCH_PROBE` (isolated data/settings)
and `SEARCH_DESKTOP_QA=1`. The test-only `wall/dragFixture` command supplies a
native source and Wall surface; `dragFixtureInfo` reports the fixture window
bounds. Automated probes keep their existing hidden-window guard by default.
No provider login, remote board import or drag from Safari was tested here.

The existing native card/ground gesture suite passed **9 checks**, and Wall tab
lifecycle/view isolation passed **29 checks**. The gesture fixture now reads
the page-area frame before selecting Wall: native Wall tabs have no WebKit pane
frame. The drop implementation uses the existing schema and atomic writer; see
[WALL_LINK_DROPS.md](WALL_LINK_DROPS.md) for limits and cancellation behavior.

The full Swift suite passed **113 tests**, including the eight focused drop
tests. Debug app assembly/ad-hoc signing and the Locus Xcode Debug scheme both
build successfully. [validation.json](../artifacts/wall-drops/validation.json)
records the completed checks. Release storage performance, file imports and
authenticated inspiration synchronization remain on the development roadmap.
