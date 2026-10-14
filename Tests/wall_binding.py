#!/usr/bin/env python3
"""Durable page identity across native session, pin, window and Space lifetimes."""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv

sv.use("wall-binding-tests")
t = sv.T()

def wall(action="state", window=1, **fields):
    return sv.cmd({"do": "wall", "action": action, "window": window, **fields})

def bound(object_id, window=1):
    state = sv.cmd({"do": "split", "action": "state", "window": window})
    full = next(b["tab"] for b in wall(window=window)["bindings"] if b["object"] == object_id)
    return next(x["id"] for x in state["tabs"] if full.lower().startswith(x["id"].lower()))

try:
    sv.setup(spaces=True, splitView=True); sv.launch()
    a = sv.page("same"); state = wall("savePage"); one = state["objects"][-1]["id"]
    b = sv.page("same"); state = wall("savePage"); two = state["objects"][-1]["id"]
    t.ok("duplicate URLs bind distinct objects", one != two and len(state["bindings"]) == 2)
    sv.sp("pair", id=b, **{"with": a})
    sv.sp("save")
    entries = sv.session()["tabs"]
    t.ok("session writes explicit durable IDs", {e.get("objectID") for e in entries} == {one, two})
    t.ok("binding metadata leaves split indices intact", sv.session()["splits"][0]["tabs"] == [0, 1])
    sv.quit(); sv.launch()
    a, b = bound(one), bound(two)
    tabs = sv.order(sv.sp("state"))
    state = wall("openPage", id=one)
    t.ok("restored object selects its original restored tab", sv.sp("state")["activeID"] == a and sv.order(sv.sp("state")) == tabs)
    wall("openPage", id=two)
    t.ok("equal URL does not select the other object's tab", sv.sp("state")["activeID"] == b)
    wall("savePage")
    t.ok("saving restored binding does not duplicate objects", len(wall()["objects"]) == 2)
    # End the split and pin the second tab; pins retain per-window session IDs.
    sv.sp("detach", id=b)
    sv.cmd({"do": "pin", "id": b})
    sv.cmd({"do": "select", "id": a})
    sv.cmd({"do": "go", "id": a, "url": f"{sv.BASE}/changed"}); time.sleep(.8)
    sv.sp("save"); sv.quit(); sv.launch()
    a, b = bound(one), bound(two)
    before = sv.order(sv.sp("state"))
    wall("openPage", id=one)
    t.ok("binding follows tab identity across navigation and restart", sv.url(sv.sp("state"), a).endswith("/changed") and sv.order(sv.sp("state")) == before)
    t.ok("pin reconciliation preserves saved per-window binding", b in sv.sp("state")["pins"])
    wall("openPage", id=two)
    t.ok("opening bound pin selects pin without a loose duplicate", sv.sp("state")["activeID"] == b and sv.order(sv.sp("state")) == before)
    sv.cmd({"do": "windows", "action": "new"})
    t.ok("a new window's shared pin is not implicitly object-bound", wall(window=2)["bindings"] == [])
    sv.cmd({"do": "towindow", "id": a, "to": 2}); time.sleep(.8)
    t.ok("same-Space window transfer retains Tab's binding", bound(one, 2) == a)
    state = sv.cmd({"do": "split", "action": "state", "window": 2})
    wall("openPage", window=2, id=one)
    t.ok("transferred object reuses tab in receiving window", sv.cmd({"do": "split", "action": "state", "window": 2})["activeID"] == a and len(wall(window=2)["bindings"]) == 1)
    sv.cmd({"do": "windows", "action": "close", "n": 1})
    sv.sp("save")
    t.ok("primary-window promotion keeps durable IDs in session", one in [e.get("objectID") for e in sv.session()["tabs"]])
    sv.cmd({"do": "space", "action": "new", "name": "Destination"})
    destination = wall()["spaceID"]
    sv.cmd({"do": "space", "action": "go", "index": 1})
    sv.cmd({"do": "tospace", "id": a, "index": 2}); time.sleep(1)
    t.ok("source object remains in original Space after moving tab", any(o["id"] == one for o in wall()["objects"]))
    sv.cmd({"do": "space", "action": "go", "index": 2})
    state = wall()
    t.ok("shared-cookie Space move clears old object binding", state["bindings"] == [] and state["objects"] == [])
    sv.cmd({"do": "select", "id": a})
    state = wall("savePage"); third = state["objects"][-1]["id"]
    t.ok("destination explicit save creates an independent object", third != one and state["bindings"][0]["object"] == third)
    wall("deleteObject", id=third); sv.sp("save")
    t.ok("deleted object IDs are omitted on session save", all("objectID" not in e for e in sv.session(destination)["tabs"]))
    state = wall("savePage"); fourth = state["objects"][-1]["id"]
    t.ok("saving after object deletion creates a fresh binding", fourth != third and state["bindings"][0]["object"] == fourth)
    sv.sp("close", id=a); time.sleep(.5)
    t.ok("closing tab preserves saved object", any(o["id"] == fourth for o in wall()["objects"]))
    wall("openPage", id=fourth); before = sv.order(sv.sp("state"))
    wall("openPage", id=fourth)
    t.ok("closed object reopens once and subsequent opens reuse it", len(wall()["bindings"]) == 1 and sv.order(sv.sp("state")) == before)
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
