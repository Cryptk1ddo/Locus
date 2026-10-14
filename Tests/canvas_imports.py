#!/usr/bin/env python3
"""Portable folder imports through native test-only command and live previews."""
import base64,json,sys,tempfile,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import split_view as sv
sv.use('canvas-imports');t=sv.T()
def wall(action='state',**kw):return sv.cmd({'do':'wall','action':action,**kw})
try:
    with tempfile.TemporaryDirectory(prefix='locus-import-ui-') as directory:
        root=Path(directory);assets=root/'assets';assets.mkdir();note=assets/'note.md';note.write_text('# Portable note\n\nImported source stays unchanged.\n')
        # Self-contained synthetic one-pixel PNG.
        (assets/'background.png').write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))
        (root/'symlink.md').symlink_to(note)
        doc={'nodes':[{'id':'note','type':'file','file':'assets/note.md','subpath':'#Portable note','x':0,'y':0,'width':320,'height':240},{'id':'group','type':'group','label':'Imported group','background':'assets/background.png','backgroundStyle':'cover','x':-40,'y':-50,'width':450,'height':380},{'id':'missing','type':'file','file':'../outside.md','x':480,'y':0,'width':320,'height':240},{'id':'symlink','type':'file','file':'symlink.md','x':480,'y':300,'width':320,'height':240}], 'edges':[{'id':'e','fromNode':'note','toNode':'missing','label':'Reference'}]}
        (root/'Wall.canvas').write_text(json.dumps(doc));sv.setup(sidebar=False);sv.launch();sv.page('portable-import');tabs=sv.sp('state')['tabs'];before=wall()
        result=wall('canvasImportFolder',path=str(root));after=wall()
        t.ok('portable import resolves local note and group background',result['imported']==4 and result['granted']==2 and result['unresolved']==2,result)
        reexport=root/'Reexport';r=wall('canvasExportFile',format='portable',path=str(reexport))
        t.ok('only contained regular file references receive bookmarks',r['unresolved']==2 and json.loads((reexport/'manifest.json').read_text())['assets']==2)
        wall('open');wall('viewport',x=100,y=130,zoom=.75);time.sleep(.4)
        obj=next(o['id'] for o in after['objects'] if o['title']=='note.md')
        card=next(p['id'] for p in after['placementData'] if p['object']==obj)
        wall('canvasEdit',id=card);sv.cmd({'do':'press','code':53,'chars':''});time.sleep(.4)
        wall('picture',path=str(sv.ROOT/'artifacts/canvas-pip-refinement/canvas-import-native-render.png'))
        info=wall('canvasContentInfo')
        t.ok('imported note renders live native Markdown',any('Imported source stays unchanged.' in row.get('text','') for row in info.get('previews',[])),info)
        wall('canvasUndo');t.ok('single undo removes whole import',wall()['objects']==before['objects'])
        wall('canvasRedo');t.ok('redo restores granted files and connections',len(wall()['objects'])==4 and len(json.loads(wall('canvasExport')['json'])['edges'])==1)
        exported=json.loads(wall('canvasExport')['json']);t.ok('subpath and group background style survive exchange',any(n.get('subpath')=='#Portable note' for n in exported['nodes']) and any(n.get('backgroundStyle')=='cover' for n in exported['nodes']))
        t.ok('import never enables vault autosave or rewrites sources',not wall('canvasVault')['connected'] and note.read_text()=='# Portable note\n\nImported source stays unchanged.\n')
        t.ok('import does not create source browser tabs',len(sv.sp('state')['tabs'])==len(tabs)+1) # explicit Wall opening adds its own tab
        saved=wall();(root/'Wall.canvas').write_text('{"nodes":[{"type":"file"}]}');rejected=False
        try:wall('canvasImportFolder',path=str(root))
        except RuntimeError:rejected=True
        t.ok('invalid portable import leaves current Wall unchanged',rejected and wall()['objects']==saved['objects'])
finally:sv.finish();t.done()
sys.exit(1 if t.failed else 0)
