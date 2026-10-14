# Locus performance work · 2026-10-13

The browser stays on Swift/AppKit/SwiftUI and the existing WKWebView engine. This pass targets measured main-thread work and unnecessary filesystem work before considering a foreign-language module.

## Measurement contract

Use disposable native profiles with generated local files. Compare the same binary configuration, dataset, frame size and frame sequence before/after. Report median/p95 Canvas frame work, file-probe counts and browser-process physical footprint. This footprint excludes WebKit helper processes, so it is not total browser RAM. Avoid website/network variance and user data. Debug timings describe this fixture, not general browsing speed.

## Native changes

Separate Canvas geometry invalidation from content invalidation; coalesce change notifications; cache failed image/text lookups as well as successful ones; cache decoded edges per committed revision and cull offscreen curves. Preserve editing, undo, external file refresh, live-embed bounds and accessibility.

Replace per-Wall two-second main-thread vault scans with one native recursive filesystem-event stream per active Space and coalesced utility-queue indexing. Explicit refresh remains synchronous for command/fixture callers. Disconnect/reconnect invalidates in-flight results; no surface means no watcher. Watcher creation failure uses a slow bounded fallback. The existing explicit folder grant remains the authority boundary.

Watch up to 32 visible granted files with native vnode sources. Attribute events invalidate content only when file size, modification time or permissions change; bookmark-read attributes must not trigger a cache/read/event loop. Writes, replacement, deletion and revocation still invalidate. Files returning from an unobserved viewport discard old cache entries. Focus refresh remains a recovery path. Files beyond the observation budget refresh through their connected vault, focus refresh or when entering the observation budget.

Each surface limits its image cache to 64 entries / 64 MB of estimated decoded pixels and text cache to 64 entries / 8 MB of estimated text storage. Missing previews are cached too. These are cache budgets, not limits on the browser's total memory. Decoded edges follow committed revisions; transient geometry does not decode them again. Curve culling uses the conservative cubic control hull so a connector crossing the viewport survives even when its endpoints are outside it.

Night Colors releases its 400 ms animation polling interval while its document is hidden and restores it for a visible adapted document. Mutation handling remains event driven.

No user preference defaults or sleep safety exemptions change. Lazy tab restoration and the webpage as the primary UI remain intact. Broader cold-start, total WebKit memory and real-site energy profiling remain separate acceptance work. This pass introduces no Rust bridge or third-party runtime.

Apple API reference: [FSEventStreamSetDispatchQueue](https://developer.apple.com/documentation/coreservices/1444164-fseventstreamsetdispatchqueue), [FSEventStreamCreate](https://developer.apple.com/documentation/coreservices/1443980-fseventstreamcreate).

## Measurements

One ARM64 macOS 27 host, 1180 × 728 pixel native bitmap, twelve generated Markdown file cards, 500 offscreen cards, 499 offscreen edges and a 612-file vault. Ten warmup frames, then three runs of forty pans per binary. The final Debug comparison ran sequentially without a concurrent compiler or regression suite. Values below are the median of the three run medians or p95 values.

| Operation | Baseline Debug | Optimized Debug | Optimized release |
| --- | ---: | ---: | ---: |
| Native capture + queued layout median | 184.43 ms | 75.04 ms | 74.94 ms |
| Native capture + queued layout p95 | 213.70 ms | 106.55 ms | 115.92 ms |
| File preview/text probes per 40 frames, median | 1,745 | 0 | 0 |
| Edge decodes per 40 frames, median | 115 | 0 | 0 |
| Browser footprint after each run | 90.4–102.4 MiB | 95.8–96.0 MiB | 97.0–97.2 MiB |

Debug median work fell 59.3%; p95 work fell 50.1%. This measures native `cacheDisplay` rendering and queued layout, **not onscreen FPS or general browsing speed**. No pre-optimization release baseline was built, so the release column is an absolute measurement. Memory savings are not established; helpers are excluded and allocations vary. The current stripped ARM64 release executable is 7,303,856 bytes (6.97 MiB), not the total app footprint. Earlier 2360 × 1456 captures are retained separately and excluded from these percentages.

Raw runs, binary identifiers, hashes and comparison limits are in [comparison.json](../artifacts/performance/comparison.json) and [validation.json](../artifacts/performance/validation.json). An intermediate watcher loop was identified with test-only invalidation counters; the final benchmark and a dedicated native regression now confirm preview reads do not invalidate themselves.

## Validation and remaining work

206 model tests passed. The final signed release passed 180 native checks covering cache reuse, external/atomic/offscreen edits, shared vault lifecycle, idle scans, hidden motion polling, Canvas gestures, tabs, file editing/autosave, rich embeds, import/export and Night Colors. The Xcode application target built successfully and passed seventeen startup, rendering, restoration and WebKit recovery checks. Strict signature verification passed for the release app; `build/Search.app` contains that release build.

Reproduce the current release fixture and resource checks:

```sh
./build.sh release
SEARCH_TEST_APP="$PWD/build/Search.app" python3 Tests/browser_performance.py \
  --output artifacts/performance/local-release.json
SEARCH_TEST_APP="$PWD/build/Search.app" python3 Tests/browser_resource_limits.py
swift test
```

Cold image decoding and explicit vault refresh can still perform synchronous work. Large live web embeds, total WebKit helper memory, cold launch and real-site energy need separate profiling. The next optimization should follow those measurements; this pass does not establish that every browser workload is faster or lighter.
