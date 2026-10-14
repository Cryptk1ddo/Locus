Locus 0.1.4 adds portable Canvas dependency packaging and restoration.

- Export referenced Markdown notes and media recursively through existing file or connected-vault grants.
- Preserve fragments, aliases and Markdown titles while rewriting the exported copies to relative asset paths.
- Deduplicate cycles and report missing or ungranted resources in the manifest.
- Restore dependency files without extra Wall cards, with one-step import undo/redo and references scoped to each imported folder.
- Retain saved-link previews, group backgrounds and unknown Canvas data through the existing import/export paths.

Download `Locus-arm64.dmg` for Apple Silicon or `Locus-x86_64.dmg` for Intel.
Drag Locus into Applications. ZIP downloads are also available.

These are ad-hoc signed development builds, without Apple notarization. Updates
remain manual through GitHub. Existing Search/development profiles are not
automatically imported; retain them and export/import data explicitly.

Portable imports bookmark files in the selected folder; keep that folder available.
Exports follow supported local Markdown/wiki syntax within the documented
count/byte/depth limits. Full vault backups, HTML references and recovery drafts
are outside this export. See [Canvas export contract](CANVAS_EXPORTS.md).

Known remaining work: Developer ID signing and notarization; signed update-path
QA; profile migration tooling; real-site/DRM PiP, VoiceOver and broader native
release QA. Hosted CI excludes seven live WebKit download checks, which remain
part of local native QA; this split is tracked in [issue #5](https://github.com/Cryptk1ddo/Locus/issues/5).

Validation: 210 model/security tests and 35 isolated native checks passed; the
Apple Silicon package passed identity, architecture, signature and checksum
verification. The full local attempt hit a live WebKit download timeout; it is
not claimed as a clean 217-test run.
