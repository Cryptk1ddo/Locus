# Durable page bindings

Implemented: an optional, lenient `Session.Entry.objectID`. Its containing session row
supplies Space identity. No workspace schema change or bulk session migration
is needed; old/malformed IDs are ignored without quarantining otherwise valid
browser tabs, groups or split indices.

A live Tab carries one `(spaceID, objectID)` binding, replacing the window's
transient lookup dictionary. The binding moves with the same Tab when transferred
between windows in the same Space. Rehoming into another Space clears it before
any cookie-store shortcut; the source object stays in its original workspace.
Restoration and session writes resolve IDs against supported page objects in the
correct Space. Deleted, missing, unsupported and wrong-Space records do not bind.
Bindings never create objects automatically and do not instantiate a WKWebView.

Save Page, open an unbound page object, and capture-source commits write the
binding through existing session persistence. Pins retain each window's own
saved binding through reconciliation; shared PinDef identities are unchanged.
A new window's copy of a pin is unbound until explicitly saved. Global pin
definitions do not acquire workspace IDs or a global live Tab pointer.

Opening a page object first resolves its current canonical record, then selects
a matching local Tab or reopens its saved URL through the browser's existing
paths. Equal URLs never establish identity. Closing a tab leaves the object;
deleting the object leaves the tab. Saved title/URL remain snapshots even if
the bound tab navigates. Reopening selects that tab's current page when bound.
No automatic tracking, cross-Space copy, background tab wake, or global window
switch is introduced. Undo-close and Clear undo now re-resolve the saved binding
in the current Space. Card context menus expose explicit saved-address navigation
and reference updates; see [PAGE_REFERENCE_LIFECYCLE.md](PAGE_REFERENCE_LIFECYCLE.md)
for these actions, recapture lineage and their validation.

## Validation

On 2026-09-30, the debug app built and **69 Swift tests passed**, including four
binding/persistence fixtures. **20 native binding checks passed**, covering
duplicate URLs, split indices, restart selection, navigation, pin reconciliation,
new-window pins, same-Space transfer, primary-window promotion, shared-cookie
Space moves, deletion and close/reopen. Existing object-search (**22**) and native
capture (**20**) checks also passed. Tests use isolated browser worlds.
Pin-tier/session regressions (**32**), fresh-window regressions (**7**) and the
existing Wall workflow (**15**) passed as well. The five native workflow images
were generated and visually inspected; see [WORKFLOW_SCREENSHOTS.md](WORKFLOW_SCREENSHOTS.md).

The screenshot workflow also exposed an initial placement overlap when adding
the capture's unplaced source page. Placement now uses the same next grid cell
as ordinary adds. This is initial layout, not a general collision-avoidance rule
for user-moved cards.
