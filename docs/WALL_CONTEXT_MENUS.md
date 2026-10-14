# Wall contextual interactions

Contract dated 2026-10-02, recorded before implementation. This slice improves
the existing native Wall tab without changing the object envelope, workspace
schema, WebKit ownership or browser chrome.

Secondary click (including Control-click) on empty canvas opens an invoked
native menu: New Note, Save Inspiration Link, Find Object, Fit All Cards and
Reset View. Creation captures the clicked canvas point, converts it through the
current pan/zoom, and retains that world position while the dialog is open.
Header creation keeps the existing default grid placement. A note or link is
published with its placement in one durable store mutation only after Save;
Cancel and invalid input create nothing. Fit changes only the window's saved
viewport and uses all placements, including offscreen cards, within existing
zoom/pan bounds.

Card menus expose the object's existing primary action, appropriate source
actions, editing for inspiration notes, Connections, Remove Card from Wall and
Delete Object. Removing a card retains the object and its links; deletion names
the object and explains that all its cards and connections in this Space are
removed. Saved source addresses can be copied explicitly after HTTP(S)
validation and credential removal. These actions do not grant new automation,
tab binding or network authority.

One sheet route owns note/link creation, inspection, editing and connections,
including the inspector-to-editor transition. Editors keep stale-object checks,
show failures without closing, and cannot write after the Space store is erased.
Leaving the Wall dismisses transient dialogs. Connection targets are searchable
by title/type, with a visible selected target; unsupported, self and deleted
targets cannot be connected. Existing provenance relationships remain read-only.

Acceptance includes real native secondary/Control-click menus, transformed
creation, cancel and failed-save behavior, card actions, searching/connecting,
remove versus named delete confirmation, viewport fitting, unchanged pan/resize/
URL drops, Space isolation and restart persistence. Screenshots should show the
real menus and dialogs in a disposable test app.

Implemented and validated 2026-10-02. Native menu/dialog and regression evidence
is recorded in [WALL_CONTEXT_WORKFLOW.md](WALL_CONTEXT_WORKFLOW.md).
