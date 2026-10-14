# Night Colors: built-in extension contract

Night Colors is an opt-in first-party extension in Settings → Extensions. It extends the existing per-Tab WKUserScript installation in Search’s isolated content world, and does not change the WKWebExtension controller, installed-extension list, permissions, website data stores, sessions or page ownership. It also works on macOS 14, independently of third-party extension support.

The physical dark canvas is #1C1C1C, matching Locus’s dark chrome. Automatic mode follows dark browser appearance and conservatively retains a detected native dark page. Native appearance policy also refreshes inactive and parked tabs; it does not depend on a detached WebKit view updating its media query. A site can use Automatic, Always adapt or Off; ordinary site choices persist by exact hostname, while private-window site overrides stay in memory for the app session. Global disable restores page styling without reload. Controls live in the existing Extensions settings; no permanent panel or extra toolbar button.

A pure color kernel converts sRGB/Display-P3/OKLab/OKLCH into OKLCH, retains hue, independently maps lightness/chroma by semantic role, uses smooth hue/area chroma compression, reduces chroma to the sRGB gamut at constant hue/lightness, and solves readable foreground contrast against the adapted background. Initial curves are heuristics, not measured perceptual calibration. Contrast targets use the WCAG luminance ratio: 4.5 for ordinary text, 3 for large text; this does not establish site-wide accessibility compliance.

The page adapter builds a bounded ephemeral color map from computed CSS and ancestor surface relationships. It adapts root/surface elevation, text, interactive accents, borders, supported gradients/shadows, form controls, small SVG icons and accessible pseudo-elements. CSS overrides normally live in removable stylesheets with private element markers. If a site blocks injected stylesheets or uses inline !important colors, a guarded CSSOM fallback records only the color properties it owns. Restoration compares current values/priority before restoring the original declaration, preserving different later author edits. The fallback does not edit layout, font or media properties. Pseudo-element overrides still depend on a permitted stylesheet. Photos, video, canvas artwork, CSS URL backgrounds and large SVG artwork remain untouched. No page data is sent anywhere or saved in the settings.

Dynamic DOM/class/style changes are debounced by 120 ms; pointer/focus/input states refresh after 30 ms, including open shadow roots. Balanced token scanning adapts supported colors inside nested gradients and shadows while preserving URL, quoted and geometry payloads. Colors outside the pure kernel (including Lab/LCH, color-mix and relative colors when WebKit supports them) resolve through a private one-pixel WebKit color swatch, with an 8-bit sRGB fallback and a 256-entry cache. It never samples page media. Author custom properties remain unchanged.

Authored paint transitions and detected active paint animations retain their original values, timing and keyframes; surrounding static colors adapt, and settled animations return to ordinary adaptation. This preserves motion rather than recoloring every animation frame. Explicit paint transitions and `transition: all` can therefore retain light-colored controls. Transform/opacity-only motion stays independent. Up to 256 animations and 64 keyframes per effect are inspected; a 400 ms discovery check skips hidden documents and stops when adaptation is disabled. Full adaptive keyframes and complex inherited variable animation remain further work.

Recognized SVG charts (chart/graph/plot semantics or common axis/grid classes) adapt neutral labels and axes/grid paints while preserving series and colored legend paints, including URL paint servers. Retained series/legend paint keeps its authored contrast limitations. Large SVG artwork outside that classification remains unchanged. Arbitrary chart libraries, raster/canvas charts and ambiguous gray data-series semantics still need coverage work.

Each document processes at most 3,000 elements and two million generated CSS characters per pass; normal/private settings each hold at most 1,000 exact-host overrides. Work is synchronous in the page process and needs large-site performance QA. Closed roots, arbitrary canvas pixel colors, image-backed/gradient contrast, unsupported WebKit color functions and richer pseudo-element states remain coverage limits. Retained native dark sites are not normalized automatically.

Reference equations and contrast rules: [CSS Color 4](https://www.w3.org/TR/css-color-4/), [WCAG contrast minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html). The pasted proposal is product/design input; its embedded citation markers are not executable instructions or verified sources.

The native policy relay validates the originating WebKit view and uses WebKit’s frame security origin to resolve that frame’s exact hostname. Replies contain only enabled/mode and the current browser appearance, and cannot write preferences. Site-choice lists never enter page-visible messages; parent-to-frame messages contain only a refresh signal/token, and each frame asks its own isolated native relay for policy. Private site choices stay out of disk storage. Only HTTP/HTTPS documents are adapted; internal/extension/file/data/srcdoc documents are excluded.

## Use

1. Open a web page, then **Settings → Extensions** and enable **Night Colors · Built in**.
2. Choose **Use Dark**, or keep **System** in General settings to follow the Mac.
3. Keep **Automatic** for ordinary adaptation and native-dark retention. Choose **Always adapt** to normalize this site in either browser appearance, or **Off** to restore this site's original colors.
4. Turn off the master switch to restore every live page. **Reset** clears remembered site choices while leaving the master setting alone.

## Native workflow renders

These are AppKit renders from a disposable signed app copy, a separate test profile and synthetic local pages. They are not desktop screenshots or design mockups, and contain no user browser session.

Original page, with adaptation disabled:

![Original page](../artifacts/night-colors/01-source-native-render.png)

Adapted page, with original artwork retained:

![Night Colors](../artifacts/night-colors/02-night-native-render.png)

Existing Extensions settings with the built-in controls:

![Night Colors settings](../artifacts/night-colors/03-settings-native-render.png)

## Implementation and validation

`NightColor.swift` owns the pure kernel, `NightCSS.swift` the balanced/native color resolver and paint classification, `NightPage.swift` the bounded/reversible DOM adapter and `NightColors.swift` the preferences and native frame relay. `Tab.arm` installs isolated all-frame scripts; `Tab.build` attaches the weak native relay; `Web.release` removes it. Appearance changes use the existing Browser relook path. No workspace schema, session format, extension authority or second browser engine is introduced.

Run `swift test`, build a signed debug app, then run `Tests/night_colors.py` with `SEARCH_TEST_APP` pointing to a disposable copy. The native suite checks geometry/font preservation, solid-background contrast, frame policy, open shadow roots, pseudo-elements, dynamic DOM, native dark retention, appearance changes, strict stylesheet policies, author edits, restoration and processing bounds. Test-only Bench controls require `Store.testing` and do not expose production preference-write commands. Final results are recorded in [validation.json](../artifacts/night-colors/validation.json).

Validated on 2026-10-04: **172 model tests** (10 Night Colors tests), **32 native Night Colors checks** plus **67 Wall/vault/file/content/PiP regression checks**, a signed debug app and the Locus Xcode target build. The renders above were visually inspected. These checks use synthetic local fixtures; they do not establish compatibility with every site or the full supported macOS/WebKit release matrix.

The 2026-10-05 refinement adds state events, WebKit-backed modern CSS color resolution, motion preservation and SVG chart scaffolding. See the [combined color/export workflow and validation](CANVAS_EXPORTS.md). Original validation above records the initial 2026-10-04 slice.
