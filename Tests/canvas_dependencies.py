#!/usr/bin/env python3
"""Portable recursive files, native embeds, and undo using only synthetic grants."""
import json
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv

sv.use("canvas-dependencies")
t = sv.T()
def wall(action="state", **kwargs):
    return sv.cmd({"do": "wall", "action": action, **kwargs})

try:
    with tempfile.TemporaryDirectory(prefix="locus-dependencies-") as directory:
        root = Path(directory)
        vault = root / "Vault"
        vault.mkdir()
        a = vault / "A.md"
        a.write_text("# Root\n![[B#Detail]]\n")
        (vault / "B.md").write_text("# Detail\nNested portable content\n![[A]]\n![[image.png]]\n")
        # Use a known-valid generated bitmap rather than a remote image.
        import subprocess
        subprocess.run(["swift", "-e", 'import AppKit; let b = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!; for x in 0..<2 { for y in 0..<2 { b.setColor(NSColor(deviceRed:0.1,green:0.4,blue:0.9,alpha:1),atX:x,y:y) } }; try b.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))', str(vault / "image.png")], check=True)
        (vault / "Unused.md").write_text("Do not copy unrelated notes")
        original = a.read_bytes()
        sv.setup(sidebar=False)
        sv.launch()
        sv.page("portable-dependencies")
        wall("canvasVault", path=str(vault))
        wall("canvasFileFixture", path=str(a))
        before = wall()
        exported = root / "Export"
        result = wall("canvasExportFile", format="portable", path=str(exported))
        manifest = json.loads((exported / "manifest.json").read_text())
        t.ok("recursive notes and image export once despite cycle", result["unresolved"] == 0 and manifest["assets"] == 3 and len(manifest["dependencies"]) == 2, manifest)
        t.ok("export preserves source and workspace", a.read_bytes() == original and wall()["objects"] == before["objects"])
        result = wall("canvasImportFolder", path=str(exported))
        state = wall()
        t.ok("dependencies import without extra Wall cards", len(state["objects"]) == len(before["objects"]) + 3 and len(state["placementData"]) == len(before["placementData"]) + 1, result)
        obj = next(o["id"] for o in state["objects"] if o["title"] == "1.md")
        card = next(p["id"] for p in state["placementData"] if p["object"] == obj)
        wall("open")
        wall("viewport", x=80, y=80, zoom=1)
        wall("canvasEdit", id=card)
        sv.cmd({"do": "press", "code": 53, "chars": ""})
        time.sleep(.4)
        previews = wall("canvasContentInfo")["previews"]
        preview = next(p for p in previews if p["object"] == obj)
        text = preview["text"]
        t.ok("nested image renders from its restored bookmark", preview["images"] >= 1, preview)
        t.ok("imported dependency renders through explicit file grant", "Nested portable content" in text, text)
        t.ok("cycle is rendered as bounded native message", "Cyclic embed" in text, text)
        wall("canvasUndo")
        t.ok("one undo removes imported cards and dependency objects", len(wall()["objects"]) == len(before["objects"]))
        wall("canvasRedo")
        t.ok("redo restores dependency grants", len(wall()["objects"]) == len(before["objects"]) + 3)
        again = root / "Again"
        t.ok("imported dependency graph exports again", wall("canvasExportFile", format="portable", path=str(again))["unresolved"] == 0)
finally:
    sv.finish()
    t.done()
sys.exit(1 if t.failed else 0)
