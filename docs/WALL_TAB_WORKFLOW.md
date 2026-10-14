# Wall tab workflow

These screenshots are actual SwiftUI/AppKit app renders from an isolated native
QA profile with a local sample webpage. They were captured by
`Tests/wall_tabs.py`; no product mockup or external service import is involved.

1. The Wall button sits immediately beside Bookmarks in the top-right toolbar.
   Clicking it opens the current Space's native Wall tab.

   ![Page and Wall button](../artifacts/wall-tabs/01-page-and-wall-button.png)

2. The Wall occupies its own tab. The source page remains in the row, and the
   toolbar button indicates when the Wall is selected.

   ![Wall selected as a native tab](../artifacts/wall-tabs/02-wall-as-a-tab.png)

3. Selecting the source page leaves the Wall open. The test verifies that the
   page retains its live JavaScript document state across these switches.

   ![Back on the page, Wall still open](../artifacts/wall-tabs/03-back-to-the-page.png)

4. Object search works over native Wall content, including with Split View
   enabled. Selecting an object reveals it in the existing Wall tab.

   ![Searching objects from a Wall tab](../artifacts/wall-tabs/04-wall-object-search.png)

The test also exercises Command-W, Reopen Closed Tab, tab groups, separate
Spaces, session restart/deduplication, invalid native markers, source-page
capture, navigation from Wall and private-page exclusion.
See [WALL_TABS.md](WALL_TABS.md) for the architecture and data contract.
