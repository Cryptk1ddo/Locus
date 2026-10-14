# Locus: remaining development

Assessment date: 2026-10-05. This counts acceptance-tested milestones, not commits
or prompts, and is an engineering estimate rather than a completion guarantee.

The twentieth slice restores contained saved link previews as workspace-owned inspiration assets during portable import, and adds PiP attention captions plus bounded portrait/square sizing. See [CANVAS_PREVIEWS_PIP_POLISH.md](CANVAS_PREVIEWS_PIP_POLISH.md). Recursive vault asset packaging and real-site release QA remain. The nineteenth slice adds portable-folder Canvas import with direct asset/background grants and atomic undo, plus PiP playback speed, loading/buffering/error/ended states, replay and paused player replacement recovery. See [CANVAS_IMPORT_PIP_REFINEMENT.md](CANVAS_IMPORT_PIP_REFINEMENT.md). Recursive asset dependencies and real streaming-site release QA remain. The eighteenth slice refines Night Colors state/motion behavior, modern CSS colors and SVG chart scaffolding, and adds portable Canvas asset folders plus PNG/PDF overviews with selection export. Its boundaries and workflow are in [CANVAS_EXPORTS.md](CANVAS_EXPORTS.md). Full animation-frame transposition, chart-library coverage, recursive vault packaging and release/performance QA remain. The seventeenth slice added the requested Night Colors built-in extension: an opt-in OKLCH color kernel, reversible page adaptation, per-site/private controls and isolated frame policy. Its contract, limits and workflow are in [NIGHT_COLORS.md](NIGHT_COLORS.md). Broader real-site, animated-state and performance validation remain release work; this additional feature does not complete the milestones below. The sixteenth foundation slice added per-Space folder grants, conflict-protected vault autosave and native tables, local images and bounded note/heading/block embeds. Its contract and workflow are in [CANVAS_VAULT_AND_EMBEDS.md](CANVAS_VAULT_AND_EMBEDS.md). The fifteenth foundation slice added native Markdown/text file editing with recoverable drafts, explicit save and external-change protection. Its contract is in [CANVAS_FILE_EDITING.md](CANVAS_FILE_EDITING.md). The fourteenth slice added Space-local wiki/section links, undoable task checkboxes and refined native video PiP controls. The thirteenth added native Canvas interactions and JSON Canvas exchange. The first twelve slices were: upstream architecture audit,
common object/Space store, invoked native Wall, bounded native UI capture, explicit
Space object search, durable page/tab binding, page/reference lifecycle,
visual inspiration/semantic canvas links/saved AI evidence, and workspace
backups/explicit recovery/preview quotas and integrity, and native per-Space Wall
tabs with the toolbar button beside Bookmarks, and bounded native web-link drops
onto the canvas, and contextual Wall creation/card menus/searchable connections/
viewport fitting. The latest contracts are in [WALL_CONTEXT_MENUS.md](WALL_CONTEXT_MENUS.md), [WALL_LINK_DROPS.md](WALL_LINK_DROPS.md),
[WALL_TABS.md](WALL_TABS.md) and [STORAGE_RECOVERY.md](STORAGE_RECOVERY.md).
Search still supplies browser
ownership, WebKit configuration, extensions, AI, passwords and sessions. Locus
has not yet completed the full product direction or release engineering.

Two useful completion boundaries:

- **Core release:** 8 remaining milestones (2–4, 6–7, 12–14 below), roughly
  **12–24 implementation-and-validation slices**. It ships a reliable contextual
  browser/Wall with files, capture and explicit search/AI content actions.
- **Full stated direction:** **14 remaining milestones** (2–15), roughly
  **26–48 slices**, including repository/design objects, deeper capture coverage,
  BrowserControl/MCP and task/agent runtime. These ranges assume the current
  architecture and local persistence; collaboration/cloud synchronization would
  add scope. A slice usually includes schema/contract work, implementation and
  relevant native regression checks. No calendar estimate is justified yet.

The ranges credit completed subfeatures toward milestones 2, 3 and 7 and include
the requested authenticated inspiration integration (15). Milestones 2, 3 and 7
remain partial: implemented subfeatures do not make these milestones complete.
These remain rough estimates, not a calendar promise.

| # | Milestone | Acceptance boundary |
|---|---|---|
| 1 | Page/reference lifecycle — complete | Undo-close, Clear/group restoration and window transfer binding coverage; explicit saved-vs-live actions; immutable recapture/provenance. See [PAGE_REFERENCE_LIFECYCLE.md](PAGE_REFERENCE_LIFECYCLE.md). |
| 2 | Wall interaction completeness — partial | Native per-Space Wall tabs, semantic/provenance connections, resize, viewport persistence, web-link drops, contextual creation/card menus and searchable connections implemented. Internal object/file drag workflows, fuller keyboard navigation and large-graph interaction QA remain. |
| 3 | Storage and assets ready for release — partial | Previous-revision backups, explicit corrupt/missing-file recovery, orphan reconciliation, quotas, preview checksums and stale-writer rejection implemented. Nonblocking ordered commits/flush, migration tooling and performance/failure QA remain. |
| 4 | Files and PDFs — partial | Explicit import and security-scoped access, inline Markdown/text editing, recovery drafts, connected-vault autosave, bounded native rich previews and reopen after restart are implemented. Portable assets, richer file semantics and release QA remain. |
| 5 | Repository/design object types | Typed repository, UI-reference, token and screenshot actions using the common envelope; enrichment only when requested. |
| 6 | Space context and history | Space-local history/context with a documented migration and intentional treatment of shared sign-ins/private browsing. |
| 7 | Universal field and AI content — partial | Explicit object search and saved page-AI answers with read source/model/cautions implemented. Unified bookmark/history/command routing and richer intentional AI content actions remain. |
| 8 | Capture coverage and export | Deliberate same-origin frame handling, richer assets/fonts/motion evidence and portable export; honest coverage for inaccessible evidence. |
| 9 | Shared browser control layer | Small BrowserControl operations shared by Bench, with explicit window/Space/object targets, errors, cancellation and compatibility tests. |
| 10 | MCP interface | Local transport, scoped authority and job/cancellation lifecycle; private data and captured instructions cannot grant permissions. |
| 11 | Task and agent runtime | Durable task state, bounded execution, resumable jobs, inspectable results and source links; no permanent AI sidebar. |
| 12 | Locus identity and distribution | Deliberate bundle, Keychain and profile migration policy; assets/menus/docs renamed; fork-owned update channels. |
| 13 | Native release QA | macOS/WebKit/extension matrix, restored multiwindow/split/pin states, large workspaces, accessibility, gestures, crashes and performance budgets. |
| 14 | Packaging and release | Signing/notarization, update/recovery verification, onboarding/help and reproducible release artifact. |
| 15 | Authenticated inspiration imports | Approved Pinterest app/OAuth, Keychain tokens, scoped board/Pin reads, paginated preview/deduplication/cancellation; Are.na adapter with visibility rules. Visited-page collection and provider-aware links already work. |

Obsidian Canvas parity remains a requested target. Native Canvas interactions, file/media references and JSON Canvas exchange are implemented; full Markdown/Obsidian note semantics and the remaining parity items in [OBSIDIAN_CANVAS_PARITY.md](OBSIDIAN_CANVAS_PARITY.md) remain acceptance gates. Ordered background commits/flush and storage performance validation (milestone 3) also remain release work. Native gestures and
multiwindow behavior still need a release QA matrix beyond isolated probes. Milestones 9–11 should follow
the object/control contracts; implementing an MCP transport alone does not
complete the agent runtime. Full cross-origin capture fidelity is not a promised
release gate because WebKit and component boundaries restrict access.

## Workflow evidence

The reproducible screenshot runner `Tests/workflow_screenshots.py` uses a separate
hidden test browser and a local sample webpage. Images are native app renders,
not design mockups, and do not include the user's browser session. The inspector
image is rendered separately with the same native view. See
[WORKFLOW_SCREENSHOTS.md](WORKFLOW_SCREENSHOTS.md) for the gallery and provenance.

The connected inspiration/knowledge workflow has a separate gallery in
[INSPIRATION_WORKFLOW.md](INSPIRATION_WORKFLOW.md).

Storage failure/recovery workflow evidence is in
[STORAGE_WORKFLOW.md](STORAGE_WORKFLOW.md).

Web-link drop workflow images and real desktop drag evidence are in
[WALL_LINK_DROP_WORKFLOW.md](WALL_LINK_DROP_WORKFLOW.md).

Context-menu and dialog workflow evidence is in
[WALL_CONTEXT_WORKFLOW.md](WALL_CONTEXT_WORKFLOW.md).
