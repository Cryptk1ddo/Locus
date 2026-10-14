# Canvas content and video PiP refinement

This slice preserves the native Canvas engine, shared Space object store and
existing PiP WebKit handoff. No replacement browser/player is introduced.

Canvas content: recognize note wiki links within the current Space; navigate to
existing objects without treating note text as file authority. Preserve heading
and block references in links and resolve them in previews. Text-card checkboxes
change their exact source marker in one undoable WorkspaceStore action; stale
source and read-only checks apply. File-backed previews remain read-only in this
slice. Full Markdown/transclusion, vault roots and file editing remain tracked in
the parity contract.

PiP: add elapsed/duration, a seekable native timeline, mute, accessible buttons
and focused-window keyboard shortcuts. Playback state comes from the isolated
video element and refreshes at the existing half-second cadence. Finite media
seek only within actual seekable ranges; live/unseekable video does not offer a
misleading scrubber. Live DVR recordings retain bounded 15-second steps inside real seek ranges.
No duplicate video, network request or download is used.
Existing return/close, docking, dragging, resize and source-tab ownership remain.

Verification uses synthetic notes and local test media in disposable profiles.

## Implemented behavior

Wiki links accept aliases, heading/block targets and current-note fragments.
Ambiguous/missing targets open no file and do not silently select an arbitrary
note. Code spans and fenced code retain literal syntax. Heading scrolling uses
the actual document section rather than the first matching word. Imported
Markdown file subpaths resolve only through an existing explicit file grant.

Checkbox clicks change the exact source marker, retain the surrounding source
and commit once. Undo restores the original source. Read-only and stale-object
checks apply. Selected previews retain native scroll behavior and explicit links.

PiP keeps the original live page. Its timeline clamps to actual seek ranges;
paused playback, mute, elapsed time and keyboard actions reflect the source.
Scrubbing is protected from the periodic progress refresh. Live DVR can step;
unseekable media cannot. Return restores the owning browser window.

## Workflow evidence

![Selected task card and wiki link](../artifacts/refinement/canvas-content-native-render.png)

See [the PiP controls gallery](PIP_WORKFLOW.md). All images are native QA app
renders with synthetic notes/local media, not desktop screenshots. The PiP
render may omit the video plane while the test app is hidden; playback and seek
state are verified independently. Verification logs and provenance are recorded
in `artifacts/refinement/validation.json`.
