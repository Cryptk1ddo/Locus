Locus 0.1.3 is the first packaged development snapshot of the current browser.

- Contextual Spaces, visual Wall and structured workspace objects.
- Native Canvas notes, file previews, imports/exports and vault integration.
- UI capture, Night Colors, PiP refinements and recent performance improvements.
- GitHub release checks, issue reporting, CI and repeatable macOS packaging.
- Separate Locus app identity, original icon and installed profile.

Download `Locus-arm64.dmg` for Apple Silicon or `Locus-x86_64.dmg` for Intel.
Drag Locus into Applications. ZIP downloads are also available.

These are ad-hoc signed development builds, without Apple notarization. macOS may
block first launch until you approve it in Privacy & Security. Updates are manual
through GitHub for now. Existing Search/development profiles are not automatically
imported; retain them and export/import data explicitly.

Known remaining work: Developer ID signing and notarization; signed update-path
QA; profile migration tooling; recursive Markdown/vault asset packaging; saved-link
preview restoration; real-site/DRM PiP, VoiceOver and broader native release QA.

Validation: 209 local tests and 17 isolated native launch/navigation/restoration
checks passed. Hosted CI runs 202 model/security tests; seven live WebKit download
checks remain part of local native QA. Hosted-runner timeouts and the broader
release matrix are tracked in [issue #5](https://github.com/Cryptk1ddo/Locus/issues/5).
