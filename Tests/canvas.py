#!/usr/bin/env python3
"""Exercise Canvas through native AppKit mouse/keyboard events in an isolated profile."""
import json,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('canvas-tests'); t=sv.T()
def wall(action='state',**kw): return sv.cmd({'do':'wall','action':action,**kw})
def drag(a,b,**kw): return sv.sp('mouse',points=[a,[(a[0]+b[0])/2,(a[1]+b[1])/2],b,b],to='view',**kw)
def click(p,**kw): return sv.sp('mouse',points=[p,p],to='view',**kw)
def key(code,chars='',mods=[]): sv.cmd({'do':'press','code':code,'chars':chars,'mods':mods}); time.sleep(.15)
try:
    sv.setup(sidebar=False); sv.launch(); page=sv.page('canvas')
    pane=sv.sp('state')['paneFrames'][0]; x,y=pane['x'],pane['y']
    wall('note',title='First',text='# Research\nA native Canvas card.'); wall('note',title='Second',text='Source reference')
    wall('open');time.sleep(.6)
    canvas=wall('canvasState');t.ok('Canvas is native and initial viewport is default',canvas['viewport']=={'x':0,'y':0,'zoom':1},canvas)
    rev=wall()['revision']
    drag([x+298,y+218],[x+338,y+248])
    cards=wall()['placementData']; t.ok('any-corner resizing commits once',cards[0]['width']==300 and cards[0]['height']==210 and wall()['revision']==rev+1,cards)
    # Overlap first with second to test hit/z-order naturally; selected resize now300 wide.
    drag([x+80,y+95],[x+110,y+115])
    cards=wall()['placementData']; first=next(p for p in cards if p['x']==70)
    t.ok('drag moves selected card in world coordinates',first['y']==60,cards)
    rev=wall()['revision']; drag([x+20,y+20],[x+640,y+320])
    t.ok('ground drag selects cards without panning or saving',len(wall('canvasState')['selected'])==2 and wall()['revision']==rev,wall('canvasState'))
    drag([x+95,y+120],[x+135,y+160],mods=['shift'])
    # Shift toggles selection first, so only move both after click then marquee again.
    wall('canvasUndo'); time.sleep(.15)
    # Frame selection leaves ground on normal drag, middle pan is distinct.
    before=wall('canvasState')['viewport']; drag([x+750,y+450],[x+800,y+480],button='middle')
    after=wall('canvasState')['viewport'];t.ok('middle-button pan preserves cards',after['x']==before['x']+50 and after['y']==before['y']+30,after)
    before=wall('canvasState')['viewport'];sv.cmd({'do':'press','code':49,'chars':' ','mods':[],'phase':'down'})
    drag([x+800,y+460],[x+830,y+480]);sv.cmd({'do':'press','code':49,'chars':' ','mods':[],'phase':'up'})
    after=wall('canvasState')['viewport'];t.ok('Space-drag pans with native key-down/up',after['x']==before['x']+30 and after['y']==before['y']+20,after)
    drag([x+800,y+460],[x+840,y+490]);t.ok('releasing Space restores selection gestures',wall('canvasState')['viewport']==after)
    key(18,'1',['shift']);t.ok('Shift-1 fits all cards',wall('canvasState')['viewport']['zoom']!=1)
    # Reset with keyboard, then choose first and duplicate via native command.
    key(29,'0',['cmd']);t.ok('reset zoom preserves the current centre and restores 100 percent',wall('canvasState')['viewport']['zoom']==1);wall('viewport',x=0,y=0,zoom=1);time.sleep(.2)
    first=wall()['placementData'][0];click([x+first['x']+30,y+first['y']+50]);key(2,'d',['cmd'])
    t.ok('Command-D duplicates selection',wall()['placements']==3,wall())
    key(6,'z',['cmd']);t.ok('Command-Z undoes duplicate',wall()['placements']==2,wall())
    key(6,'Z',['cmd','shift']);t.ok('Shift-Command-Z restores duplicate',wall()['placements']==3)
    key(6,'z',['cmd'])
    # Double-click ground creates a card and enters inline editor; Escape commits typed source.
    count=wall()['placements'];click([x+650,y+350],clicks=2);wall('canvasInsert',text='Markdown draft');key(53)
    t.ok('double-click creates an inline editable card',wall()['placements']==count+1,wall())
    exported=json.loads(wall('canvasExport')['json']);t.ok('inline edit saved Markdown text',any(n.get('text')=='Markdown draft' for n in exported['nodes']),exported)
    # Connector from first right handle to second top side. Reset and move second aside via model fixture.
    cards=wall()['placementData']; first=cards[0]; second=cards[1]
    secondObj=second['object'];wall('move',id=secondObj,x=450,y=40);time.sleep(.2)
    click([x+first['x']+30,y+first['y']+50]);drag([x+first['x']+first['width'],y+first['y']+first['height']/2],[x+460,y+100])
    exported=json.loads(wall('canvasExport')['json']);t.ok('drag side handle creates placement edge',len(exported['edges'])==1,exported['edges'])
    wall('canvasUndo');t.ok('connector undo is a complete action',not json.loads(wall('canvasExport')['json'])['edges'])
    wall('canvasRedo')
    saved=wall();sv.sp('save');sv.quit();sv.launch();wall('open');time.sleep(.4)
    t.ok('cards and edges survive app restart',wall()['placementData']==saved['placementData'] and len(json.loads(wall('canvasExport')['json'])['edges'])==1)
    t.ok('Canvas creates no Tab-owned WebKit view',len(wall()['builtTabs']) <= 1,wall()['builtTabs'])
    page=next(row['id'] for row in sv.sp('state')['tabs'] if row['url']==sv.BASE+'/canvas')
    sv.sp('select',id=page);time.sleep(.5)
    # A restored lazy WebKit view may still be navigating. Setting a marker in
    # its initial about:blank document would disappear when navigation finishes.
    deadline=time.monotonic()+10
    ready="location.href === " + json.dumps(sv.BASE+'/canvas') + " && document.readyState === 'complete'"
    while not sv.ev(page,ready) and time.monotonic()<deadline:time.sleep(.1)
    if not sv.ev(page,ready):raise RuntimeError('Restored source page did not finish loading')
    pane=sv.sp('state')['paneFrames'][0];x,y=pane['x'],pane['y']
    sv.ev(page,'window.nativeKeep=71;true');wall('savePage');wall('open');wall('viewport',x=0,y=0,zoom=1);time.sleep(.2)
    source=next(o['id'] for o in wall()['objects'] if o['type']=='page');savedPage=next(p for p in wall()['placementData'] if p['object']==source)
    click([x+savedPage['x']+30,y+savedPage['y']+50],clicks=2)
    state=sv.sp('state');kept=sv.ev(page,'window.nativeKeep')
    t.ok('double-click a saved page returns to its live bound tab',state['activeID']==page and kept==71,{'active':state['activeID'],'page':page,'kept':kept,'card':savedPage,'pane':pane})

finally: t.done();sv.finish()
sys.exit(1 if t.failed else 0)
