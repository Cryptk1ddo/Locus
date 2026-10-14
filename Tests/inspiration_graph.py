#!/usr/bin/env python3
"""Native inspiration/graph/AI checks using isolated preferences and a local fixture.
Screenshots are native app renders, not external provider pages or design mockups.
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv
sv.use("inspiration-graph-tests")
t = sv.T()
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else sv.ROOT / "artifacts" / "inspiration"
output.mkdir(parents=True, exist_ok=True)
mode = "answer"
HTML = b'''<!doctype html><html><head><title>Atlas / Interface research</title><meta name="description" content="A study of quiet interfaces, generous spacing and explicit actions."><style>
*{box-sizing:border-box}body{margin:0;background:#f4f3ee;color:#30352e;font:15px -apple-system}main{max-width:920px;margin:auto;padding:40px 48px}header{display:flex;justify-content:space-between;font-size:12px}.brand{font-weight:650;font-size:19px}h1{font-size:52px;line-height:1.05;font-weight:530;letter-spacing:-2px;margin:66px 0 24px}.intro{max-width:460px;color:#797d71;line-height:1.6}.component{margin-top:38px;padding:30px;background:#fff;border:1px solid #e3e4da;border-radius:16px}.eyebrow{color:#828675;letter-spacing:1.4px;font-size:10px}h2{font-weight:550;font-size:22px}.row{display:flex;justify-content:space-between;align-items:center;gap:20px}button{--accent:#57614c;background:var(--accent);border:0;color:#fff;border-radius:10px;padding:14px 22px;font:500 14px -apple-system}button::before{content:'+';margin-right:9px}footer{margin-top:28px;font-size:11px;color:#949887}
</style></head><body><main><header><span class="brand">Atlas / Patterns</span><span>RESEARCH &nbsp; / &nbsp; DESIGN</span></header><h1>Small interfaces.<br>Clear decisions.</h1><p class="intro">A quiet primary action and generous spacing. Collect the reference, inspect its UI, and connect the evidence to your design notes.</p><section class="component"><span class="eyebrow">INTERACTION / 03</span><div class="row"><div><h2>Save a reference</h2><p class="intro">An explicit action. Context stays with the page.</p></div><button id="reference" aria-label="Save reference">Save reference</button></div></section><footer>Local sample page - Locus workflow evidence</footer></main></body></html>'''
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.send_header("Content-Length", str(len(HTML))); self.end_headers(); self.wfile.write(HTML)
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if mode == "failure":
            body = b'{"error":{"message":"Fixture unavailable"}}'
            self.send_response(500); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
        payload = {"choices": [{"delta": {"content": "The reference uses a quiet primary action and generous spacing. A model suggestion: https://invented.invalid/pattern"}}]}
        body = ("data: " + json.dumps(payload) + "\n\ndata: [DONE]\n\n").encode()
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *args): pass
server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
sv.BASE = f"http://127.0.0.1:{server.server_port}"
def wall(action="state", **fields): return sv.cmd({"do": "wall", "action": action, **fields})
def ai(action="state", **fields): return sv.cmd({"do": "ai", "action": action, **fields})
def until(fn, seconds=12):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = fn()
        if result: return result
        time.sleep(.1)
    raise RuntimeError("Timed out waiting for native fixture")
def ready(page):
    def check():
        try: return sv.ev(page, "document.title") == "Atlas / Interface research"
        except RuntimeError: return False
    until(check)
def finished_ai():
    state = ai()
    return state if state.get("turns") and state["turns"][-1]["done"] and state["turns"][-1]["checked"] else None
def data(id): return wall("pageData", id=id)["object"]
def snap(name, action="picture", **fields):
    wall(action, path=str(output / name), **fields)

try:
    sv.setup(sidebar=True, spaces=True); sv.launch()
    page = sv.page("interface-study"); ready(page)
    sv.cmd({"do": "pages", "on": True})
    before = wall()["builtTabs"]
    wall("captureSelector", selector="#reference"); until(lambda: not wall()["capturing"])
    capture = wall("captureData")["object"]
    source = capture["relationships"][0]["targetID"]
    wall("collectInspiration"); until(lambda: not wall()["collecting"])
    inspirations = [x for x in wall()["objects"] if x["type"] == "inspiration"]
    t.ok("visited page becomes structured inspiration", len(inspirations) == 1)
    clip = data(inspirations[0]["id"])
    t.ok("collection keeps mounted WebKit ownership", wall()["builtTabs"] == before)
    t.ok("clip retains description and source", "quiet interfaces" in clip["content"]["description"] and clip["relationships"][0] == {"kind":"collectedFrom", "targetID": source})
    asset = Path(sv.SUPPORT) / "workspaces" / wall()["spaceID"] / "assets" / (clip["content"]["screenshot"]["value"]["assetID"] + ".png")
    t.ok("visual preview is an owned PNG", asset.exists() and asset.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n')
    snap("01-inspiration-inspector.png", "evidencePicture")
    wall("savePage")
    wall("note", title="Design direction", text="Preserve a quiet primary action.\nUse generous spacing and explicit source references.")
    note = wall()["objects"][-1]["id"]
    wall("inspirationLink", url="https://www.pinterest.com/pin/123456789/", title="Pinterest · Layout reference")
    pin = wall()["objects"][-1]["id"]
    t.ok("Pinterest link is classified without creating a tab", data(pin)["content"]["provider"] == "pinterest" and data(pin)["content"]["resourceKind"] == "pin" and wall()["builtTabs"] == before)
    wall("connect", source=note, target=clip["id"], kind="inspiredBy", label="Quiet action")
    wall("connect", source=note, target=capture["id"], kind="supports", label="Spacing and tokens")
    wall("connect", source=pin, target=note, kind="relatedTo")
    t.ok("semantic and provenance wires share the canvas", wall()["wires"] == 5)
    wall("resize", id=clip["id"], width=300, height=250)
    p = next(x for x in wall()["placementData"] if x["object"] == clip["id"])
    t.ok("native card size persists in workspace", (p["width"], p["height"]) == (300, 250))
    wall("removePlacements", id=clip["id"])
    t.ok("removing card keeps semantic research link", data(note)["relationships"][0]["targetID"] == clip["id"] and wall()["wires"] == 3)
    wall("place", id=clip["id"])
    t.ok("replacing card restores graph projection", wall()["wires"] == 5)
    wall("search", typed="wall: quiet interfaces")
    t.ok("description is searchable by explicit Wall intent", any(x.get("object") == clip["id"] for x in wall()["offers"]))
    wall("close")
    ai("mock", url=sv.BASE + "/v1"); ai("use", provider="ollama", model="local-fixture")
    ai("summarize", id=page); state = until(finished_ai)
    t.ok("completed normal AI answer can be saved", state["turns"][-1]["canSave"])
    wall("saveAI")
    answer = [x for x in wall()["objects"] if x["type"] == "aiOutput"][-1]
    evidence = data(answer["id"])
    t.ok("AI evidence preserves actual read source and attribution", evidence["relationships"][0]["targetID"] == source and evidence["content"]["model"] == "local-fixture" and evidence["content"]["sourceTitle"] == "Atlas / Interface research")
    t.ok("AI cautions remain data and text creates no navigation", evidence["content"]["strays"] and wall()["builtTabs"] == before)
    wall("saveAI")
    t.ok("repeated save after panel closes creates no duplicate", len([x for x in wall()["objects"] if x["type"] == "aiOutput"]) == 1)
    # Explicitly updating a page reference must not retarget an AI answer's evidence.
    sv.ev(page, "history.pushState({}, '', '/updated-reference'); true"); time.sleep(.2)
    wall("updatePage", id=source)
    t.ok("source reference can be explicitly updated", data(source)["content"]["url"].endswith('/updated-reference'))
    wall("openAIReadSource", id=answer["id"])
    opened = sv.sp("state")["activeID"]; ready(opened)
    t.ok("AI source action opens the immutable read URL", sv.url(sv.sp("state"), opened) == evidence["content"]["url"])
    sv.sp("close", id=opened); sv.sp("select", id=page)
    sv.ev(page, "history.pushState({}, '', '/interface-study'); true"); time.sleep(.2)
    wall("updatePage", id=source)
    # Lay out a real native canvas for reproducible visual evidence.
    for id, x, y in [(source, 30, 30), (capture["id"], 30, 280), (clip["id"], 345, 35), (note, 705, 70), (answer["id"], 360, 355), (pin, 705, 360)]:
        wall("move", id=id, x=x, y=y)
    wall("resize", id=note, width=240, height=210)
    wall("resize", id=answer["id"], width=290, height=205)
    wall("close"); time.sleep(.3)
    wall("viewport", x=0, y=0, zoom=.85)
    snap("02-connected-wall.png")
    snap("03-connections.png", "connectionsPicture", id=note)
    snap("04-ai-evidence.png", "evidencePicture")
    wall("close")
    count = len(wall()["objects"])
    mode = "failure"; ai("summarize", id=page); state = until(finished_ai)
    wall("saveAI")
    t.ok("failed model response stays ephemeral", state["turns"][-1]["failed"] and not state["turns"][-1]["canSave"] and len(wall()["objects"]) == count)
    mode = "answer"
    # Visible user-entered content suppresses the page preview but not the safe component picker.
    sv.ev(page, "document.body.insertAdjacentHTML('beforeend', '<input id=private-value value=DO-NOT-SAVE style=\"position:fixed;top:10px;left:10px\">'); true")
    wall("collectInspiration"); until(lambda: not wall()["collecting"])
    safe = data([x for x in wall()["objects"] if x["type"] == "inspiration"][-1]["id"])
    t.ok("visible populated form suppresses whole-page preview", safe["content"]["screenshot"]["value"] is None and "DO-NOT-SAVE" not in json.dumps(safe))
    sv.ev(page, "document.querySelector('#private-value').remove(); document.body.insertAdjacentHTML('beforeend','<custom-form style=\"position:fixed;top:10px;left:10px;display:block;width:150px;height:40px\"></custom-form>'); document.querySelector('custom-form').attachShadow({mode:'open'}).innerHTML='<input value=SHADOW-SECRET>'; true")
    wall("collectInspiration"); until(lambda: not wall()["collecting"])
    shadow = data([x for x in wall()["objects"] if x["type"] == "inspiration"][-1]["id"])
    t.ok("opaque component preview is conservatively omitted", shadow["content"]["screenshot"]["value"] is None and "SHADOW-SECRET" not in json.dumps(shadow))
    sv.ev(page, "document.querySelector('custom-form').remove(); true")
    # WebKit evaluation is async: changing URL immediately must invalidate a pending clip.
    count = len(wall()["objects"])
    wall("collectInspiration", delay=.5)
    sv.ev(page, "history.pushState({}, '', '/changed-before-commit'); true")
    until(lambda: not wall()["collecting"])
    t.ok("navigation rejects stale collection", len(wall()["objects"]) == count)
    wall("collectInspiration", delay=.5)
    sv.cmd({"do": "space", "action": "new", "name": "Design alternatives"})
    time.sleep(.65)
    t.ok("Space switch cancels a held collection", not wall()["collecting"] and not wall()["objects"])
    t.ok("new Space has independent inspiration and viewport", not wall()["objects"] and wall("viewport")["zoom"] == 1)
    wall("inspirationLink", url="https://www.are.na/alex/interface-research", title="Are.na · Research channel")
    t.ok("alternative source is a typed reference", data(wall()["objects"][-1]["id"])["content"]["resourceKind"] == "channel")
    sv.cmd({"do": "space", "action": "go", "index": 1})
    t.ok("held clip never reaches the original Space", len(wall()["objects"]) == count)
    sv.sp("private"); private = sv.sp("open", url=sv.BASE + "/private")["resultID"]; ready(private)
    t.ok("private page cannot collect durable inspiration", not wall()["canCollect"])
    ai("summarize", id=private); state = until(finished_ai)
    count = len(wall()["objects"]); wall("saveAI")
    t.ok("private local AI remains ephemeral", not state["turns"][-1]["canSave"] and len(wall()["objects"]) == count)
    sv.sp("private")
    wall("close"); time.sleep(.3)
    wall("viewport", x=-120, y=80, zoom=.75)
    before_restart = wall(); sv.sp("save"); sv.quit(); sv.launch()
    t.ok("graph, resized objects and PNG survive restart", wall()["objects"] == before_restart["objects"] and wall()["wires"] == before_restart["wires"] and asset.exists())
    view = wall("viewport")
    t.ok("per-window Space viewport survives restart", view == {"x": -120, "y": 80, "zoom": .75}, view)
    wall("deleteObject", id=clip["id"])
    t.ok("deleting inspiration retains recoverable PNG and removes incoming links", asset.exists() and all(x["targetID"] != clip["id"] for x in data(note)["relationships"]))
    wall("note", title="Advance recovery copy")
    t.ok("retired preview is cleaned after backup advances", not asset.exists())
    (output / "manifest.json").write_text(json.dumps({"provenance": "Native app views rendered in an isolated hidden test world using a local reference and local mock AI server. Pinterest and Are.na cards are saved links, not authenticated imports.", "world": sv.W, "source": "Tests/inspiration_graph.py", "screenshots": sorted(x.name for x in output.glob("*.png"))}, indent=2) + "\n")
finally:
    server.shutdown(); t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
