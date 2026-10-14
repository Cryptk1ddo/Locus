#!/usr/bin/env python3
"""Native workflow screenshots using a local page and a dedicated hidden world."""
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv

sv.use("workflow-screenshots")
output = sv.ROOT / "artifacts" / "workflow"
output.mkdir(parents=True, exist_ok=True)

def wall(action="state", **fields):
    return sv.cmd({"do": "wall", "action": action, **fields})

def picture(name):
    time.sleep(.6)
    result = sv.cmd({"do": "picture", "path": str(output / name), "page": False})
    print(name, result)

try:
    sv.setup(sidebar=True, spaces=True); sv.launch()
    page = sv.page("interface-study")
    sv.ev(page, """document.title = 'Interface study'; document.head.insertAdjacentHTML('beforeend', `<style>
      * {box-sizing:border-box} body {margin:0;background:#f7f6f2;color:#24262a;font:16px -apple-system,BlinkMacSystemFont,sans-serif}
      main {max-width:900px;margin:auto;padding:36px 48px} header {display:flex;align-items:center;justify-content:space-between;font-size:13px}
      .brand {font-weight:650;font-size:18px} nav {color:#737678} h1 {font-size:48px;line-height:1.06;letter-spacing:-2px;margin:72px 0 22px;font-weight:550}
      .intro {max-width:460px;color:#777a7b;line-height:1.6} .component {margin-top:38px;padding:28px;background:#fff;border:1px solid #e7e5df;border-radius:16px}
      .eyebrow {font-size:11px;letter-spacing:1.4px;color:#7f8480;text-transform:uppercase} h2 {font-size:21px;font-weight:550;margin:12px 0}
      .row {display:flex;justify-content:space-between;align-items:center;gap:24px} .small {color:#797d7b;font-size:13px;line-height:1.6}
      button {--accent:#535c46;background:var(--accent);color:white;border:0;border-radius:10px;padding:14px 22px;font:500 14px -apple-system;white-space:nowrap}
      button::before {content:'+';margin-right:9px} footer {margin-top:28px;font-size:11px;color:#989b97}
      </style>`); document.body.innerHTML = `<main><header><span class='brand'>Atlas / Patterns</span><nav>Components &nbsp;&nbsp; Guidelines</nav></header>
      <h1>Small interfaces.<br>Clear decisions.</h1><p class='intro'>A component reference for quiet software. Keep useful details close to the work.</p>
      <section class='component'><span class='eyebrow'>Interaction / 03</span><div class='row'><div><h2>Save a reference</h2><p class='small'>One explicit action. A clear label.<br>Context stays with the page.</p></div>
      <button id='reference' aria-label='Save reference'>Save reference</button></div></section><footer>Local sample page · Locus workflow evidence</footer></main>`; true;""")
    time.sleep(.6)
    sv.cmd({"do": "pages", "on": True})
    picture("01-browser.png")
    wall("capture")
    sv.ev(page, "document.querySelector('#reference').dispatchEvent(new PointerEvent('pointermove',{bubbles:true})); true")
    picture("02-ui-picker.png")
    sv.ev(page, "document.querySelector('#reference').click(); true")
    for _ in range(100):
        if not wall()["capturing"]: break
        time.sleep(.1)
    result = wall("captureData")
    # Capture source references do not get a placement until explicitly added.
    wall("savePage")
    wall("note", title="Navigation tokens", text="Olive accent · 10 pt corner radius\nKeep page actions explicit and close to their source.")
    picture("03-space-wall.png")
    wall("search")
    sv.cmd({"do": "field", "text": "wall: navigation"})
    picture("04-object-search.png")
    wall("capturePicture", path=str(output / "05-capture-inspector.png"))
    metadata = {"provenance": "Native debug app renders in an isolated hidden test world; local sample webpage.",
                "inspector": "Separate native UICaptureInspector render, not a full-window screenshot.",
                "world": sv.W, "source": "Tests/workflow_screenshots.py", "captureID": result["object"]["id"],
                "screenshots": sorted(p.name for p in output.glob("*.png"))}
    (output / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
finally:
    sv.finish()
