# Canvas import and PiP refinement contract

This slice preserves the tab-owned WKWebView, native Canvas and shared object model.

## Portable import

Wall options → Import → Portable folder chooses an explicit folder containing `Wall.canvas`. Only directly referenced regular files and group backgrounds inside that chosen folder receive individual security-scoped bookmarks. Absolute paths, traversal, symlinks and missing files stay unresolved. JSON alone still grants no access. The manifest is informational, not authority; unrelated files and preview entries are not imported. Imports add to the current Wall at its center and enter undo as one transaction. Existing objects, vault configuration and source files are unchanged. Limits match export: 2 MB JSON, 200 assets, 20 MB per asset and 100 MB total. Oversize or invalid documents fail before the workspace changes.

## PiP

Continue moving the same WKWebView, without a second player or a reload. Distinguish loading, buffering, ended, unavailable and playback error from live playback. Disable media actions when no player is attached. If a site replaces its player, prefer a replacement inside the original player container, including paused/loading video; do not control an unrelated video while waiting for a replacement. Preserve authored volume and playback speed. Add a native right-click Playback speed menu rather than permanent chrome. Return/close and docking retain their existing behavior. Polling callbacks remain scoped to the active floating session.

Validation: model tests for states, import containment and atomic undo; disposable native app probes for replacement, replay, speed, missing player and portable round-trip. Real streaming sites, DRM, cross-frame players and visible hover remain release QA.

## Acceptance evidence · 2026-10-05

191 model tests and 109 native checks passed. New native suites cover 14 PiP state/replacement/speed cases and 9 portable import cases; existing controls, video isolation, Canvas gestures, exports, vault embeds, file editing and content suites also passed. SwiftPM signed debug and Xcode Debug builds passed. Strict deep signature verification passed for the disposable app. [Validation manifest](../artifacts/canvas-pip-refinement/validation.json) contains the build hash and suite counts.

![Portable import native render](../artifacts/canvas-pip-refinement/canvas-import-native-render.png)

![Paused PiP controls native render](../artifacts/canvas-pip-refinement/pip-paused-native-render.png)

These are AppKit app renders from synthetic fixtures, not desktop screenshots. Hidden WebKit may omit the video plane, so the PiP image illustrates controls only. Loading/buffering/error states use explicit test overrides; replay, speed, paused replacement, source ownership and return/close checks use generated local media. Real-site and visible interaction QA remain.

The later [saved-preview/PiP polish slice](CANVAS_PREVIEWS_PIP_POLISH.md) restores contained saved link previews as owned inspiration assets. The initial direct-file-only scope described above is superseded for these validated link previews.
