#!/usr/bin/env python3
"""Native URL drag-data reader in an isolated profile; desktop gestures are QA'd separately."""
import json
import sys
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('wall-drop-tests')
t = sv.T()
out = sv.ROOT / 'artifacts' / 'wall-drops'
out.mkdir(parents=True, exist_ok=True)
def wall(action='state', **fields): return sv.cmd({'do':'wall','action':action,**fields})
def wait_for(predicate):
    for _ in range(100):
        if predicate(): return True
        time.sleep(.1)
    return False
def drop(links, **fields): return wall('dropLinks', links=links, x=160, y=145, **fields)['accepted']
def picture(name):
    time.sleep(.5)
    sv.cmd({'do':'picture', 'path':str(out/name), 'page':False})
try:
    sv.setup(sidebar=False, spaces=True); sv.launch()
    page = sv.page('inspiration-links'); wait_for(lambda: wall()['canCapture'])
    sv.ev(page, "document.title='Inspiration research';window.keepForWall=91;true")
    original = wall()['builtTabs']
    t.ok('web page cannot receive durable Wall link drops', not drop([{'url':'https://example.com/'}]))
    wall('viewport',x=60,y=20,zoom=1.25); wall('open'); time.sleep(.4)
    view = wall('viewport')
    t.ok('native URL-provider reader accepts a reference',drop([{'url':'https://www.pinterest.com/pin/12345/'}]))
    wait_for(lambda: len(wall()['objects'])==1)
    state = wall(); first = state['placementData'][0] if state['placementData'] else {}
    t.ok('canvas coordinates invert pan and zoom', first.get('x')==80 and first.get('y')==100, first)
    pin = state['objects'][0]['id'] if state['objects'] else ''
    if pin:
        data = wall('pageData',id=pin)['object']
        t.ok('native drop uses the existing structured Pinterest payload', data['type']=='inspiration' and data['content']['provider']=='pinterest' and data['content']['remoteID']=='12345' and data['relationships']==[])
    t.ok('native URL reader saves one durable revision',state['revision']==1)
    t.ok('drop keeps the selected native Wall and its viewport',state['showing'] and wall('viewport')==view)
    t.ok('URL drop creates no additional WebKit view',state['builtTabs']==original, state['builtTabs'])
    before = state['revision']
    rows = [{'url':'https://user:secret@www.are.na/alex/quiet-interfaces','title':'Quiet interfaces'},
            {'url':'https://www.are.na/alex/quiet-interfaces','title':'Duplicate'},
            {'url':'javascript:alert(1)'}, {'url':'file:///tmp/private'},
            {'url':'https://dribbble.com/shots/3456','title':'Type and rhythm'}]
    t.ok('batch URL-provider request is accepted',drop(rows))
    wait_for(lambda: wall()['revision']>before); state=wall()
    t.ok('valid links commit together while invalid/duplicate items are skipped',state['revision']==before+1 and len(state['objects'])==3 and state['announcement'].endswith('3 skipped'), state)
    t.ok('provider completion order does not alter card order', [x['title'] for x in state['objects'][1:]]==['Quiet interfaces','Type and rhythm'])
    arena = wall('pageData',id=state['objects'][1]['id'])['object']
    t.ok('URL credentials are removed before persistence',arena['content']['url']=='https://www.are.na/alex/quiet-interfaces' and arena['content']['provider']=='arena')
    t.ok('a batch uses world-space three-column spacing', state['placementData'][2]['x']-state['placementData'][1]['x']==280)
    count = len(state['objects'])
    t.ok('over-limit native reader request is rejected',not drop([{'url':'https://example.com/'+str(i)} for i in range(21)]))
    drop([{'url':'file:///tmp/secret'}]); time.sleep(.3)
    t.ok('unsupported native URL payload creates no object',len(wall()['objects'])==count)
    t.ok('delayed provider begins in its Wall',drop([{'url':'https://example.com/stale-tab'}],delay=.7))
    sv.sp('select',id=page); wall('open'); time.sleep(.9)
    t.ok('leaving and returning cancels a delayed drop',len(wall()['objects'])==count)
    drop([{'url':'https://example.com/stale-space'}],delay=.7)
    first_space=wall()['spaceID']
    sv.cmd({'do':'space','action':'new','name':'Other research'}); wall('open'); time.sleep(.9)
    t.ok('Space switch cannot redirect a delayed payload',len(wall()['objects'])==0)
    sv.cmd({'do':'space','action':'go','index':1})
    t.ok('original Space also rejects the cancelled payload',wall()['spaceID']==first_space and len(wall()['objects'])==count)
    drop([{'url':'https://example.com/closed-wall'}],delay=.7); wall('close'); wall('open'); time.sleep(.9)
    t.ok('closing a Wall cancels its pending drop',len(wall()['objects'])==count)
    sv.sp('select',id=page)
    t.ok('source page document survives every drop and Wall switch',sv.ev(page,'window.keepForWall')==91)
    wall('open')
    # Show native app results with independently positioned references and a note.
    for i,obj in enumerate(wall()['objects']): wall('move',id=obj['id'],x=40+i*280,y=40)
    wall('note',title='Research directions',text='Collect links while browsing. Inspect the reference, visit its source, then capture the interface when it is useful.')
    note=wall()['objects'][-1]['id']; wall('move',id=note,x=40,y=260)
    sv.cmd({'do':'pages','on':True}); picture('01-dropped-inspiration-links.png')
    saved = wall(); sv.sp('save'); sv.quit(); sv.launch()
    t.ok('restart restores all objects and spatial positions',wall()['objects']==saved['objects'] and wall()['placementData']==saved['placementData'])
    t.ok('restart restores the independent pan and zoom',wall('viewport')==view)
    t.ok('restored native Wall still creates no WebKit view',wall()['showing'] and wall()['builtTabs']==[])
    sv.cmd({'do':'pages','on':True}); picture('02-restored-wall.png')
    # Corrupt only this disposable world's sidecar, then reopen read-only.
    sv.quit(); path=Path(sv.SUPPORT,'workspaces',first_space,'workspace.json'); path.write_text('damaged test snapshot')
    sv.launch()
    t.ok('unavailable Wall rejects URL drops',not wall()['writable'] and not drop([{'url':'https://example.com/read-only'}]))
    t.ok('rejected read-only drop preserves the damaged bytes',path.read_text()=='damaged test snapshot')
    (out/'manifest.json').write_text(json.dumps({'source':'Tests/wall_drops.py','world':sv.W,
        'provenance':'Native app screenshots in an isolated profile. Real URL-provider callbacks through the production reader; desktop gestures checked separately. No provider account access.',
        'screenshots':sorted(p.name for p in out.glob('*.png'))},indent=2)+'\n')
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
