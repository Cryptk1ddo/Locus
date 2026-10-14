#!/usr/bin/env python3
"""Portable, PNG, PDF and selection exports from a native disposable Canvas."""
import json,re,sys,tempfile,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import split_view as sv
sv.use('canvas-exports');t=sv.T();out=sv.ROOT/'artifacts/color-export-refinement';out.mkdir(parents=True,exist_ok=True)
def wall(action='state',**kw):return sv.cmd({'do':'wall','action':action,**kw})
def export(format,path,**kw):return wall('canvasExportFile',format=format,path=str(path),**kw)
try:
    with tempfile.TemporaryDirectory(prefix='locus-export-ui-') as folder:
        root=Path(folder);source=root/'Granted.md';source.write_text('# Granted source\n\nPortable note content\n')
        sv.setup(sidebar=False);sv.launch();sv.page('export-workflow');pane=sv.sp('state')['paneFrames'][0];x,y=pane['x'],pane['y']
        doc={'nodes':[{'id':'a','type':'text','x':40,'y':60,'width':300,'height':220,'text':'# Research\n\n**Canvas export**\n- [x] Preserve objects\n- [ ] Share with the team','color':'4'},{'id':'b','type':'text','x':440,'y':60,'width':300,'height':220,'text':'# Findings\n\nPortable files remain local.\nLive pages export as saved previews or links.','color':'2'},{'id':'missing','type':'file','x':40,'y':340,'width':300,'height':200,'file':'Unresolved.pdf','subpath':'#Section'}],'edges':[{'id':'relation','fromNode':'a','toNode':'b','fromSide':'right','toSide':'left','label':'Supports'}]}
        wall('canvasImport',json=json.dumps(doc));wall('canvasFileFixture',path=str(source));state=wall();file=state['objects'][-1]['id'];wall('move',id=file,x=440,y=340)
        wall('open');wall('viewport',x=20,y=20,zoom=1);time.sleep(.4);before=wall();tabState=sv.cmd({'do':'tabs'})
        folder=root/'Portable';result=export('portable',folder)
        t.ok('portable export reports unresolved file instead of claiming a grant',result.get('unresolved')==1,result)
        data=json.loads((folder/'Wall.canvas').read_text());manifest=json.loads((folder/'manifest.json').read_text())
        t.ok('portable file paths resolve within the new export',any(n.get('file')=='assets/1.md' for n in data['nodes']) and (folder/'assets/1.md').read_text()==source.read_text())
        t.ok('unresolved subpath and contained connections survive',any(n.get('subpath')=='#Section' for n in data['nodes']) and len(data['edges'])==1 and manifest['unresolved'][0]['reference']=='Unresolved.pdf')
        rejected=False
        try:export('portable',folder)
        except RuntimeError:rejected=True
        t.ok('existing export folder is protected',rejected and (folder/'Wall.canvas').exists())
        png=out/'canvas-overview.png';pdf=out/'canvas-overview.pdf'
        t.ok('native PNG overview exports',export('png',png).get('exported') and png.read_bytes().startswith(b'\x89PNG'))
        t.ok('native PDF overview exports',export('pdf',pdf).get('exported') and pdf.read_bytes().startswith(b'%PDF'))
        sv.sp('mouse',points=[[x+110,y+160],[x+110,y+160]],to='view');time.sleep(.2)
        selected=wall('canvasState')['selected'];selection=root/'Selection.canvas';r=export('json',selection,selection=True)
        t.ok('selection export contains only selected cards and valid edges',r.get('exported') and len(selected)==1 and len(json.loads(selection.read_text())['nodes'])==1 and not json.loads(selection.read_text())['edges'],selected)
        t.ok('exports leave Canvas objects and browser tabs unchanged',wall()['revision']==before['revision'] and wall()['objects']==before['objects'] and sv.cmd({'do':'tabs'})==tabState)
        # Export is static: no source is saved and no user profile is opened.
        t.ok('export reads committed source without rewriting it',source.read_text()=='# Granted source\n\nPortable note content\n')
        export('portable',out/'portable-example') if not (out/'portable-example').exists() else None
finally:t.done();sv.finish()
sys.exit(1 if t.failed else 0)
