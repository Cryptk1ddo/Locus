#!/usr/bin/env python3
"""Synthetic visible Canvas fixture for desktop QA; stop with build/canvas-desktop.stop."""
import sys,time,subprocess,json,os
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('canvas-desktop-qa')
stop=sv.ROOT/'build/canvas-desktop.stop'
if stop.exists(): stop.unlink()
# Reuse only this test's disposable profile, never a user's app session.
if os.path.exists(sv.SOCK):
    try:sv.cmd({'do':'quit'})
    except Exception:pass
    time.sleep(1)
sv.setup(sidebar=False)
subprocess.run(['open','-n','--env','SEARCH_PROBE='+sv.W,'--env','SEARCH_DESKTOP_QA=1',sv.APP])
for _ in range(100):
    if os.path.exists(sv.SOCK):break
    time.sleep(.1)
try:
    time.sleep(2);sv.page('design-reference')
    data={'nodes':[{'id':'group','type':'group','x':70,'y':70,'width':770,'height':380,'label':'Design research','color':'4'},{'id':'text','type':'text','x':100,'y':120,'width':300,'height':250,'text':'# Quiet interfaces\n\nKeep the webpage primary.\n\n- Capture the component\n- Connect the evidence\n- Return to the work','color':'4'},{'id':'reference','type':'text','x':500,'y':130,'width':280,'height':220,'text':'## Questions\n\nWhat makes this interaction feel calm?\n\n**Structure** before decoration.','color':'6'}],'edges':[{'id':'edge','fromNode':'text','toNode':'reference','fromSide':'right','toSide':'left','label':'Informs','color':'4'}]}
    sv.cmd({'do':'wall','action':'canvasImport','json':json.dumps(data)});sv.cmd({'do':'wall','action':'open'})
    print(json.dumps({'world':sv.W,'socket':sv.SOCK,'support':sv.SUPPORT}),flush=True)
    while not stop.exists():time.sleep(.5)
finally:sv.finish()
