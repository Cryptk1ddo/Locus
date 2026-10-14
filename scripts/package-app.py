#!/usr/bin/env python3
"""Build Locus for one architecture and produce a ZIP, DMG and update manifest."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=["arm64", "x86_64"], default=os.uname().machine)
    parser.add_argument("--notarize", action="store_true")
    args = parser.parse_args()
    version = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        parser.error("VERSION must be a stable semantic version, such as 0.1.0")
    build = os.environ.get("LOCUS_BUILD", datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S"))
    if not build.isdigit():
        parser.error("LOCUS_BUILD must be a monotonically increasing integer")
    identity = os.environ.get("LOCUS_SIGN_IDENTITY", "-")
    team = os.environ.get("LOCUS_UPDATE_TEAM", "")
    if (identity != "-") != bool(team) or (team and not re.fullmatch(r"[A-Z0-9]{10}", team)):
        parser.error("Set both LOCUS_SIGN_IDENTITY and LOCUS_UPDATE_TEAM, or neither")
    if args.notarize and (identity == "-" or not os.environ.get("LOCUS_NOTARY_PROFILE")):
        parser.error("--notarize needs Developer ID signing and LOCUS_NOTARY_PROFILE")
    flags = ["-c", "release", "--arch", args.arch, "--jobs", "2", "-Xswiftc", "-Osize"]
    run("swift", "build", *flags)
    binary_dir = Path(run("swift", "build", *flags, "--show-bin-path", capture_output=True, text=True).stdout.strip())
    out = ROOT / "build" / "release" / args.arch
    out.mkdir(parents=True, exist_ok=True)
    app = out / "Locus.app"
    if app.exists():
        shutil.rmtree(app)
    (app / "Contents/MacOS").mkdir(parents=True)
    resources = app / "Contents/Resources"
    resources.mkdir()
    shutil.copy2(binary_dir / "Search", app / "Contents/MacOS/Search")
    run("strip", "-x", str(app / "Contents/MacOS/Search"))
    shutil.copy2(ROOT / "Search.sdef", resources)
    info = plistlib.loads((ROOT / "Xcode/Info.plist").read_bytes())
    info.update(CFBundleName="Locus", CFBundleDisplayName="Locus", CFBundleExecutable="Search",
                CFBundleIdentifier="com.cryptk1ddo.locus", CFBundleShortVersionString=version,
                CFBundleVersion=build, LSMinimumSystemVersion="14.0", CFBundleIconFile="AppIcon",
                NSHumanReadableCopyright="Locus contributors; based on Search (MIT)")
    info["CFBundleURLTypes"] = [{"CFBundleURLName": "Web address", "CFBundleURLSchemes": ["http", "https"]}]
    info["CFBundleDocumentTypes"] = [{"CFBundleTypeName": "Web page", "CFBundleTypeRole": "Viewer",
        "LSItemContentTypes": ["public.html", "public.xhtml", "com.apple.web-internet-location"]}]
    if team:
        info["LocusUpdateTeam"] = team
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    with tempfile.TemporaryDirectory(prefix="locus-icon-") as temporary:
        iconset = Path(temporary) / "AppIcon.iconset"
        run("swift", "Icon/locus.swift", str(iconset))
        run("iconutil", "-c", "icns", str(iconset), "-o", str(resources / "AppIcon.icns"))
    signing = ["codesign", "--force", "--sign", identity]
    if team:
        signing += ["--timestamp", "--options", "runtime", "--entitlements", "Search.entitlements"]
    run(*signing, str(app))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    if team:
        # Refuse a misconfigured certificate before creating an unusable update channel.
        run("codesign", "--verify", "-R", f'anchor apple generic and identifier "com.cryptk1ddo.locus" and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "{team}"', str(app))
    archive = out / f"Locus-{args.arch}.zip"
    archive.unlink(missing_ok=True)
    run("ditto", "-c", "-k", "--keepParent", str(app), str(archive))
    dmg = out / f"Locus-{args.arch}.dmg"
    dmg.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="locus-dmg-") as temporary:
        stage = Path(temporary)
        run("ditto", str(app), str(stage / "Locus.app"))
        (stage / "Applications").symlink_to("/Applications")
        run("hdiutil", "create", "-volname", "Locus", "-srcfolder", str(stage), "-format", "UDZO", "-quiet", str(dmg))
    if team:
        run("codesign", "--force", "--timestamp", "--sign", identity, str(dmg))
    if args.notarize:
        for file in [archive, dmg]:
            run("xcrun", "notarytool", "submit", str(file), "--keychain-profile", os.environ["LOCUS_NOTARY_PROFILE"], "--wait")
        run("xcrun", "stapler", "staple", str(dmg))
        run("xcrun", "stapler", "validate", str(dmg))
    base = f"https://github.com/Cryptk1ddo/Locus/releases/download/v{version}"
    manifest = dict(version=version, build=int(build), url=f"{base}/{archive.name}", dmg=f"{base}/{dmg.name}",
        sha256=digest(archive), dmgSha256=digest(dmg), minimumSystemVersion="14.0",
        notes="Locus development release. See GitHub for changes and known limitations.", architecture=args.arch)
    feed = out / f"appcast-{args.arch}.json"
    feed.write_text(json.dumps(manifest, indent=2) + "\n")
    signed_feed = out / (feed.name + ".zip")
    signed_feed.unlink(missing_ok=True)
    if team:
        with tempfile.TemporaryDirectory(prefix="locus-feed-") as temporary:
            signed = Path(temporary) / "appcast.json"
            shutil.copy2(feed, signed)
            run("codesign", "--force", "--timestamp", "--sign", identity, "--identifier", "com.cryptk1ddo.locus.appcast", str(signed))
            run("ditto", "-c", "-k", "--sequesterRsrc", str(signed), str(signed_feed))
    files = [archive, dmg, feed] + ([signed_feed] if team else [])
    (out / f"SHA256SUMS-{args.arch}.txt").write_text("".join(f"{digest(file)}  {file.name}\n" for file in files))
    print(f"Built {app}: {version}, {args.arch}, build {build}; signing: {'Developer ID' if team else 'development (ad hoc)'}")

if __name__ == "__main__":
    main()
