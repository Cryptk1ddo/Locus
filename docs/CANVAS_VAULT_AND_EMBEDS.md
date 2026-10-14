# Vault autosave and rich native previews

Each Space can connect one user-selected folder as its vault through Canvas settings. A versioned `vault.json` beside the Space snapshot stores the security-scoped folder bookmark and autosave preference; it is configuration, outside Canvas undo. Existing browser tabs, WebKit configuration, sessions, extensions and the Wall-tab model remain unchanged.

Connecting a folder enables autosave for Markdown/text file cards inside that folder. Editing still immediately keeps a bounded recovery draft. After a short quiet interval, autosave checks the object identity, read-only state, folder membership and original file bytes before coordinated atomic replacement. It flushes on editor departure; conflict stops autosave and keeps the draft. Recovered drafts require explicit Save before automatic writes resume. Files outside the connected folder retain explicit Save. Disconnecting or disabling autosave never writes a pending draft.

Vault-relative paths are authorized only by the explicit folder grant. Resolution rejects traversal and symlinks, stays inside the root, and only returns regular files. A bounded index supports unambiguous wiki resolution; choosing a note or following a link creates the existing file object with its own bookmark. Imported .canvas paths can be bound after the folder grant, without reading arbitrary absolute paths. New note cards can be saved into the vault using an explicit Save dialog. A visible Wall polls bounded vault metadata for changed files; its previews refresh without replacing live editor text.

Native previews retain the NSTextView renderer and source editor. Rich rendering adds Markdown tables, local images and note/heading/block transclusion. Resolution uses known Space objects or the connected vault. Embeds have depth, count and byte limits, detect cycles, preserve source syntax, and never execute raw HTML or fetch remote images. Embedded tasks open their source rather than editing the containing note. Missing/ambiguous/unsupported references show a readable placeholder. Math and executable plugin embeds remain separate parity work.

This delivers working vault-backed autosave and richer native content; it is not a promise of complete Obsidian plugin compatibility, portable vault export or full Markdown parity.

References: [Obsidian embeds](https://obsidian.md/help/embeds), [Apple Markdown presentation intents](https://developer.apple.com/documentation/foundation/nspresentationintent).

## Use the connected vault

1. Open the Space’s Wall tab and choose **Canvas settings → Connect vault…**. Select the folder containing your notes and assets. Autosave is enabled for granted Markdown/text file cards inside this folder.
2. Use **Add note from vault…** to place an existing file, or save a text card with **Save note to vault…** from its context menu. Double-click a file card to edit its full source. Its contextual bar reports Autosaved, or explains that saving paused while a recovery draft is kept.
3. Use `![[Note#Heading]]`, `![[Note#^block]]`, `![[Image.png|240]]`, relative Markdown image paths and ordinary Markdown tables in text cards or file sources. Select a card to use its native reading view. Clicking an embedded source caption opens or selects the source file card.
4. For imported `.canvas` documents, choose **Locate imported files in vault** after connecting the folder. Only existing safe relative file references receive bookmarks. Paths outside the folder still require individual selection.
5. Disable **Autosave vault notes** to keep explicit Save, or disconnect the folder. A recovered dirty draft always requires explicit Save before autosave resumes. Source conflicts require resolving the file difference or using Save copy; Save never silently overwrites an externally changed file.

## Native workflow renders

These are AppKit renders of the running app in disposable profiles using synthetic local files. They are not mockups or desktop screenshots, and contain no user browser data.

![Vault file editor after autosave](../artifacts/vault-embeds/vault-autosave-native-render.png)

![Native section transclusion, table and local image in a selected Wall card](../artifacts/vault-embeds/vault-rich-native-render.png)

## Boundaries and release follow-up

The connected-vault index visits at most 10,000 entries and retains 2,000 regular-file paths. Visible Walls check metadata every two seconds. A preview expands at most 16 embeds across three nested levels and one megabyte of source, with at most eight bounded raster images. Table previews support twelve columns and one hundred body rows. Missing references and limits remain visible; raw source is preserved in the editor.

Vault rename/backlink maintenance, math, embedded canvases, inline PDF transclusion, portable asset packaging, full vault-wide search and Obsidian plugin behavior remain further work. Save dialogs, security-scoped access in a distributed signed app, large-vault performance, accessibility and multiwindow release behavior still need the release QA matrix. Saves notify visible previews across windows; vault polling refreshes external changes without replacing a live editor’s text.

## Validation

The full suite passes 162 model tests, including eight vault and seven rich-Markdown tests. Native checks pass 22 new vault/embed workflows plus 12 file-editor, 19 Canvas, four content and ten PiP regressions (67 total). The signed debug app and Locus Xcode target build, and the diff whitespace check passes. Logs, image provenance and the app hash are recorded in `artifacts/vault-embeds/validation.json`.

These checks verify autosave debounce/exit flush, conflict protection, restart recovery/manual resume, outside-vault explicit saving, disabling/disconnecting/read-only authority, section embeds, tables/images, external preview refresh and source navigation. They do not establish complete Obsidian parity or the release matrix.
