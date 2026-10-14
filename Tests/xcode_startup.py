#!/usr/bin/env python3
"""Native app launch/scene diagnostics, with a separately signed test copy."""
import argparse
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from http.server import BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, required=True)
parser.add_argument("--log-prefix", type=Path, default=Path("/tmp/locus-xcode-startup"))
parser.add_argument("--screenshots", type=Path, help="save native page/split renders in this directory")
args = parser.parse_args()
source = args.app.resolve()
if not (source / "Contents/MacOS/Search").is_file():
    parser.error("--app must point to the built Search.app")

t = sv.T()
logs = []

class RenderPage(BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.strip("/")
        colour = "#d8e4d1" if name == "native-two" else "#e0e8f2"
        body = f"""<!doctype html><title>{name}</title><style>
        body {{margin:0;padding:48px;background:{colour};color:#253040;font:18px -apple-system}}
        h1 {{font-size:36px;font-weight:500;letter-spacing:-1px}} p {{line-height:1.6}}
        section {{padding:32px;background:#ffffffb0;border-radius:16px;max-width:560px}}
        </style><h1>{name}</h1><section><p>Locus native rendering check</p>
        <p>This page must remain visible after navigation, Space restoration,
        and a WebKit process restart.</p></section>""".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass

sv.srv.RequestHandlerClass = RenderPage

def launch():
    index = len(logs) // 2 + 1
    out = Path(f"{args.log_prefix}.{index}.stdout.log")
    err = Path(f"{args.log_prefix}.{index}.stderr.log")
    for path in (out, err): path.write_text("")
    logs.extend((out, err))
    if os.path.exists(sv.SOCK): os.remove(sv.SOCK)
    before = sv.running()
    subprocess.run(["open", "-n", "-g", "-j", "--stdout", str(out), "--stderr", str(err),
                    "--env", f"SEARCH_PROBE={sv.W}", "--env", "OS_ACTIVITY_DT_MODE=enable", sv.APP], check=True)
    for _ in range(150):
        if os.path.exists(sv.SOCK): break
        time.sleep(.1)
    time.sleep(2)
    sv.started.update((sv.running() - before) & sv.holding())
    if not os.path.exists(sv.SOCK): raise RuntimeError("native app did not finish launching")

def page_title(tab, expected):
    last = ""
    for _ in range(100):
        try: last = sv.ev(tab, "document.title")
        except RuntimeError as error: last = str(error)
        if last == expected: return True, last
        time.sleep(.1)
    return False, last

def mounted(*tabs):
    last = []
    for _ in range(100):
        last = sv.sp("state")["paneFrames"]
        frames = {frame["id"]: frame for frame in last}
        if all(tab in frames and frames[tab]["width"] > 100 and frames[tab]["height"] > 100
               and frames[tab]["alpha"] > .99 and not frames[tab]["hidden"]
               and not frames[tab]["unpainted"] for tab in tabs): return True, last
        time.sleep(.1)
    return False, last

def picture(name):
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
        sv.cmd({"do": "pages", "on": True})
        sv.cmd({"do": "picture", "path": str((args.screenshots / name).resolve()), "page": False})

def terminate_page(tab):
    # The PID comes from this run's signed copy and isolated browser profile,
    # never from a machine-wide WebContent process search.
    page = next(page for page in sv.cmd({"do": "tabs"})["tabs"] if page["id"] == tab)
    pid = page["process"]
    if pid <= 1: raise RuntimeError("page has no WebKit process to terminate")
    command = subprocess.run(["ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True, check=True).stdout
    if "com.apple.WebKit.WebContent" not in command:
        raise RuntimeError(f"refusing to terminate a process other than WebKit: {command.strip()}")
    os.kill(pid, signal.SIGKILL)
    return pid

with tempfile.TemporaryDirectory(prefix="locus-xcode-probe-") as directory:
    app = Path(directory) / "Search.app"
    shutil.copytree(source, app)
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    token = uuid.uuid4().hex[:12]
    # Both WebKit's container and the browser sidecar belong to this run.
    info["CFBundleIdentifier"] = f"com.cryptk1ddo.locus.startup-tests.{token}"
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-",
                    "--preserve-metadata=entitlements,flags", str(app)], check=True, capture_output=True)
    sv.APP = str(app)
    sv.use(f"xcode-startup-{token}")
    try:
        sv.setup(spaces=True, splitView=True, **{"tabs.groups": True})
        launch()
        t.ok("native app has complete application identity", info["CFBundlePackageType"] == "APPL"
             and bool(info["CFBundleIdentifier"]) and info["CFBundleExecutable"] == "Search"
             and all(info.get(key) for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSLocationUsageDescription"]))
        st = sv.sp("state")
        first_space = st["spaceID"]
        t.ok("primary scene starts with a valid active tab", st["activeID"] in sv.order(st))
        a = sv.page("native-one")
        ready, title = page_title(a, "native-one")
        t.ok("WebKit loads and evaluates a page", ready, title)
        ready, frames = mounted(a)
        t.ok("loaded page is mounted, sized and visible", ready, frames)
        picture("01-page.png")
        sv.cmd({"do": "go", "id": a, "url": f"{sv.BASE}/native-next"}); time.sleep(.9)
        ready, title = page_title(a, "native-next")
        t.ok("WebKit navigation works", ready, title)
        b = sv.page("native-two")
        page_title(b, "native-two")
        sv.sp("pair", id=b, **{"with": a})
        ready, frames = mounted(a, b)
        t.ok("both split pages are mounted and visible", ready and len(sv.sp("state")["splits"]) == 1, frames)
        picture("02-split.png")
        sv.sp("focus", id=a)
        old_pid = terminate_page(b)
        ready, title = page_title(b, "native-two")
        new_pid = next(page["process"] for page in sv.cmd({"do": "tabs"})["tabs"] if page["id"] == b)
        t.ok("unfocused split pane recovers from a real process crash", ready and new_pid > 1
             and new_pid != old_pid and sv.sp("state")["activeID"] == a, title)
        ready, frames = mounted(a, b)
        t.ok("recovered split retains both visible views", ready, frames)
        picture("03-recovered-split.png")
        terminate_page(a)
        ready, title = page_title(a, "native-next")
        t.ok("focused pane recovers from a real process crash", ready, title)
        sv.cmd({"do": "wall", "action": "note", "title": "First Space", "text": "Saved in its Space"})
        sv.sp("space", spaceAction="new", name="Native Two"); time.sleep(.7)
        t.ok("another Space has its own Wall", sv.cmd({"do": "wall"})["objects"] == [])
        c = sv.page("native-space")
        sv.cmd({"do": "wall", "action": "note", "title": "Second Space", "text": "Restored"})
        sv.sp("save"); sv.quit(); launch()
        st = sv.sp("state")
        t.ok("restart restores the Space, tab and objects", st["spaceID"] != first_space
             and any(x["url"].endswith("/native-space") for x in st["tabs"])
             and [o["title"] for o in sv.cmd({"do": "wall"})["objects"]] == ["Second Space"])
        ready, title = page_title(st["activeID"], "native-space")
        t.ok("restored active page loads its document", ready, title)
        ready, frames = mounted(st["activeID"])
        t.ok("restored page is visibly mounted", ready, frames)
        sv.sp("space", spaceAction="go", spaceID=first_space); time.sleep(.7)
        t.ok("original Space retains its split and object", len(sv.sp("state")["splits"]) == 1
             and [o["title"] for o in sv.cmd({"do": "wall"})["objects"]] == ["First Space"])
        for page in sv.sp("state")["tabs"]:
            if page["url"].endswith(("/native-next", "/native-two")):
                page_title(page["id"], page["url"].rsplit("/", 1)[1])
        ready, frames = mounted(*sv.sp("state")["visibleIDs"])
        t.ok("Space switch restores both rendered panes", ready, frames)
        sv.quit()
        text = "\n".join(path.read_text(errors="replace") for path in logs)
        t.ok("scene rendering does not publish state changes", "Publishing changes from within view updates" not in text)
        t.ok("window indexing has an application identifier", "missing main bundle identifier" not in text)
        print("Captured logs: " + ", ".join(str(path) for path in logs))
    finally:
        t.done()
        sv.finish()
        bundle_id = info["CFBundleIdentifier"]
        subprocess.run(["defaults", "delete", bundle_id], capture_output=True)
        for root in ("WebKit", "Caches"):
            shutil.rmtree(Path(sv.HOME) / "Library" / root / bundle_id, ignore_errors=True)

sys.exit(1 if t.failed else 0)
