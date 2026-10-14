#!/usr/bin/env python3
"""Page reference/undo/capture lineage in a dedicated native test browser."""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv

sv.use("page-lifecycle-tests")
t = sv.T()

def wall(action="state", **fields):
    return sv.cmd({"do": "wall", "action": action, **fields})

def bound(object_id):
    full = next(b["tab"] for b in wall()["bindings"] if b["object"] == object_id)
    return next(x["id"] for x in sv.sp("state")["tabs"] if full.lower().startswith(x["id"].lower()))

def data(object_id):
    return wall("pageData", id=object_id)["object"]

def wait_capture():
    for _ in range(100):
        state = wall()
        if not state["capturing"]: return state
        time.sleep(.1)
    raise RuntimeError("capture did not finish")

try:
    sv.setup(spaces=True, splitView=True, **{"tabs.groups": True}); sv.launch()
    a = sv.page("same"); one = wall("savePage")["objects"][-1]["id"]
    b = sv.page("same"); two = wall("savePage")["objects"][-1]["id"]
    sv.sp("close", id=a); sv.sp("reopen"); time.sleep(.7)
    a = bound(one)
    t.ok("single-tab undo restores object binding", len(wall()["bindings"]) == 2)
    before = sv.order(sv.sp("state"))
    wall("openPage", id=one)
    t.ok("object open reuses undo-restored tab", sv.sp("state")["activeID"] == a and sv.order(sv.sp("state")) == before)
    sv.sp("pair", id=b, **{"with": a})
    sv.sp("clear"); sv.sp("reopen"); time.sleep(.7)
    a, b = bound(one), bound(two)
    t.ok("Clear undo restores each distinct object binding", {x["object"] for x in wall()["bindings"]} == {one, two})
    t.ok("Clear undo preserves split restoration", len(sv.sp("state")["splits"]) == 1)
    sv.sp("detach", id=a)
    grouped = sv.sp("group", id=b); group_id = grouped["groups"][-1]["id"]
    sv.cmd({"do": "group", "name": group_id, "close": True}); sv.sp("reopen"); time.sleep(.7)
    b = bound(two); grouped = sv.sp("state")
    t.ok("undo restores a closed group and its page binding", grouped["groupIDs"][sv.order(grouped).index(b)] == group_id)
    sv.sp("group", id=b, group="none")
    wall("openPage", id=one)
    sv.ev(a, "document.body.innerHTML = '<button id=target aria-label=Reference style=padding:20px>Reference</button>'; true")
    wall("captureSelector", selector="#target"); wait_capture()
    original = wall("captureData")["object"]; parent = original["id"]
    reference = data(one)
    sv.cmd({"do": "go", "id": a, "url": f"{sv.BASE}/changed"}); time.sleep(.9)
    before = sv.order(sv.sp("state"))
    wall("openPage", id=one)
    t.ok("default Open preserves live tab's navigated address", sv.url(sv.sp("state"), a).endswith("/changed"))
    t.ok("navigation does not silently update saved reference", data(one) == reference)
    built_before = wall()["builtTabs"]
    wall("updatePage", id=one)
    updated = data(one)
    t.ok("explicit update keeps object identity and saves current address", updated["id"] == one and updated["content"]["url"].endswith("/changed"))
    t.ok("explicit update keeps original capture observation intact", data(parent) == original)
    t.ok("explicit update neither creates a tab nor a WebKit view", sv.order(sv.sp("state")) == before and wall()["builtTabs"] == built_before)
    wall("search", typed="wall: changed")
    t.ok("object search observes updated reference", any(r.get("object") == one for r in wall()["offers"]))
    sv.cmd({"do": "press", "code": 53, "chars": "", "mods": []})
    sv.cmd({"do": "go", "id": a, "url": f"{sv.BASE}/elsewhere"}); time.sleep(.9)
    wall("openPage", id=one, savedAddress=True); time.sleep(.9)
    t.ok("Open Saved Address explicitly navigates the bound tab", sv.url(sv.sp("state"), a).endswith("/changed") and sv.order(sv.sp("state")) == before)
    sv.cmd({"do": "select", "id": b})
    t.ok("recapture requires the active source tab", not wall("canRecapture", id=parent)["available"])
    wall("sourcePage", id=parent)
    t.ok("Open Source Page selects the bound source", sv.sp("state")["activeID"] == a)
    t.ok("loaded source permits recapture", wall("canRecapture", id=parent)["available"])
    count = len(wall()["objects"])
    wall("recapture", id=parent)
    sv.cmd({"do": "press", "code": 53, "chars": "", "mods": []})
    t.ok("Escape cancels recapture without changing objects", not wall()["capturing"] and len(wall()["objects"]) == count)
    wall("recapture", id=parent)
    sv.ev(a, "document.querySelector('p').click(); true")
    wait_capture(); new = wall("captureData")["object"]
    links = {r["kind"]: r["targetID"] for r in new["relationships"]}
    t.ok("recapture creates a new observation with source and lineage", new["id"] != parent and links.get("capturedFrom") == one and links.get("derivedFrom") == parent)
    t.ok("recapture does not mutate original capture or asset", data(parent) == original and wall("captureData")["assetExists"])
    sv.sp("save"); sv.quit(); sv.launch(); time.sleep(.7)
    a, b = bound(one), bound(two)
    t.ok("updated reference and undo-restored bindings survive restart", data(one) == updated and len(wall()["bindings"]) == 2)
    t.ok("capture lineage and asset survive restart", data(new["id"]) == new and wall("captureData")["assetExists"])
    wall("openPage", id=one)
    for _ in range(100):
        if wall()["canCapture"] and sv.ev(a, "!!document.querySelector('p')"): break
        time.sleep(.1)
    wall("recapture", id=parent); wall("deleteObject", id=parent)
    count = len(wall()["objects"])
    sv.ev(a, "document.querySelector('p').click(); true"); wait_capture()
    t.ok("deleting predecessor while picking prevents derived commit", len(wall()["objects"]) == count)
    wall("openPage", id=one)
    wall("recapture", id=new["id"]); wall("deleteObject", id=one)
    count = len(wall()["objects"])
    sv.ev(a, "document.querySelector('p').click(); true"); wait_capture()
    t.ok("deleting source while picking prevents derived commit", len(wall()["objects"]) == count)
    sv.sp("close", id=a); sv.sp("reopen"); time.sleep(.7)
    t.ok("undo of deleted object's tab restores page without stale binding", all(r["object"] != one for r in wall()["bindings"]))
    b = bound(two); sv.sp("close", id=b)
    sv.cmd({"do": "space", "action": "new", "name": "Other Space"})
    sv.sp("reopen"); time.sleep(.7)
    t.ok("undo in another Space does not import or bind source object", wall()["objects"] == [] and wall()["bindings"] == [])
    sv.cmd({"do": "space", "action": "go", "index": 1})
    t.ok("cross-Space undo leaves original object intact", any(o["id"] == two for o in wall()["objects"]))
    wall("openPage", id=two); time.sleep(.5)
    sv.sp("save"); sv.quit(); sv.launch()
    t.ok("reopened source binding survives restart", data(two)["content"]["url"].endswith("/same") and bound(two) in sv.order(sv.sp("state")))
    before = wall()["closedTabs"]
    sv.sp("private"); private = sv.page("private")
    sv.sp("close", id=private)
    t.ok("private close does not create an undo record or object binding", wall()["closedTabs"] == before and all(r["object"] != one for r in wall()["bindings"]))
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
