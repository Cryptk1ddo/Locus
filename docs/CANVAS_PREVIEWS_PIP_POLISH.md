# Saved Canvas previews and PiP polish

## Data and ownership contract

Portable-folder import may restore `manifest.json` previews only for matching JSON Canvas link nodes. An explicit folder choice remains the authority boundary: preview files must be contained regular PNGs with no symlink/traversal, pass existing image bounds/integrity checks, and fit the existing asset quotas. Titles are bounded data. The importer copies validated PNGs into fresh workspace-owned assets, creates inspiration objects carrying the original sanitized link, and commits cards, edges and snapshots in one undo step. Failed commits remove staged assets; undo/redo retain preview assets through existing history retention. Removing the portable source folder does not invalidate these owned previews. JSON-only imports still grant no access. Invalid/missing/ambiguous previews leave ordinary links and produce an unresolved count. The manifest cannot supply browser authority, bookmarks, object types or workspace asset IDs. Recursive Markdown dependencies remain separate work.

## PiP behavior contract

The existing tab-owned WKWebView stays the player. A small status caption stays visible for loading, buffering, unavailable and failed video when controls are hidden; normal playback hides it again. Metadata may update the native panel's aspect ratio for portrait/square media. Resizing is bounded to the available screen, preserves the top-right corner, and waits during live resize or docking. Unknown/extreme ratios keep the current panel shape. Remembered window geometry is checked against actual media dimensions, including reopening a portrait frame for landscape video. Controls, native shortcuts, seeking, playback speed and Return/Close use the existing paths. No second player, reload or permanent toolbar is added.

Validation uses model tests and disposable native profiles with synthetic PNGs and local video. Real streaming sites, DRM, cross-frame playback, VoiceOver and visible hover still require release QA.

## Workflow

Use Wall options → Import → Portable folder to restore a link and its validated saved preview. It appears as an inspiration object without navigating to the source page. Its title and link survive re-export; the copied preview survives removing the source image, undo/redo and restart. Missing or invalid previews remain plain links with an unresolved-reference count.

PiP automatically adapts to supported portrait/square/landscape dimensions. Loading, buffering and error captions remain visible when you leave the window; ordinary playback restores the unobstructed picture. Playback buttons, speed menu and keyboard shortcuts retain their existing behavior.

## Acceptance evidence · 2026-10-12

198 model tests and 128 native checks passed. This includes eight owned-preview cases and eleven PiP sizing/caption cases, plus existing controls, player replacement, CSS isolation, Canvas gestures, imports/exports, vault embeds, editing and content regressions. Signed Debug and Xcode Debug builds succeeded for the final Swift sources; strict signature verification passed. The [validation manifest](../artifacts/preview-pip-polish/validation.json) records hashes, suite counts and build provenance.

Earlier download timing failures and a disk-full run are retained in the logs. The final full suite passed after removing only generated Xcode caches. The video-isolation fixture now waits for media readiness instead of a fixed delay.

![Saved inspiration preview on Canvas](../artifacts/preview-pip-polish/canvas-saved-preview-native-render.png)

![Portrait PiP loading caption](../artifacts/preview-pip-polish/pip-portrait-loading-native-render.png)

These are AppKit app renders from synthetic fixtures, not desktop screenshots. Hidden WebKit may omit the video plane; the PiP image demonstrates panel shape and caption visibility. Caption readiness/error states use explicit overrides; aspect changes, seeking and continued playback use generated local media. Real-site and visible interaction QA remain.
