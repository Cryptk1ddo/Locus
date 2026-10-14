#!/usr/bin/env python3
"""Native AppKit events exercise SwiftUI card/ground gestures in a hidden world."""
import sys
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv
sv.use("wall-gesture-tests")
t = sv.T()
def wall(action="state", **fields): return sv.cmd({"do":"wall", "action":action, **fields})
def drag(x, y, dx, dy, **fields):
    sv.sp("mouse", points=[[x,y],[x+dx/2,y+dy/2],[x+dx,y+dy],[x+dx,y+dy]], to="view", **fields)
def placement(): return wall()["placementData"][0]
try:
    sv.setup(sidebar=True, spaces=True); sv.launch(); page = sv.page("gesture")
    # Native Wall tabs use the same page area but expose no WebKit pane frame.
    pane = sv.sp("state")["paneFrames"][0]
    wall("note", title="Gesture fixture"); wall("open"); time.sleep(.6)
    x, y = pane["x"] + 40 + 260 - 2, pane["y"] + 40 + 180 - 2
    drag(x, y, 40, 30)
    p = placement()
    t.ok("corner gesture resizes the native card", (p["width"], p["height"]) == (300,210), p)
    t.ok("resize does not also move the card", (p["x"],p["y"]) == (40,40), p)
    drag(pane["x"] + 70, pane["y"] + 90, 60, 40)
    p = placement()
    t.ok("card gesture moves without resizing", (p["x"],p["y"],p["width"],p["height"]) == (100,80,300,210), p)
    drag(pane["x"] + 700, pane["y"] + 600, 50,30, button="middle")
    view = wall("viewport")
    t.ok("ground gesture saves pan independently of object coordinates", view == {"x":50,"y":30,"zoom":1} and placement()["x"] == 100, view)
    x, y = pane["x"] + pane["width"] - 32, pane["y"] + 72
    sv.sp("mouse",points=[[x,y],[x,y]],to="view")
    view = wall("viewport")
    t.ok("native zoom control persists its value", view["zoom"] == 1.2, view)
    drag(pane["x"] + view["x"] + (100+300-2)*1.2, pane["y"] + view["y"] + (80+210-2)*1.2,40,30)
    p = placement()
    t.ok("resize respects the current canvas zoom", (p["width"],p["height"],p["x"],p["y"]) == (300+40/1.2,210+30/1.2,100,80), p)
    wall("close"); time.sleep(.25); wall("open"); time.sleep(.3)
    t.ok("reopening restores the gesture-produced viewport", wall("viewport") == view)
    sv.cmd({"do":"space", "action":"new", "name":"Another context"}); wall("open"); time.sleep(.3)
    t.ok("another Space starts with its own canvas view", wall("viewport") == {"x":0,"y":0,"zoom":1})
    sv.cmd({"do":"space", "action":"go", "index":1}); wall("close"); time.sleep(.3)
    sv.sp("save"); sv.quit(); sv.launch()
    t.ok("native gesture state survives full app restart", wall("viewport") == view and abs(placement()["width"] - (300+40/1.2)) < .001)
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
