# Locus

A native macOS browser with contextual Spaces, a visual Wall, structured objects,
Canvas files, UI capture and a local browser automation interface. Built with
SwiftUI, AppKit and WKWebView, preserving the lightweight architecture of
[Search](https://github.com/driceroland/Search).

[Download releases](https://github.com/Cryptk1ddo/Locus/releases) ·
[Report a bug](https://github.com/Cryptk1ddo/Locus/issues/new/choose) ·
[Development workflow](docs/DEVELOPMENT.md)

Locus is in active development. Current downloads are ad-hoc signed development
builds; Apple Developer ID signing and notarization are planned. Review
[release notes](docs/RELEASE_NOTES.md) before installing.

## Build and run

Requires macOS 14+, Xcode 26 or newer (Swift 6), and Python 3.11+. Extensions need macOS 15.4+.

```sh
swift test -c release --arch arm64 --jobs 2 -Xswiftc -Osize
python3 scripts/package-app.py --arch arm64
open build/release/arm64/Locus.app
```

For Intel, use `--arch x86_64`. The package command creates `Locus.app`, a ZIP,
a drag-to-Applications DMG, checksums and a GitHub update manifest under
`build/release/<architecture>/`. `scripts/verify-package.py` verifies these outputs.

`Locus.xcodeproj` provides an isolated development Run configuration. The inherited
`build.sh`, `bench` and SwiftPM target retain the internal name `Search` so existing
regression probes continue to work. Distributable packages use the name **Locus**,
bundle identifier `com.cryptk1ddo.locus` and an original icon.

## Updates and development

Every pull request and push to `main` runs model/security tests, a secret scan
and an Apple Silicon package build. Version tags run tests, build Apple Silicon
and Intel packages, and publish GitHub Releases. See [DEVELOPMENT.md](docs/DEVELOPMENT.md)
for the branch, issue and release workflow.

The app checks this repository's release manifest at launch and hourly. Development
builds announce newer releases and open GitHub for manual download. Signed
installations require a signed manifest, archive checksum, matching bundle identity
and Developer ID team before replacing the app; configuration is documented in
[DEVELOPMENT.md](docs/DEVELOPMENT.md). The browser never executes a GitHub branch.

## Locus workspace features

**Night Colors** is an opt-in built-in extension under **Settings → Extensions**. It adapts page surfaces, text and accents to the dark browser canvas while retaining photos, video and artwork. Automatic follows browser appearance and retains detected native dark themes; each site can use Automatic, Always adapt or Off. See the [contract, controls and native renders](docs/NIGHT_COLORS.md).

The **Wall** button beside Bookmarks opens the current Space’s Wall in its own tab. **View → Open Wall** and the Space menu select that same tab. Switch back to a page without closing the Wall; Command-W closes the selected tab. **Add** names the source page from which the Wall was opened and saves a page or note, collects inspiration from the loaded page, saves an inspiration link, or invokes **Capture UI**. Pinterest, Are.na, Behance, Dribbble and Awwwards references share the same object model. Visited pages can retain a local viewport preview; a saved board link does not import its contents.

Wall now uses a native Canvas interaction model: double-click ground to add text, double-click a text card to edit Markdown in place, drag ground to select, Shift-click to extend selection, and drag selected cards together. Space-drag or middle-drag pans; pinch or Command-scroll zooms around the pointer. Resize any card edge, Option-drag to duplicate, and use Command-Z / Shift-Command-Z for undo/redo. Four side handles create selectable, labelled connections. Groups, preset/custom colours, file/media/PDF cards, live web cards, image paste, and `.canvas` import/export are available through floating tools and contextual menus. See the [native Canvas workflow](docs/CANVAS_WORKFLOW.md) and [Canvas contract and parity tracking](docs/OBSIDIAN_CANVAS_PARITY.md). Exact Obsidian parity remains incomplete.

Canvas caches, shared native vault watchers and hidden-page motion polling are covered by the [performance contract and measurements](docs/PERFORMANCE.md).

Granted Markdown/text file cards edit in place with restart-recoverable drafts and external-change protection. Files outside the connected vault use explicit Save. See the [file editor contract](docs/CANVAS_FILE_EDITING.md).

Whole-Wall and selected-card exports now include portable folders with recursively referenced granted Markdown/media files and saved previews and native PNG/PDF overviews. See [Canvas exports and sample output](docs/CANVAS_EXPORTS.md).

Connect a folder through Wall settings to enable vault-note autosave. Local images, Markdown tables and note/heading/block embeds now render natively. External file changes pause saving and keep recovery drafts. See [vault workflows](docs/CANVAS_VAULT_AND_EMBEDS.md).

Selected Canvas text cards support Space-local wiki links with aliases and heading/block targets, plus undoable task checkboxes. See the [content and PiP refinement](docs/CANVAS_PIP_REFINEMENT.md).

Video picture-in-picture now includes a seekable timeline, elapsed/duration display, mute and focused-window keyboard controls. Return brings forward the source browser window. Live streams show Live; DVR stepping uses available seek ranges. See the [PiP workflow](docs/PIP_WORKFLOW.md).

Connect research, notes, captures and design references; drag cards, resize their edges and pan/zoom the canvas. View positions are remembered per window and Space. Captures keep their DOM/CSS/geometry inspector. A completed page AI answer has an explicit **Save to Wall** action with source/model attribution; private conversations remain ephemeral. Use `wall: words` in the existing address field to find objects.

Drag web links onto the Wall canvas to save inspiration at that location. A drop accepts up to 20 links, recognizes the existing providers, and saves the batch together without loading its pages. Drop positions respect pan and zoom. See the [link-drop contract](docs/WALL_LINK_DROPS.md) and [workflow screenshots](docs/WALL_LINK_DROP_WORKFLOW.md).

Each Space keeps a previous Wall revision. A corrupt Wall offers explicit recovery while preserving its damaged file. Local previews have integrity checks and a per-Space quota; tabs keep working if workspace storage fails. See the [storage contract](docs/STORAGE_RECOVERY.md) and [native Wall tab contract](docs/WALL_TABS.md).

See the [architecture and data contract](docs/INSPIRATION_GRAPH.md), [native workflow screenshots](docs/INSPIRATION_WORKFLOW.md) and [remaining development](docs/DEVELOPMENT_ROADMAP.md). Authenticated Pinterest/Are.na board/channel imports, file/PDF objects and production MCP/agent execution remain separate work.

## Data and privacy

Installed Locus stores sessions, history and workspace objects in
`~/Library/Application Support/Locus/`. Settings and WebKit data belong to its
bundle identifier, and saved passwords use Locus keychain labels. Development
and automated test runs use isolated profiles via `SEARCH_PROBE`. No automatic
migration from Search or earlier experimental profiles occurs; keep those profiles
until you have explicitly exported/imported the data you need.

GitHub update checks contact GitHub. Feedback opens an issue draft for you to
review and submit. Page content stays local unless you explicitly use a configured
AI provider. Secrets and private browsing data must never be committed or posted
in issues. The local `bench` socket is opt-in for installed apps.

## Attribution and license

Forked from [cryptk1ddo/locus](https://github.com/cryptk1ddo/locus), based on
[Search by Drice Roland / Office Commun](https://github.com/driceroland/Search).
The original MIT copyright and license remain in [LICENSE](LICENSE).
Upstream history and internal implementation names are retained. The Locus package
uses its own branding; historical upstream changelog and roadmap entries are
reference material, while GitHub Issues track Locus development.
