#!/usr/bin/env python3
"""Portable link previews persist as owned native inspiration assets."""
import json,struct,sys,tempfile,time,zlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import split_view as sv
sv.use('canvas-preview-roundtrip');t=sv.T();out=sv.ROOT/'artifacts/preview-pip-polish';out.mkdir(parents=True,exist_ok=True)
def wall(action='state',**kw):return sv.cmd({'do':'wall','action':action,**kw})
def previewPNG():
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    width,height=520,300
    def pixel(x,y):
        if x<60 or y<34:return bytes((30,36,56))
        if 90<=x<470 and 65<=y<145:return bytes((40+int(x/10),130+int(y/5),180))
        if 90<=x<260 and 180<=y<265:return bytes((130,110,190))
        if 285<=x<470 and 180<=y<265:return bytes((75,150,120))
        return bytes((46,54,76))
    rows=b''.join(b'\0'+b''.join(pixel(x,y) for x in range(width)) for y in range(height))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b'')
png=previewPNG()

try:
    with tempfile.TemporaryDirectory(prefix='locus-preview-roundtrip-') as folder:
        root=Path(folder);(root/'preview.png').write_bytes(png)
        (root/'Wall.canvas').write_text(json.dumps({'nodes':[{'id':'reference','type':'link','url':sv.BASE+'/portable-inspiration','x':30,'y':30,'width':320,'height':240}]}))
        (root/'manifest.json').write_text(json.dumps({'version':1,'previews':[{'node':'reference','file':'preview.png','title':'Portable visual reference'}]}))
        sv.setup(sidebar=False);sv.launch();sv.page('preview-owner');built=wall()['builtTabs'];result=wall('canvasImportFolder',path=str(root));state=wall()
        t.ok('portable preview creates an inspiration object with its title',result['previews']==1 and state['objects'][0]['type']=='inspiration' and state['objects'][0]['title']=='Portable visual reference',result)
        t.ok('preview import opens no destination browser page',wall()['builtTabs']==built)
        (root/'preview.png').unlink();wall('open');wall('viewport',x=60,y=60,zoom=1);time.sleep(.5)
        restored=root/'Restored';r=wall('canvasExportFile',format='portable',path=str(restored));manifest=json.loads((restored/'manifest.json').read_text());path=manifest['previews'][0]['file']
        t.ok('preview is owned after original image removal',r['unresolved']==0 and (restored/path).read_bytes()==png)
        wall('picture',path=str(out/'canvas-saved-preview-native-render.png'))
        wall('canvasUndo');t.ok('one undo removes preview object and placement',not wall()['objects'] and wall()['placements']==0)
        wall('canvasRedo');t.ok('redo restores preview ownership',wall()['objects'][0]['type']=='inspiration' and wall('canvasExportFile',format='portable',path=str(root/'Redo'))['unresolved']==0)
        sv.quit();sv.launch();wall('open');time.sleep(.3)
        t.ok('restart restores preview image and original link',wall('canvasExportFile',format='portable',path=str(root/'Restart'))['unresolved']==0 and json.loads(wall('canvasExport')['json'])['nodes'][0]['url']==sv.BASE+'/portable-inspiration')
        (root/'manifest.json').write_text(json.dumps({'version':1,'previews':[{'node':'reference','file':'../escape.png'}]}))
        result=wall('canvasImportFolder',path=str(root));t.ok('escaping preview stays an unresolved plain link',result['previews']==0 and result['unresolved']==1 and wall()['objects'][-1]['type']=='web')
        (root/'preview.png').write_bytes(png);(root/'manifest.json').write_text(json.dumps({'version':1,'previews':[{'node':'reference','file':'preview.png'},{'node':'reference','file':'preview.png'}]}))
        result=wall('canvasImportFolder',path=str(root));t.ok('ambiguous preview mapping stays a plain link',result['previews']==0 and result['unresolved']==1)
finally:sv.finish();t.done()
sys.exit(1 if t.failed else 0)
