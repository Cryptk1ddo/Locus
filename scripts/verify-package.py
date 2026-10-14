#!/usr/bin/env python3
"""Check packaged release identity, architecture, hashes, and ZIP contents."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import zipfile

folder = Path(sys.argv[1])
arch = folder.name
manifest = json.loads((folder / f"appcast-{arch}.json").read_text())
assert manifest["architecture"] == arch
app = folder / "Locus.app"
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "com.cryptk1ddo.locus"
assert info["CFBundleDisplayName"] == "Locus"
assert info["CFBundleShortVersionString"] == manifest["version"]
assert int(info["CFBundleVersion"]) == manifest["build"]
assert subprocess.check_output(["lipo", "-archs", str(app / "Contents/MacOS/Search")], text=True).strip() == arch
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
for suffix, key in [("zip", "sha256"), ("dmg", "dmgSha256")]:
    file = folder / f"Locus-{arch}.{suffix}"
    with file.open("rb") as stream:
        assert hashlib.file_digest(stream, "sha256").hexdigest() == manifest[key]
    assert manifest["url" if suffix == "zip" else "dmg"] == f'https://github.com/Cryptk1ddo/Locus/releases/download/v{manifest["version"]}/{file.name}'
with zipfile.ZipFile(folder / f"Locus-{arch}.zip") as archive:
    packed = plistlib.loads(archive.read("Locus.app/Contents/Info.plist"))
    assert packed == info
    with (app / "Contents/MacOS/Search").open("rb") as stream:
        assert hashlib.sha256(archive.read("Locus.app/Contents/MacOS/Search")).hexdigest() == hashlib.file_digest(stream, "sha256").hexdigest()
print(f"Verified Locus {manifest['version']} ({arch}): identity, architecture, signature and archive hashes")
