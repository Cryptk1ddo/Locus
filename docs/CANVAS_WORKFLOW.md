# Native Canvas workflow

The Wall remains a separate browser tab with a toolbar button beside Bookmarks.
Its canvas now uses native AppKit interaction and compact floating controls.
The screenshots below are **AppKit renders of the running QA app**, made through
its existing test-only Bench interface using synthetic content. They are not
mockups or desktop screen captures. The final desktop comparison is pending
because the Mac was locked during verification.

## Arrange research

Double-click ground to create a text card, or click/drag a creation tool to add a
card, Space note or file/media at that position. Drag cards to arrange them,
drag ground for a selection rectangle, and Shift-click to extend selection.
Groups move their enclosed cards. Option-drag duplicates; Space bypasses snapping.

![Canvas with grouped Markdown cards and a labeled connection](../artifacts/canvas/01-canvas-native-render.png)

## Work with a card

Selection exposes its four connection handles and a compact color/group/remove
toolbar. Drag a boundary to resize; Shift preserves its aspect ratio. Right-click
for duplication, grouping, file conversion, object-specific actions and removal.
Removing a card retains its Space object; the separately named Delete Saved Object
command removes the object and supports undo.

![Selected card and contextual controls](../artifacts/canvas/02-selected-card-native-render.png)

## Edit directly

Double-click a text card to edit its Markdown source in place. Escape or
Command-Return saves it and returns to rendered content. Native text selection,
clipboard shortcuts and scrolling stay inside the editor while it has focus.
Selected text cards also support clickable task checkboxes and `[[Note#Heading|Alias]]`
links within the current Space. Task updates preserve source formatting and are
undoable; read-only mode blocks changes. `[[#Heading]]` targets the current note.
File-backed previews resolve imported heading/block subpaths after explicit location.
Saved pages reopen their bound browser tabs; captures and saved AI results keep
their structured inspectors.

![Native inline Markdown editor](../artifacts/canvas/03-inline-editor-native-render.png)

## Connect evidence

Drag a side dot to another card, or to empty ground to create a connected card.
Select a line for color, label and arrow controls. Its endpoint handles reconnect
it to existing cards. Visual lines remain separate from semantic knowledge links.

![Selected connection with compact label and arrow controls](../artifacts/canvas/04-selected-connection-native-render.png)

## Navigate and exchange

Space-drag or middle-drag pans. Command-scroll/pinch zooms around the pointer;
Shift-1 fits all and Shift-2 fits selection. Command-0 returns to 100% while
preserving the world point at the centre. Undo/redo restore complete actions.
The settings menu contains snapping, read-only mode, `.canvas` import/export and
Locus's source/capture/inspiration actions.

`.canvas` preserves JSON Canvas node/edge IDs, ordering, colors, labels, directions
and unknown fields. Imported paths need explicit file location before access.
This export does not bundle Locus capture assets or replace a full workspace backup.

Exact Obsidian capability parity is **not complete**. The
[parity contract](OBSIDIAN_CANVAS_PARITY.md#remaining-differences-exact-parity-is-not-complete)
lists the remaining note/vault semantics, renderer, embed and release-validation work.

## Editing files inside a card

Double-click a granted Markdown/text file card, or choose Edit from its context menu. The editor opens the whole file. Save with Command-S or the contextual Save button; Command-Return saves and closes. For files outside a connected vault, Escape or clicking outside keeps a draft without changing the file. Connected-vault files autosave and flush on departure, pausing on conflicts. Reopening the card restores the draft, including after restart. The ••• menu provides Save copy and confirmed Discard. External changes block saving over the original. Canvas undo controls card/object changes; native text undo works while editing.

See [file editing contract and evidence](CANVAS_FILE_EDITING.md).

Connected-vault workflows and richer native previews are documented in [Vault autosave and embeds](CANVAS_VAULT_AND_EMBEDS.md).
