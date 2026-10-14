# Contributing to Locus

Open a GitHub issue describing a concrete problem and acceptance criteria, then
make a focused branch from `main`. Submit a pull request that links the issue,
explains the resulting behavior and states how it was checked. CI must pass before
merging. Keep the browser core small, the webpage primary and UI invoked when needed.

Use SwiftUI/AppKit/WebKit and Foundation where practical. Avoid unrelated rewrites
and new dependencies for functionality already provided by the system.

Run `swift test -c release --arch arm64 --jobs 2 -Xswiftc -Osize`. For native behavior,
package the app and run the relevant Python probe with `SEARCH_TEST_APP` pointing
to it. Probes must use isolated `SEARCH_PROBE` profiles and synthetic data. Do not
run probes against someone's installed profile. GUI tests require an unlocked Mac
and are tracked separately from model tests in CI.

Release packages come from `scripts/package-app.py`. The inherited `build.sh`
remains available for existing Search-named test tooling. See
[development and releases](docs/DEVELOPMENT.md).

Never commit credentials, signing material, personal session data or build artifacts.
The repository's `.gitleaks.toml` adds AI-provider patterns to standard secret scanning.
Review crash logs and screenshots before posting them in an issue. Security problems
should use GitHub's private vulnerability reporting rather than public issue details.
