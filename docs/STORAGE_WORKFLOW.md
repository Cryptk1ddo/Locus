# Native workspace recovery workflow

Captured 2026-10-01 from the actual SwiftUI/AppKit Wall and capture inspector.
The hidden Bench app uses a disposable profile and a local sample page. The
Pinterest card is a saved URL reference; it does not represent an account import.
Only test workspace files were damaged. No user session is included.

## Keep structured evidence when its preview is damaged

New UI captures and collected inspiration record a PNG byte count and SHA-256
digest. Missing, invalid or changed previews show an availability message. The
object's DOM/CSS, notes, sources and links remain readable.

![Capture inspector retains structured evidence](../artifacts/storage/01-damaged-preview.png)

## Explicitly restore the previous Wall

A corrupt current snapshot opens read-only. The error banner offers recovery
only when a previous snapshot validates for the same Space. The confirmation
shows its revision/object count and warns that later changes may be absent.
Locus archives damaged bytes before restoring the previous save. Newer-schema,
oversized, wrong-Space and unsafe-path files are preserved without downgrade.

![Native recovery choice](../artifacts/storage/02-recovery-choice.png)

## Continue the Space's research

Recovery restores objects, placements, relationships and local previews. Saved
page bindings survive session saves and undo-close while storage is unreadable;
opening the recovered page reuses its restored live tab. Normal browsing keeps
working while a workspace error is present.

![Recovered inspiration and UI research canvas](../artifacts/storage/03-recovered-wall.png)

The rolling backup retains deleted previews for one revision. Cleanup removes
only unreferenced owned UUID-named PNGs, preserving opaque future payloads,
unknown files and assets potentially needed by damaged archives. Those retained
assets count toward the 256 MB/4,000-entry quota.

## Reproduce and validate

Build the debug app and run `python3 Tests/workspace_recovery.py artifacts/storage`.
If a browser already uses the build path, copy the bundle to a disposable
directory and set `SEARCH_TEST_APP=/absolute/path/Search.app` for the runner.
All automated state lives in `Search (workspace-recovery-tests-<checkout>)` and
is cleaned up afterward. `artifacts/storage/manifest.json` records provenance.
The recovery probe calls the same store method as the confirmation button;
this Bench runner does not interact with the alert. Separate native desktop QA
verified the confirmation text, Cancel preserving the damaged file, and Recover
restoring the prior card/exact bytes while archiving damage. Its evidence is in
`artifacts/storage/desktop-qa.json`. Images are native view renders,
not mockups or full desktop screenshots.

The final sources passed all **102 Swift tests**, including 15 new storage
failure/recovery fixtures and the seven existing download fixtures. All **133
native checks** passed: recovery (19), UI Sniper (20), session/Space/window
bindings (20), page/reference lifecycle (27), inspiration/graph/AI (30), and
bundled Xcode startup/WebKit process recovery (17). Both the signed SwiftPM app
and the native Xcode Locus scheme built successfully. `git diff --check` passed.

An ordered background writer/quit flush, migrations and storage performance
budgets remain pending. See [STORAGE_RECOVERY.md](STORAGE_RECOVERY.md) for the
contract and [DEVELOPMENT_ROADMAP.md](DEVELOPMENT_ROADMAP.md) for remaining work.
