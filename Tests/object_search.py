#!/usr/bin/env python3
"""Explicit Space object search through the native field, in an isolated world."""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv

sv.use("object-search-tests")
t = sv.T()

def wall(action="state", **fields):
    return sv.cmd({"do": "wall", "action": action, **fields})

def search(query):
    wall("search")
    sv.cmd({"do": "field", "text": query})
    return wall()

try:
    sv.setup(); sv.launch()
    page = sv.page("reference")
    wall("savePage")
    state = wall("note", title="Café research", text="Native interfaces and tokens")
    note = state["objects"][-1]["id"]
    wall("note", title="Other", text="Research in the note body")
    wall("note", title="Duplicate", text="One")
    wall("note", title="Duplicate", text="Two")
    wall("note", title="www.Native reference")
    original = sv.sp("state")
    built = wall()["builtTabs"]
    space = wall()["spaceID"]
    state = search("wall:")
    t.ok("bare scope offers at most five objects", len(state["offers"]) == 5)
    t.ok("results carry typed Space/object IDs without URLs", all(r.get("space") == space and r.get("object") and r["url"] == "" for r in state["offers"]))
    state = search("wall: cafe")
    t.ok("title search is diacritic insensitive", len(state["offers"]) == 1 and state["offers"][0].get("object") == note)
    t.ok("object query has no address completion", state["ending"] == "")
    state = wall("submitSearch")
    t.ok("Return reveals selected object on Wall", state["showing"] and state["revealID"] == note and not state["editing"])
    t.ok("reveal preserves tabs and WebKit views", all(id in sv.order(sv.sp("state")) for id in sv.order(original)) and len(state["wallTabs"]) == 1 and state["builtTabs"] == built)
    wall("move", id=note, x=100000.0, y=-100000.0)
    search("wall: cafe"); wall("submitSearch")
    wall("picture", path="/tmp/locus-object-search-preview.png")
    wall("close")
    state = search("wall: research")
    t.ok("note body is searchable after title matches", len(state["offers"]) == 2 and state["offers"][0].get("object") == note)
    state = search("wall: duplicate")
    ids = [r.get("object") for r in state["offers"]]
    t.ok("duplicate titles have distinct result identities", len(ids) == 2 and len(set(r["id"] for r in state["offers"])) == 2)
    sv.cmd({"do": "press", "code": 125, "chars": "", "mods": []})
    sv.cmd({"do": "press", "code": 125, "chars": "", "mods": []})
    state = wall()
    t.ok("arrow keys choose second object without rewriting scoped input", state["picked"] == 1 and state["completed"] == "wall: duplicate")
    sv.cmd({"do": "press", "code": 36, "chars": "\r", "mods": []})
    state = wall()
    t.ok("native Return reveals the arrow-selected object", state["revealID"] == ids[1])
    search("wall: duplicate")
    chosen = ids[1]
    state = wall("chooseSearch", index=1)
    t.ok("clicking second result reveals its typed target", state["revealID"] == chosen)
    wall("close")
    count = wall()["placements"]
    wall("removePlacements", id=note)
    search("wall: cafe"); state = wall("submitSearch", aside=True)
    t.ok("unplaced object gets one placement with no duplicate object", state["placements"] == count and len(state["objects"]) == 6)
    t.ok("Command-Return selects a single native Wall tab", len(wall()["wallTabs"]) == 1 and all(id in sv.order(sv.sp("state")) for id in sv.order(original)))
    search("wall: cafe"); state = wall("submitSearch")
    t.ok("repeat reveal reuses placement", state["placements"] == count)
    sv.sp("select", id=page)
    state = search("wall: absent")
    state = wall("submitSearch")
    t.ok("no matches keeps query without navigation", not state["showing"] and state["editing"] and state["typed"] == "wall: absent" and sv.sp("state")["activeID"] == page)
    state = search("wall art")
    t.ok("ordinary phrase retains web-search suggestions", state["offers"] and all("object" not in r for r in state["offers"]) and any(r["url"] for r in state["offers"]))
    state = search(f"{sv.BASE}/reference")
    t.ok("URL input retains navigation suggestions", all("object" not in r for r in state["offers"]))
    state = search("wall: duplicate")
    stale = state["offers"][0]["object"]
    wall("deleteObject", id=stale)
    state = wall("chooseSearch", index=0)
    t.ok("deleted result is revalidated before reveal", state["revealID"] == "")
    # Capture uses the same object search, without indexing its raw DOM.
    sv.cmd({"do": "press", "code": 53, "chars": "", "mods": []})
    wall("captureSelector", selector="p")
    for _ in range(100):
        state = wall()
        if not state["capturing"]: break
        time.sleep(.1)
    capture = next((o for o in state["objects"] if o["type"] == "uiCapture"), None)
    state = search("wall: p")
    t.ok("capture title is searchable as a typed object", capture is not None and any(r.get("object") == capture["id"] for r in state["offers"]))
    sv.cmd({"do": "ui", "spaces": True})
    sv.cmd({"do": "space", "action": "new", "name": "Other project"})
    state = search("wall: research")
    t.ok("object search is scoped to active Space", state["offers"] == [])
    state = wall("reveal", id=note, space=space)
    t.ok("cross-Space stale target cannot switch or reveal", not state["showing"] and state["spaceID"] != space and state["revealID"] == "")
    sv.cmd({"do": "space", "action": "go", "index": 1})
    sv.quit(); sv.launch()
    before = wall()["builtTabs"]
    state = search("wall: cafe")
    state = wall("submitSearch")
    t.ok("search and reveal survive restart without waking extra pages", state["revealID"] == note and state["showing"] and state["builtTabs"] == before)
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
