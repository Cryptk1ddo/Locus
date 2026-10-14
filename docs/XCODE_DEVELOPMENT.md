# Native Xcode launch

The Swift package target is an executable, not a macOS application target.
Running it from Xcode's package scheme gives a `Debug/` main bundle with no
application identifier. The notification-center guard prevents its launch
exception, but that launch still lacks the app identity used by macOS services.

Open `Locus.xcodeproj` and select the shared **Locus** scheme. It compiles the
same `Sources/Search` files into `Search.app`, with a development bundle
identifier (`com.cryptk1ddo.locus.development`), the existing browser entitlements
and usage descriptions. SwiftPM and `build.sh` remain
available; release signing, branding and distribution are unchanged.

The Xcode scheme sets `SEARCH_PROBE=locus-xcode`, so its settings, tabs and
workspace files use an isolated development profile. WebKit data is separate
under the development bundle identity. It opens the normal UI;
browser automation is off until enabled in that profile. System notifications
are suppressed for this probe, as in other isolated runs. To exercise actual
notification delivery, use the app produced by `./build.sh debug`.

The first browser is initialized in `SearchApp.init`, after fresh-session cleanup
and before evaluating the scene/menu views. Rendering no longer initializes the
browser and publishes `Front.browser` in the same SwiftUI update.

WebKit owns its sandboxed child processes. Their diagnostic output is checked
alongside actual page behavior; the project uses the existing app entitlements.
No framework-private sandbox entitlement or blanket exception is introduced.

Page-crash recovery keeps the existing `Tab.recoverFromCrash` loading path.
Every page in the active split should recover immediately when WebKit reports
process termination, including the pane without keyboard focus. Background
tabs remain deferred until selected. The startup regression checks the mounted
view's geometry, visibility and first-frame state, and terminates only a WebKit
process reported by its uniquely identified disposable app. Optional native
window renders provide visual evidence alongside document readiness.

The Xcode target uses a synchronized source folder (Xcode 16 or newer), Swift 5
language mode and the existing macOS 14 deployment target. Unit tests continue
through `swift test`; the application target does not duplicate the test target.

## Validation

Validated on 2026-10-01:

- The shared Xcode scheme built successfully with ad-hoc signing. The produced
  bundle has `APPL` package type, the development identifier, executable and
  usage descriptions. Signature verification passed.
- The existing `build.sh debug` app build also passed.
- All **78 Swift tests passed**, with the 71 non-download tests and 7 existing
  WebKit download tests run separately during startup validation. After the
  split-recovery change, the 71 non-download tests passed again; a repeat of
  the download suite passed 5 tests and timed out in the Space-deletion and
  pause/resume cases. Both failures then passed in individual reruns (3.45 s
  and 4.31 s). All 78 tests have therefore passed against the final sources,
  with those retries required. The intermittent WebKit download fixture
  timeouts remain recorded separately from the native process-crash regression.
- **17 native Xcode startup checks passed**, including completed page loading,
  JavaScript, navigation, mounted/visible split pages, actual WebKit process
  termination and recovery in both focused and unfocused panes, Space-local
  objects and restart.
  No SwiftUI publication warning or missing-main-identifier warning occurred.
- Existing fresh-window/session cleanup regressions: **7 checks passed**.
- `git diff --check` passed.

The previous app build reproduced the SwiftUI publication warning in the same
diagnostic runner. The native app with initialization moved earlier did not.
The first-page check polls actual page readiness instead of assuming that a
cold WebKit process completes its first navigation within 700 ms.

Before the split-recovery change, the same runner passed 16 checks and failed
the unfocused-pane crash check: the pane retained its view but lost its document.
Using the active split's visible tab IDs instead of only `activeID` for immediate
recovery resolved that failure without switching keyboard focus.

The single-page and recovered-split images were visually inspected. They are
native app renders: `bench picture` composites the existing WKWebViews' snapshots
with AppKit window chrome while the disposable test app is off screen. They are
not screen captures of a user's session or mockups. See `artifacts/startup/`.

Shortcuts (`com.apple.linkd.autoShortcut`) and WebKit child-process diagnostics
still appeared in these isolated runs. The page/navigation/restoration checks
passed despite them. This validates those workflows; it does not establish that
every system message is harmless or cover an unspecified failing website.

Reproduce:

```sh
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Debug \
  -derivedDataPath /tmp/locus-xcode-derived build
python3 Tests/xcode_startup.py \
  --app /tmp/locus-xcode-derived/Build/Products/Debug/Search.app \
  --screenshots artifacts/startup
```

The runner signs a disposable copy with a unique test bundle identifier, uses
local webpages and an isolated browser profile, and captures stdout/stderr.
It removes its own browser profile and unique WebKit/cache containers, and
keeps diagnostic logs under `/tmp/locus-xcode-startup.*.log`. The Xcode
development profile and production browser session are not used by the runner.
