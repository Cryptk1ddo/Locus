# Video picture-in-picture

PiP preserves the playing tab's WKWebView and source player. It does not reload
or download a second copy of the video. Hover exposes the native controls;
leaving the panel hides them. Focused keyboard actions expose the controls too.

- Scrub the timeline to seek within the recording's available media ranges.
- Elapsed/duration uses a compact clock, including hour-long recordings.
- Right-click PiP → Playback speed offers 0.5×, 0.75×, normal, 1.25×, 1.5× and 2×. The checkmark follows the source player; returning keeps that speed.
- Mute/unmute operates on the source video. Zero-volume video can be unmuted.
- Return closes PiP, selects the source tab and brings forward its browser window.
- Close returns the player to its tab while keeping the current browser selection.
- Dragging, resize, docking and source-player isolation retain the existing paths.

| Focused-window shortcut | Action |
|---|---|
| Space | Play/pause |
| Left / Right | Back / forward 15 seconds |
| M | Mute/unmute |
| Return | Return to the source tab |
| Escape / Command-W | Close PiP |

Live/unseekable video does not display a misleading finite scrubber. Live DVR
streams can step through real seekable ranges without advertising a finite total.
Loading, buffering, ended, playback error and missing-player states are displayed
separately from Live. Ended video exposes Replay. A replaced player is followed
inside its original container even when paused or still loading. During a missing
player gap, actions cannot fall back to an existing background video. Recovery
does not force autoplay. Whole-player/container replacement remains a heuristic;
DRM and cross-frame players are not added by this refinement.

Playback UI refreshes from the source at the existing half-second cadence;
play/pause callbacks update the button from the result, rather than assuming play
succeeded. A scrub in progress is not overwritten by a timer update.

![Native PiP controls](../artifacts/refinement/pip-native-render.png)

This is a native QA render from a generated local video, not a desktop screen
capture. Hidden WebKit snapshots may omit the video plane; the black background
in this control render is not evidence of blank playback. Actual player state,
seeking and continued WebKit ownership are checked separately by native probes.

The test fixture is `Tests/pip_controls.py`; the existing CSS/video isolation
regression is `Tests/float_video.py`. DRM, cross-frame players, OS versions,
keyboard/VoiceOver behavior and performance still need the release matrix.

The replacement/status/speed checks are in `Tests/pip_refinements.py`; portable-import and PiP acceptance evidence is in [CANVAS_IMPORT_PIP_REFINEMENT.md](CANVAS_IMPORT_PIP_REFINEMENT.md).

The [saved-preview/PiP polish slice](CANVAS_PREVIEWS_PIP_POLISH.md) keeps loading, buffering, missing-player and error captions visible while controls are hidden. Portrait/square metadata fits the native panel within screen bounds; live resize and docking defer reshaping.
