# Canvas file editing

Markdown and UTF-8 text files with an existing user-granted bookmark can be edited inside their Wall card. The editor always opens the whole file, including when the preview targets a heading or block. Unsupported objects and read-only Walls cannot start or save an edit.

File editing uses a separate, bounded draft sidecar per object in its Space. Drafts contain the original bytes, bookmark identity and edited text. They survive leaving the Wall or restarting; they are not part of Canvas snapshot undo. Native text undo applies while editing. Files outside a connected vault use explicit Save / Command-S; Command-Return saves and closes. Escape or clicking outside pauses those drafts without writing the source. Connected-vault files can now autosave safely; see [vault and embeds](CANVAS_VAULT_AND_EMBEDS.md). Discard requires confirmation.

Save coordinates access to the bookmarked file and compares its current bytes with the original before atomic replacement. External changes, revoked grants, changed object identity, and competing draft writers block replacement. The draft remains recoverable; Save a copy uses a new user-chosen destination. Cooperating macOS editors participate in file coordination; applications that ignore coordination can still race, so this is not a general distributed file lock.

Only regular UTF-8 .md/.markdown/.txt files up to 1 MB are editable. UTF-8 BOM and uniform CRLF line endings are preserved. Drafts have a 3 MB encoded limit and a 16 MB total Space budget. Invalid/future drafts are left untouched. Failed draft writes retain the live editor and offer Save a copy; forced process termination during a failed write can lose unsaved input.

This extends the existing Canvas surface and security-scoped file access. Canvas undo does not restore external bytes. The subsequent vault layer adds opt-in folder access and autosave for its granted files. Full Obsidian parity remains incomplete.

## Workflow evidence

![Native file card editor](../artifacts/file-editing/editor-native-render.png)

This is an AppKit render from a disposable browser profile with synthetic local Markdown, not a desktop screenshot or mockup. The inline editor shows raw Markdown and an explicit Save button; its contextual menu holds Save copy and Discard.

The native workflow runner is `Tests/canvas_file_editing.py`. It checks complete-file editing, draft pause/reopen/restart, both save shortcuts, text undo/redo, clean-draft cleanup, fresh external contents, missing-source recovery, read-only protection and unchanged Canvas snapshot history. Model tests separately cover external-change conflicts, concurrent draft writers, encoding, limits, corrupt/future drafts and source aliases.

Save-copy and Discard panels still need manual release QA. Connected-vault metadata polling and cross-window save notifications now refresh previews. Background draft commits and fuller vault semantics remain further work.

Validation: the full Swift suite passes 147 tests, including 10 file-draft tests. The final native runs pass 12 file-editor, 19 Canvas, 4 content and 10 PiP checks (45 total), using disposable profiles. Logs and the native render are under `artifacts/file-editing/`.

The signed debug app and Locus Xcode target both build successfully. The machine-readable record is `artifacts/file-editing/validation.json`.
