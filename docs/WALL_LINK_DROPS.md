# Web links dropped onto Wall

Contract dated 2026-10-01, recorded before implementation. This is a small Wall
interaction slice using the existing inspiration payload and Space store. It
does not change the workspace schema or browser ownership.

Drag a web link from a page or another app onto the canvas of an active Wall
tab. Standard macOS URL drag items are accepted; plain-text-only items, files and images
remain separate future import workflows. Save HTTP(S) references with the
existing Pinterest, Are.na, Behance, Dribbble, Awwwards and Web classification.
Saving does not load a page, fetch a preview or import a provider's board.

Convert the drop location from canvas points into world coordinates using the
pan and zoom at drop time. The first card starts at that location. A batch uses
a compact three-column layout in drag-item order. Pan and zoom stay unchanged.
Only the canvas accepts drops; tab chrome retains its existing navigation drop
behavior. A subtle target outline appears only while a suitable drag is over
the canvas.

Bound one drop to 20 URL items, with each address limited to 8,192 characters.
Strip URL credentials, reject non-HTTP(S) or hostless addresses, and coalesce
equal cleaned URLs within that drop. Invalid and duplicate items are skipped
with a count in the result. Each later deliberate drop creates new object IDs;
URL equality never infers an existing tab binding or graph relationship.
Optional drag titles are bounded by the object envelope. A link reference has
no screenshot or inferred source-page relationship.

Read drag payloads asynchronously with an eight-second deadline. Pin the exact
window/browser, native Wall tab and Space. Leaving the tab or Space cancels the
request, including leaving and returning before a payload completes. Closing
the Wall or making its store unavailable also prevents publication. A timeout
saves nothing; delayed callbacks cannot revive the request.

Once every item resolves, save all valid objects and placements in one existing
WorkspaceStore mutation. Publication follows a successful durable write;
failure preserves the previous snapshot and creates no partial references.
Existing count/byte/geometry limits continue to apply. The 20-item limit keeps
this slice small while ordered background persistence remains a release task.

Acceptance: transformed positions and item order, provider/URL boundaries,
batch deduplication, one-revision atomic save and failure rollback, cancellation
and deadline behavior, Space isolation, unchanged WebKit ownership and viewport,
and restart persistence. Native evidence should distinguish exercising the
actual drag-data reader from a complete desktop mouse-drag interaction.

Implemented and validated 2026-10-02. Reader integration, native desktop drags,
restoration and workflow images are recorded in
[WALL_LINK_DROP_WORKFLOW.md](WALL_LINK_DROP_WORKFLOW.md).
