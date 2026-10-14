# Workspace recovery and owned preview assets

Implemented storage slice, 2026-10-01. The contract was written before runtime
changes; native failure cases and screenshots are in
[STORAGE_WORKFLOW.md](STORAGE_WORKFLOW.md). Browser tabs, sessions, WebKit
stores, extensions and Keychain ownership remain upstream responsibilities.
Only the existing Space workspace sidecar changes.

## Commit and recovery

`workspace.json` remains schema 1, with the same opaque-field preservation and
2 MB snapshot bound. Before replacing a committed snapshot, atomically save its
exact bytes as `workspace.previous.json`. A backup-write failure rejects the new
mutation, as does a current-file write failure. Publish only after the current
write succeeds. Compare disk bytes with the last loaded commit before saving;
an external change must be reopened, never silently overwritten. This detects
stale writers but is not a cross-process locking protocol.

A corrupt or missing current snapshot remains read-only. If its previous
snapshot validates for the same Space, offer **Recover Previous Wall** in the
existing error banner. Show the previous revision/object count and require an
explicit in-app confirmation. Preserve the damaged current file under a unique
`workspace.damaged-<UUID>.json` name before restoring the validated previous
bytes. Never silently recover, downgrade a newer schema, recover another
Space's file, follow a symlink, or resurrect an erased Space. Oversized snapshots
also stay read-only without recovery because their version cannot be safely
inspected within the read bound. A recovery-write
failure leaves the UI read-only and the damaged bytes preserved. Session saves,
restoration and undo-close retain unresolved page-object IDs while a workspace
is unreadable; lookup/actions still require a validated supported page in the
current Space. Recovery resolves these retained bindings. Erasing the Space or
validating a snapshot in which an object was deleted rejects the old ID.

## Asset lifetime and integrity

Preview PNGs stay local under `assets/<UUID>.png`. New captures record their
byte count and SHA-256 digest in `content.screenshot.value`, alongside the
existing asset ID/MIME. Legacy objects without those fields remain readable.
Validate PNG size, dimensions and decodability before accepting a new preview;
verify recorded integrity before displaying it. Missing or damaged previews do
not prevent the object's text, links and captured metadata from opening.

Keep assets referenced by either the current or previous snapshot. Deleting an
object removes its relationships/placements immediately; its PNG remains for
one previous revision so recovery can restore the visual evidence. After the
next successful commit, or on a valid reopen, remove only unreferenced regular
UUID-named PNGs. This also reconciles assets staged before an interrupted JSON
commit. Preserve unknown files and symlinks. Skip cleanup if either snapshot
cannot be understood, including unsupported object payloads. A preserved damaged
snapshot also suspends cleanup: its assets remain in place for manual repair and
count toward the quota until the archive is reviewed and removed. Locus does not
automatically discard damaged archives.

The Space asset directory is bounded to 256 MB and 4,000 entries for new writes;
each PNG remains limited to 4 MB and 2,000 × 4,000 pixels. Include retained
previous-revision assets in this quota. Rejection must preserve the prior
snapshot and remove a newly staged asset. Space deletion still removes the
whole owned workspace, including backups and retained assets.

## Acceptance and remaining work

Exercise failures before both backup/current writes and recovery writes;
corrupt/missing/newer/wrong-Space snapshots; stale external edits; dangling
assets; deletion retention; corrupt checksums; quotas; opaque future payloads;
symlink boundaries; erased-store callbacks; native recovery and restart.
Record real native workflow images using the isolated Bench test profile.
Implemented acceptance: all 102 Swift tests and 133 native checks passed; see
[STORAGE_WORKFLOW.md](STORAGE_WORKFLOW.md) for the gallery and test breakdown.

This slice keeps bounded synchronous commits before publication. An ordered
background writer with explicit completion/quit flush, migration tooling,
performance budgets and broader release QA remain milestone 3 work. A rolling
local backup is not export, cloud synchronization or a disaster-recovery copy.
