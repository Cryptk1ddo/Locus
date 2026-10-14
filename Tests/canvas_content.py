#!/usr/bin/env python3
"""Use native text links to exercise tasks and Space-local wiki navigation."""
import json,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('canvas-content');t=sv.T()
def wall(action='state',**kw):return sv.cmd({'do':'wall','action':action,**kw})
def click(point):sv.sp('mouse',points=[point,point],to='view');time.sleep(.3)
def links():return wall('canvasContentInfo')['previews'][0]['links']
def noteText(objectID):
    placement=next(p['id'] for p in wall()['placementData'] if p['object']==objectID)
    return next(n['text'] for n in json.loads(wall('canvasExport')['json'])['nodes'] if n['id']==placement)
try:
    sv.setup(sidebar=False);sv.launch();sv.page('canvas-content')
    pane=sv.sp('state')['paneFrames'][0];x,y=pane['x'],pane['y']
    wall('note',title='Source',text='- [ ] Capture 🌿\n\n[[Reference#Spacing|Read spacing]]')
    source=wall()['objects'][-1]['id']
    wall('note',title='Reference',text='# Reference\n\n## Spacing\nFour units')
    reference=wall()['objects'][-1]['id'];wall('open');time.sleep(.5)
    click([x+80,y+80]);rev=wall()['revision']
    task=next(item for item in links() if item['url'].startswith('locus-task:'))
    click(task['point'])
    changed=noteText(source)
    t.ok('click checkbox updates the correct Markdown source once',changed.startswith('- [x]') and wall()['revision']==rev+1,changed)
    sv.cmd({'do':'picture','path':str(sv.ROOT/'artifacts/refinement/canvas-content-native-render.png'),'page':False})
    wall('canvasUndo');t.ok('undo restores unchecked task',noteText(source).startswith('- [ ]'))
    click([x+80,y+80]);wall('canvasOptions',readOnly=True);click(task['point'])
    t.ok('read-only checkbox cannot alter note',noteText(source).startswith('- [ ]'))
    wall('canvasOptions',readOnly=False)
    wiki=next(item for item in links() if item['url'].startswith('locus-note:'));click(wiki['point'])
    placement=next(p for p in wall()['placementData'] if p['object']==reference)
    t.ok('wiki link selects the existing Space note',placement['id'] in wall('canvasState')['selected'] and wall()['placements']==2,wall('canvasState'))
finally:t.done();sv.finish()
sys.exit(1 if t.failed else 0)
