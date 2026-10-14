#!/usr/bin/env python3
"""Repeatable local native Canvas measurements; no user session/network data."""
import argparse,hashlib,json,platform,plistlib,sys,tempfile,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import split_view as sv
args=argparse.ArgumentParser();args.add_argument('--output',required=True);args=args.parse_args();sv.use('browser-performance')
def wall(action='state',**kw):return sv.cmd({'do':'wall','action':action,**kw})
try:
    with tempfile.TemporaryDirectory(prefix='locus-performance-') as directory:
        root=Path(directory);notes=[]
        for i in range(12):
            source=root/f'Note-{i}.md';source.write_text(f'# Reference {i}\n\n'+('A local research note with **emphasis**, spacing and design findings.\n'*90));notes.append(source)
        sv.setup(sidebar=False);sv.launch();sv.page('performance')
        for i,source in enumerate(notes):
            wall('canvasFileFixture',path=str(source));obj=wall()['objects'][-1]['id'];wall('move',id=obj,x=(i%4)*230,y=(i//4)*190)
        wall('canvasImport',json=json.dumps({'nodes':[{'id':f'off-{i}','type':'text','text':f'Offscreen {i}','x':10000+(i%10)*260,'y':10000+(i//10)*140,'width':240,'height':120} for i in range(500)],'edges':[{'id':f'e-{i}','fromNode':f'off-{i}','toNode':f'off-{i+1}'} for i in range(499)]}))
        for i in range(600): (root/f'Indexed-{i}.md').write_text('Small indexed fixture\n')
        started=time.perf_counter();state=wall('canvasVault',path=str(root));scanMs=(time.perf_counter()-started)*1000
        wall('open');wall('viewport',x=30,y=40,zoom=.9);time.sleep(.5)
        obj=wall()['objects'][0]['id'];card=next(p['id'] for p in wall()['placementData'] if p['object']==obj)
        wall('canvasEdit',id=card);sv.cmd({'do':'press','code':53,'chars':''});time.sleep(.3)
        warm=wall('canvasPerformance',frames=10)
        runs=[wall('canvasPerformance',frames=40) for _ in range(3)]
        result={'dataset':{'notes':12,'offscreenCards':500,'offscreenEdges':499,'vaultFiles':len(state['entries']),'framesPerRun':40,'runs':3,'render':'AppKit native cacheDisplay; generated Markdown only'},'initialVaultConnectMs':scanMs,'warmup':warm,'runs':runs,'tabs':len(sv.sp('state')['tabs']),'builtWebViews':len(wall()['builtTabs'])}
        app=Path(sv.APP);info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
        result['binary']={'app':str(app),'build':info['CFBundleVersion'],'sha256':hashlib.sha256((app/'Contents/MacOS/Search').read_bytes()).hexdigest(),'bytes':(app/'Contents/MacOS/Search').stat().st_size,'architecture':platform.machine(),'os':platform.mac_ver()[0]}
        Path(args.output).parent.mkdir(parents=True,exist_ok=True);Path(args.output).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
finally:sv.finish()
