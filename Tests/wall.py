#!/usr/bin/env python3
"""Wall integration in an isolated, hidden Bench test world. Build debug first."""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv

sv.use("wall-tests")
t = sv.T()
def wall(action="state", **fields):
    return sv.cmd({"do": "wall", "action": action, **fields})
try:
    sv.setup(); sv.launch()
    page = sv.page("reference")
    before = sv.sp("state")
    built = wall()["builtTabs"]
    state = wall("open")
    t.ok("Wall opens without Spaces enabled", state["showing"])
    t.ok("Wall leaves WebKit views unchanged", state["builtTabs"] == built)
    t.ok("Wall adds one native tab while preserving page identities", len(sv.order(sv.sp("state"))) == len(sv.order(before)) + 1 and all(id in sv.order(sv.sp("state")) for id in sv.order(before)))
    state = wall("savePage")
    t.ok("explicit save creates one page object", len(state["objects"]) == 1 and state["objects"][0]["type"] == "page", state)
    page_object = state["objects"][0]["id"]
    state = wall("savePage")
    t.ok("saving a bound page again reuses its object", len(state["objects"]) == 1)
    state = wall("note", title="Research", text="A native workspace for the pages we keep.")
    t.ok("note is durable content alongside page", len(state["objects"]) == 2 and state["placements"] == 2)
    # Offscreen native render for visual QA, outside the test world's cleanup.
    wall("picture", path="/tmp/locus-wall-preview.png")
    sv.cmd({"do": "press", "code": 13, "chars": "w", "mods": ["cmd"]}); time.sleep(.4)
    t.ok("Command-W closes Wall before the page", not wall()["showing"] and page in sv.order(sv.sp("state")))
    wall("open"); sv.cmd({"do": "press", "code": 53, "chars": "", "mods": []}); time.sleep(.3)
    t.ok("Escape keeps Wall as a tab", wall()["showing"])
    wall("open")
    sv.cmd({"do": "ui", "settings": True})
    sv.cmd({"do": "press", "code": 13, "chars": "w", "mods": ["cmd"]}); time.sleep(.3)
    t.ok("panel above Wall closes first", wall()["showing"] and not sv.cmd({"do": "probe"})["settings"])
    wall("openPage", id=page_object)
    t.ok("opening object selects original live tab", sv.sp("state")["activeID"] == page)
    sv.cmd({"do": "ui", "spaces": True})
    sv.cmd({"do": "space", "action": "new", "name": "Project"})
    state = wall("open")
    t.ok("new Space has an independent Wall", state["objects"] == [])
    wall("note", title="Project note")
    sv.cmd({"do": "space", "action": "go", "index": 1})
    t.ok("switching back restores first Space objects", len(wall()["objects"]) == 2)
    sv.quit(); sv.launch()
    t.ok("Wall objects survive restart", len(wall()["objects"]) == 2)
    sv.sp("private")
    private = sv.sp("open", url=f"{sv.BASE}/private")["resultID"]
    time.sleep(.4)
    count = len(wall()["objects"])
    t.ok("private page cannot be saved", not wall()["canSavePage"])
    t.ok("private save leaves objects unchanged", len(wall("savePage")["objects"]) == count)
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
