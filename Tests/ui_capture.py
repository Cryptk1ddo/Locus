#!/usr/bin/env python3
"""Native capture through the existing WKWebView in an isolated hidden world."""
import json
import sys
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv
sv.use("capture-tests")
t = sv.T()
def wall(action="state", **fields): return sv.cmd({"do":"wall", "action":action, **fields})
def wait_done():
    for _ in range(100):
        state = wall()
        if not state["capturing"]: return state
        time.sleep(.1)
    raise RuntimeError("Capture never finished")
def ev(js, world="page"): return sv.cmd({"do":"eval", "id":page, "js":js, "world":world}).get("value")
def capture(selector):
    wall("captureSelector", selector=selector); wait_done()
    return wall("captureData")
try:
    sv.setup(); sv.launch(); page = sv.page("reference")
    for _ in range(100):
        if wall()["canCapture"] and ev("document.readyState") == "complete": break
        time.sleep(.1)
    ev("""document.body.innerHTML = `<section id="component"><button id="target" aria-label="Save reference" style="--accent: rgb(40, 50, 60); padding:20px; font-size:16px; background:#eee; color:#111">Save reference</button><input value="FIELD-SECRET"><textarea>TEXTAREA-SECRET</textarea><a href="/target?token=ASSET-SECRET#fragment">Link</a><span hidden>HIDDEN-SECRET</span><script>NOT-CAPTURED</script></section>`;
      const style = document.createElement('style'); style.textContent = '#target::before {content:"+";margin-right:8px}'; document.head.append(style);
      window.clicked = 0; document.querySelector('#target').onclick = () => window.clicked++; true;
    """)
    before = wall()["builtTabs"]
    result = capture("#target")
    obj = result["object"]; content = obj["content"]
    t.ok("capture is a structured Wall object", obj["type"] == "uiCapture" and wall()["showing"])
    t.ok("capture keeps existing WebKit views", wall()["builtTabs"] == before)
    t.ok("capture records CSS and custom properties", content["css"]["status"] == "captured" and "--accent" in content["customProperties"]["value"])
    t.ok("capture records pseudo-elements and geometry", "::before" in content["pseudoElements"]["value"] and content["geometry"]["value"]["width"] > 0)
    t.ok("capture records inferred accessibility", content["accessibility"]["value"]["name"] == "Save reference")
    t.ok("non-link elements do not invent link URLs", content["interactions"]["value"]["href"] == "")
    t.ok("capture links a durable source page", obj["relationships"][0]["kind"] == "capturedFrom")
    t.ok("visible crop is an owned PNG", content["screenshot"]["status"] == "captured" and result["assetExists"], content["screenshot"])
    wall("capturePicture", path="/tmp/locus-capture-preview.png")
    # Capture a parent containing editable and hidden data; none of that enters DOM or AX.
    content = capture("#component")["object"]["content"]
    serialized = json.dumps(content)
    t.ok("editable and hidden contents omitted", all(secret not in serialized for secret in ["FIELD-SECRET","TEXTAREA-SECRET","HIDDEN-SECRET","NOT-CAPTURED","ASSET-SECRET"]))
    t.ok("editable subtree screenshot is unavailable", content["screenshot"]["status"] == "unavailable")
    count = len(wall()["objects"])
    wall("captureSelector", selector="input"); wait_done()
    t.ok("direct field selection creates no object", len(wall()["objects"]) == count)
    wall("capture"); time.sleep(.3)
    t.ok("picker starts in the existing document", wall()["capturing"])
    sv.cmd({"do":"press", "code":53, "chars":"", "mods":[]}); time.sleep(.2)
    t.ok("Escape cancels picker and cleans injected state", not wall()["capturing"] and ev("!!window.__locusCapture", world="search") is False)
    wall("capture"); time.sleep(.3)
    # Dispatch the click through DOM event propagation, exercising the installed picker.
    ev("document.querySelector('#target').click()")
    wait_done()
    t.ok("picker captures without activating page action", ev("window.clicked") == 0 and len(wall()["objects"]) == count + 1)
    wall("capture"); time.sleep(.2)
    sv.sp("open", url=f"{sv.BASE}/other"); time.sleep(.4)
    t.ok("tab change cancels pending capture", not wall()["capturing"])
    sv.cmd({"do":"select", "id":page})
    wall("capture"); time.sleep(.2)
    ev("history.pushState({}, '', '/spa-change'); true")
    time.sleep(.3)
    t.ok("SPA URL change cancels pending capture", not wall()["capturing"])
    wall("capture"); time.sleep(.2)
    ev("location.href = '/navigated'"); time.sleep(.6)
    t.ok("navigation cancels pending capture", not wall()["capturing"])
    sv.sp("private"); sv.sp("open", url=f"{sv.BASE}/private"); time.sleep(.5)
    t.ok("private page cannot capture UI", not wall()["canCapture"])
    wall("capture")
    t.ok("private capture request stays off", not wall()["capturing"])
    sv.quit(); sv.launch()
    t.ok("capture and asset survive restart", wall("captureData")["assetExists"])
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
