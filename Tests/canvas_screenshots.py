#!/usr/bin/env python3
"""Render synthetic Canvas workflow states through the app's test-only Bench API."""
import json,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('canvas-render-workflow')
output=sv.ROOT/'artifacts/canvas'
output.mkdir(parents=True,exist_ok=True)
def wall(action='state',**fields):return sv.cmd({'do':'wall','action':action,**fields})
def click(x,y,count=1):
    sv.sp('mouse',points=[[x,y],[x,y]],to='view',clicks=count)
    time.sleep(.25)
def picture(name):
    result=sv.cmd({'do':'picture','path':str(output/name),'page':False})
    if 'error' in result:raise RuntimeError(result['error'])
    print(name,result,flush=True)
try:
    sv.setup(sidebar=False);sv.launch();sv.page('design-reference')
    data={'nodes':[
        {'id':'group','type':'group','x':70,'y':70,'width':770,'height':380,'label':'Design research','color':'4'},
        {'id':'text','type':'text','x':100,'y':120,'width':300,'height':250,'text':'# Quiet interfaces\n\nKeep the webpage primary.\n\n- Capture the component\n- Connect the evidence\n- Return to the work','color':'4'},
        {'id':'reference','type':'text','x':500,'y':130,'width':280,'height':220,'text':'## Questions\n\nWhat makes this interaction feel calm?\n\n**Structure** before decoration.','color':'6'}],
        'edges':[{'id':'edge','fromNode':'text','toNode':'reference','fromSide':'right','toSide':'left','label':'Informs','color':'4'}]}
    pane=sv.sp('state')['paneFrames'][0];x,y=pane['x'],pane['y']
    wall('canvasImport',json=json.dumps(data));wall('open');time.sleep(.6)
    picture('01-canvas-native-render.png')
    click(x+250,y+218);picture('02-selected-card-native-render.png')
    click(x+250,y+218,2);picture('03-inline-editor-native-render.png')
    sv.cmd({'do':'press','code':53,'chars':'','mods':[]});time.sleep(.2)
    click(x+450,y+244);picture('04-selected-connection-native-render.png')
    manifest={'provenance':'AppKit bitmap render of the running native Locus QA app through its test-only Bench picture interface; synthetic content only. These are app renders, not desktop screenshots.','world':sv.W,'source':'Tests/canvas_screenshots.py','screenshots':sorted(p.name for p in output.glob('*native-render.png')),'canvas':wall('canvasState')}
    (output/'render-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
finally:sv.finish()
