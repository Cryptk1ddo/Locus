#!/usr/bin/env python3
"""Space recovery and owned preview integrity in an isolated native app world."""
import hashlib
import json
import sys
import time
import uuid
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv
sv.use("workspace-recovery-tests")
t = sv.T()
output = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/locus-workspace-recovery")
output = output.resolve()
output.mkdir(parents=True, exist_ok=True)
def wall(action="state", **fields): return sv.cmd({"do": "wall", "action": action, **fields})
def until(predicate):
    for _ in range(100):
        result = predicate()
        if result: return result
        time.sleep(.1)
    raise RuntimeError("Native operation did not complete")
def object_data(id): return wall("pageData", id=id)["object"]
try:
    sv.setup(); sv.launch(); page = sv.page("inspiration")
    until(lambda: sv.cmd({"do": "eval", "id": page, "js": "document.readyState"}).get("value") == "complete")
    sv.cmd({"do": "pages", "on": True})
    sv.cmd({"do": "eval", "id": page, "js": """
        document.title = 'Interface study';
        document.body.innerHTML = `<main><p>LOCUS / RESEARCH</p><h1>Make room for ideas.</h1><p>Collect references. Keep their origins. Connect what you learn.</p><button id='target' aria-label='Save inspiration'>Save inspiration ↗</button></main>`;
        document.head.insertAdjacentHTML('beforeend', `<style>body{margin:0;background:#eee8df;color:#253f38;font:18px Georgia}main{padding:60px}h1{font-size:60px;max-width:550px;font-weight:400}button{background:#253f38;color:#fff;border:0;border-radius:8px;padding:16px 24px;font:15px sans-serif}</style>`);
        true;
    """})
    wall("savePage")
    wall("note", title="Interaction study", text="Keep the quiet layout and compare the call to action with collected references.")
    until(lambda: wall()["canCollect"])
    wall("collectInspiration")
    until(lambda: not wall()["collecting"])
    state = wall()
    assert any(x["type"] == "inspiration" for x in state["objects"]), state
    clip = next(x for x in state["objects"] if x["type"] == "inspiration")
    until(lambda: wall()["canCapture"] or wall()["canCaptureSource"])
    wall("captureSelector", selector="#target")
    until(lambda: not wall()["capturing"])
    state = wall()
    assert any(x["type"] == "uiCapture" for x in state["objects"]), state
    capture = next(x for x in state["objects"] if x["type"] == "uiCapture")
    note = next(x for x in wall()["objects"] if x["type"] == "note")
    wall("inspirationLink", url="https://www.pinterest.com/pin/123456789/", title="Pinterest · Layout reference")
    wall("connect", source=note["id"], target=clip["id"], kind="inspiredBy")
    wall("move", id=note["id"], x=330, y=50)
    state = wall()
    root = Path(sv.SUPPORT) / "workspaces" / state["spaceID"]
    file, previous = root / "workspace.json", root / "workspace.previous.json"
    expected = json.loads(previous.read_text())
    t.ok("native writes create a previous revision backup", expected["revision"] == state["revision"] - 1)
    clip_data = object_data(clip["id"])
    value = clip_data["content"]["screenshot"]["value"]
    asset = root / "assets" / (value["assetID"] + ".png")
    original_png = asset.read_bytes()
    t.ok("new native previews record byte count and SHA-256", value["bytes"] == len(original_png) and value["sha256"] == hashlib.sha256(original_png).hexdigest())
    t.ok("verified local preview displays", wall("previewAvailable", id=clip["id"])["available"])
    asset.write_bytes(b"broken PNG")
    t.ok("damaged preview is rejected without deleting evidence", not wall("previewAvailable", id=clip["id"])["available"] and object_data(clip["id"]) == clip_data)
    # Render the actual component inspector with intentionally damaged evidence.
    capture_value = object_data(capture["id"])["content"]["screenshot"]["value"]
    capture_asset = root / "assets" / (capture_value["assetID"] + ".png")
    capture_png = capture_asset.read_bytes()
    capture_asset.write_bytes(b"broken capture PNG")
    wall("capturePicture", path=str(output / "01-damaged-preview.png"))
    capture_asset.write_bytes(capture_png); asset.write_bytes(original_png)
    # Reconcile a staged asset after a valid restart, preserving unknown files.
    orphan = root / "assets" / (str(uuid.uuid4()) + ".png")
    orphan.write_bytes(original_png)
    unknown = root / "assets" / "future-attachment.bin"; unknown.write_bytes(b"future data")
    sv.sp("save")
    before_urls = [x["url"] for x in sv.session()["tabs"]]
    page_object = next(x["id"] for x in wall()["objects"] if x["type"] == "page")
    sv.quit(); sv.launch()
    t.ok("valid native reopen removes interrupted staging", not orphan.exists())
    t.ok("reconciliation preserves unknown future assets", unknown.read_bytes() == b"future data")
    t.ok("workspace maintenance preserves restored browser tabs", [x["url"] for x in sv.sp("state")["tabs"]] == before_urls)
    page = next(x["id"] for x in sv.sp("state")["tabs"] if x["url"].endswith("/inspiration"))
    expected_bytes = previous.read_bytes(); expected = json.loads(expected_bytes)
    sv.sp("select", id=page); sv.quit()
    damaged = b"interrupted JSON write"
    file.write_bytes(damaged)
    sv.launch(); state = wall("open")
    t.ok("corrupt Wall opens read-only with a recovery choice", not state["writable"] and state["recoveryRevision"] == expected["revision"] and state["recoveryObjects"] == len(expected["objects"]))
    t.ok("failure leaves tabs and WebKit functional", [x["url"] for x in sv.sp("state")["tabs"]] == before_urls and sv.cmd({"do":"eval", "id":next(x["id"] for x in sv.sp("state")["tabs"] if x["url"].endswith("/inspiration")), "js":"document.readyState"}).get("value") == "complete")
    wall("note", title="Must not overwrite")
    t.ok("blocked edit preserves damaged bytes", file.read_bytes() == damaged and not wall()["objects"])
    wall("picture", path=str(output / "02-recovery-choice.png"))
    page = next(x["id"] for x in sv.sp("state")["tabs"] if x["url"].endswith("/inspiration"))
    sv.sp("select", id=page); sv.sp("close", id=page); sv.sp("reopen")
    until(lambda: wall()["canCapture"] or wall()["canCaptureSource"])
    sv.sp("save")
    t.ok("session save and undo-close retain unresolved binding during corruption", any(x.get("objectID") == page_object for x in sv.session()["tabs"]))
    state = wall("recover")
    t.ok("explicit recovery restores prior objects and placements", state["writable"] and state["recoveryRevision"] == -1 and [x["id"] for x in state["objects"]] == [x["id"] for x in expected["objects"]] and state["placements"] == len(expected["wall"]["placements"]))
    t.ok("recovery restores the exact prior file bytes", file.read_bytes() == expected_bytes)
    archives = list(root.glob("workspace.damaged-*.json"))
    t.ok("recovery preserves damaged file for manual repair", len(archives) == 1 and archives[0].read_bytes() == damaged)
    t.ok("recovered visual evidence remains usable", wall("previewAvailable", id=clip["id"])["available"] and wall("previewAvailable", id=capture["id"])["available"])
    t.ok("recovered page binding resolves to restored live tab", any(x["object"] == page_object and x["tab"].lower().startswith(sv.sp("state")["activeID"].lower()) for x in state["bindings"]))
    restored_tabs = sv.order(sv.sp("state"))
    wall("openPage", id=page_object)
    t.ok("opening recovered page reuses the restored tab", sv.order(sv.sp("state")) == restored_tabs)
    wall("open")
    wall("picture", path=str(output / "03-recovered-wall.png"))
    wall("note", title="Continue research", text="The previous Space objects are editable again.")
    committed = json.loads(file.read_text()); sv.quit(); sv.launch()
    t.ok("edits after recovery survive native restart", wall()["revision"] == committed["revision"] and len(wall()["objects"]) == len(committed["objects"]))
    # A newer writer's snapshot must never be replaced by our older backup.
    sv.quit(); future = b'{"schemaVersion":99,"futurePayload":"preserve"}'
    file.write_bytes(future); sv.launch()
    state = wall("open"); wall("recover")
    t.ok("newer schema has no recovery/downgrade action", not state["writable"] and state["recoveryRevision"] == -1 and file.read_bytes() == future)
    (output / "manifest.json").write_text(json.dumps({"provenance": "Actual native SwiftUI/AppKit views in an isolated hidden Bench profile. Local sample page; Pinterest is a saved URL reference, not authenticated import. Recovery state intentionally created by corrupting only the disposable test workspace. Recovery command exercises the same store method as the confirmation button; alert interaction is not automated.", "world": sv.W, "source": "Tests/workspace_recovery.py", "screenshots": sorted(x.name for x in output.glob('*.png'))}, indent=2) + "\n")
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
