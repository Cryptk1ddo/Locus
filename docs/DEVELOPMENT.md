# Locus development and releases

The canonical repository is https://github.com/Cryptk1ddo/Locus. GitHub Issues
hold the backlog. Keep `main` usable, create focused feature/fix branches, link PRs
to issues, and merge only after CI and review. Use bug and feature issue forms.
Historical upstream roadmap/changelog files remain as context.

## Local loop

1. Pull `main`, create a branch and implement one issue's acceptance criteria.
2. Run `swift test -c release --arch arm64 --jobs 2 -Xswiftc -Osize`.
3. Build with `python3 scripts/package-app.py --arch arm64`.
4. Verify with `python3 scripts/verify-package.py build/release/arm64`.
5. Exercise affected native flows with synthetic data and a `SEARCH_PROBE` profile.
6. Open a PR and record validation and remaining limits.

Packages use `Locus.app` with executable `Search` and bundle identifier
`com.cryptk1ddo.locus`. The installed profile is `Application Support/Locus`;
Search and earlier development data are not automatically migrated. Preserve those
folders and use explicit exports/imports. Xcode's development scheme and existing
Python probes retain their isolated Search test-world names.

## CI

CI runs on PRs and pushes to `main`: Swift model/security regression tests,
Apple Silicon packaging and verification, plus gitleaks. GitHub retains the
package artifacts for 14 days. Dependabot proposes GitHub Actions updates weekly.
Full native WebKit, Canvas, PiP and performance probes require a GUI session;
passing CI does not claim real-site, DRM, VoiceOver or complete release QA.

## Release

Update `VERSION` and `docs/RELEASE_NOTES.md` in a tested PR. Once merged:

```sh
git checkout main
git pull --ff-only
release_tag="v$(tr -d '[:space:]' < VERSION)"
git tag -a "$release_tag" -m "Locus $release_tag"
git push origin "$release_tag"
```

The release workflow verifies tag/version agreement, runs tests, builds each
architecture, checks identity/signatures/checksums, and creates the GitHub Release.
The tag is the release boundary: ordinary branch pushes do not publish releases.
Never retag an existing version or replace its assets; make a new version for fixes.

The app reads `releases/latest/download/appcast-<architecture>.json`. Each manifest
points to immutable version-tagged ZIP/DMG asset URLs and contains a monotonic UTC
build number and SHA-256 hashes. Unsigned development builds announce new releases
and open GitHub for manual installation; they never automatically replace code.
GitHub's latest channel excludes prereleases. Download the architecture matching
your Mac. Development downloads may require approval in macOS Privacy & Security.

## Signing later

Obtain a Developer ID Application certificate and export it securely for the
release runner. Configure a temporary CI keychain and notarytool credentials,
then supply `LOCUS_SIGN_IDENTITY`, `LOCUS_UPDATE_TEAM` (your ten-character team ID)
and `LOCUS_NOTARY_PROFILE` to `scripts/package-app.py --notarize`. Do not commit
certificates, private keys, passwords or provisioning profiles. The current
release workflow deliberately builds development packages without these secrets.

The script signs the app, DMG and manifest, verifies the certificate's team,
notarizes ZIP/DMG and staples the DMG. It embeds `LocusUpdateTeam` and emits
`appcast-<architecture>.json.zip` containing signed `appcast.json`. The app accepts
only that signed feed when a team is embedded. It also verifies the downloaded
app's bundle ID, newer build, Developer ID team and archive checksum before swapping.
Use the same identity/team across releases. Test this full path on two disposable
signed releases before enabling signed distribution; it is not validated yet.

Transitioning from ad-hoc to signed releases requires one manual installation.
Do not distribute the upstream Office Commun icon or use its signing identity/feed.
