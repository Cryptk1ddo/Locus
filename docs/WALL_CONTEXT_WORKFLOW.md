# Native Wall menus and dialogs

Validated 2026-10-02 using a disposable app copy with isolated settings/data and
synthetic research notes. Pinterest and Are.na cards contain reference URLs;
their pages were not fetched. These are actual native app/window screenshots.

## Create where you are working

Right-click empty ground to create a note or inspiration link at that point,
find an object, fit all cards or reset the view. Creation respects pan and zoom.

![Native empty-canvas context menu](../artifacts/wall-context/01-canvas-menu.jpg)

New notes stay in the dialog until Save. Cancelling creates no object, placement
or revision. Empty drafts have Save disabled. Existing notes retain stale-save
protection, and write failures keep the draft open.

![Native new-note dialog](../artifacts/wall-context/02-new-note-dialog.jpg)

## Connect ideas without a long target menu

Search objects by title or type, select a target, choose the relationship and
optionally label it. The selected target remains visible if the filter changes.
Source/provenance connections retain their read-only treatment.

![Searchable native connection dialog](../artifacts/wall-context/03-searchable-connections.jpg)

## Actions belong to their objects

Card menus expose primary and source actions alongside connections and removal.
Inspiration offers Inspect, Edit Note and Open; page/capture/AI objects retain
their existing saved/live/source behavior. Saved HTTP(S) addresses can be copied
explicitly. Inspection and editing share one sheet route.

![Native inspiration card menu](../artifacts/wall-context/04-card-menu.jpg)

Remove Card retains the saved object and connections. Delete Object names what
will be deleted and counts its cards in this Space. Cancel leaves them intact.

![Named deletion confirmation for an object with two cards](../artifacts/wall-context/05-named-delete-dialog.jpg)

## Bring offscreen work back into view

Fit All Cards uses every saved placement. It changes the current window/Space
viewport only, preserving object positions, sizes and the workspace revision.
At the zoom limits, a very large Wall may still require panning.

![Native Wall after fitting every card](../artifacts/wall-context/06-fit-all-cards.jpg)

## Evidence and reproduction

The full Swift suite passed **118 tests**, including five new interaction tests
covering fitted geometry/limits, connection filtering, explicit-position atomic
creation, durable restoration and failure rollback. **20 native desktop checks**
are recorded in [desktop-qa.json](../artifacts/wall-context/desktop-qa.json).

Desktop actions used the actual native browser Wall tab, not the offscreen
render probe. With pan `(50, -30)` and zoom `1.25`, secondary clicks at window
points `(620, 450)` and `(100, 650)` created note/link world positions
`(456, 306.4)` and `(40, 466.4)` respectively. The canvas began at window y=97.
Cancel, invalid link input, inspector-to-editor Save, labelled connection,
card removal, two-card delete cancellation, fitted viewport and stale-save
rejection were checked against the durable store and native accessibility tree.
Objects, relationships, cards and viewport were verified after restarting.

The final Debug build also accepted a real native URL drag through the updated
ground. Dragging from the test-only source to window point `(600, 450)` created
one inspiration at world `(440, 284)` under the same viewport, with one revision
and unchanged WebKit views/bindings. Its ground menu still opened and Escape
dismissed it. See [native drag evidence](../artifacts/wall-context/07-native-drop-regression.jpg).
The existing native gesture, drop-reader and Wall-tab regression suites passed
**9 + 25 + 29 = 63 checks**. Debug assembly/ad-hoc signing and the Xcode Debug
scheme both build successfully.

For desktop replay, use a separate copy of `build/Search.app`, a unique bundle
identity and a named `SEARCH_PROBE` profile. Enable `SEARCH_DESKTOP_QA=1` explicitly
when launching that copy; the default probe continues to hide windows. Seed
synthetic note/link objects through the test-only Wall probes, open Wall and use
native secondary clicks. Never use an installed browser's profile. The test
profile was cleaned after this run; image provenance is in
[manifest.json](../artifacts/wall-context/manifest.json).

The final build adds explicit Control-click handling to the ground's native
menu. Physical trackpad/Control-click and the broader accessibility/large-graph
matrix remain release QA. Keyboard canvas navigation, internal object/file
drags and background storage still have separate roadmap acceptance boundaries.

See [WALL_CONTEXT_MENUS.md](WALL_CONTEXT_MENUS.md) for the contract and
[DEVELOPMENT_ROADMAP.md](DEVELOPMENT_ROADMAP.md) for remaining work.
