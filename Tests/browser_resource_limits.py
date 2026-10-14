#!/usr/bin/env python3
"""Native file-event correctness and idle-work checks with synthetic resources."""
import sys,tempfile,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import split_view as sv
sv.use('browser-resource-limits');t=sv.T()
def wall(action='state',**kw):return sv.cmd({'do':'wall','action':action,**kw})
def wait(check,seconds=8):
    until=time.monotonic()+seconds
    while time.monotonic()<until:
        if check():return True
        time.sleep(.12)
    return False
try:
    with tempfile.TemporaryDirectory(prefix='locus-idle-') as directory:
        root=Path(directory);vault=root/'Vault';vault.mkdir();source=root/'outside.md';source.write_text('# Original\nOutside content\n');part=vault/'Part.md';part.write_text('# Part\nInitial vault content\n')
        sv.setup(sidebar=False);sv.launch();sv.page('resources');wall('canvasFileFixture',path=str(source));state=wall();obj=state['objects'][-1]['id'];card=state['placementData'][-1]['id']
        wall('open');wall('viewport',x=40,y=50,zoom=1);wall('canvasEdit',id=card);sv.cmd({'do':'press','code':53,'chars':''});time.sleep(.3)
        def preview():return next((p['text'] for p in wall('canvasContentInfo')['previews'] if p['object']==obj),'')
        t.ok('granted outside file has a readable native preview','Outside content' in preview())
        wall('canvasPerformance',frames=10)
        cached=wall('canvasPerformance',frames=10)['counters']
        t.ok('preview reads do not feed back into file invalidation',cached.get('request:fileEvent',0)==0 and cached['fileProbes']==0,cached)
        source.write_text('# Original\nChanged outside without panning\n')
        t.ok('single-file native event refreshes a stable viewport',wait(lambda:'Changed outside' in preview()))
        replacement=root/'replacement.md';replacement.write_text('# Original\nAtomic replacement\n');replacement.replace(source)
        t.ok('atomic file replacement reattaches observation',wait(lambda:'Atomic replacement' in preview()))
        wall('viewport',x=-10000,y=-10000,zoom=1);time.sleep(.3)
        source.write_text('# Original\nChanged while offscreen\n');time.sleep(.3)
        wall('viewport',x=40,y=50,zoom=1)
        t.ok('returning to an unobserved card refreshes its cached content',wait(lambda:'Changed while offscreen' in preview()))
        wall('canvasVault',path=str(vault));assert wait(lambda:wall('canvasVaultMetrics')['watching'] and not wall('canvasVaultMetrics')['scanning'])
        before=wall('canvasVaultMetrics')['asyncScans'];time.sleep(4.5);after=wall('canvasVaultMetrics')['asyncScans']
        t.ok('idle connected Wall performs no repeating index scans',before==after,{'before':before,'after':after})
        wall('canvasImport',json='{"nodes":[{"id":"embed","type":"text","text":"![[Part]]","x":500,"y":0,"width":400,"height":300}]}')
        state=wall();note=state['objects'][-1]['id'];ncard=state['placementData'][-1]['id'];wall('canvasEdit',id=ncard);sv.cmd({'do':'press','code':53,'chars':''});time.sleep(.3)
        def embedded():return next((p['text'] for p in wall('canvasContentInfo')['previews'] if p['object']==note),'')
        assert wait(lambda:'Initial vault content' in embedded())
        part.write_text('# Part\nEvent-driven nested note\n')
        t.ok('recursive native event updates rich vault content',wait(lambda:'Event-driven nested note' in embedded()))
        wall('close');t.ok('leaving Wall stops its shared vault stream',wait(lambda:wall('canvasVaultMetrics')['clients']==0 and not wall('canvasVaultMetrics')['watching']))
        tab=sv.page('night-idle');assert wait(lambda:sv.ev(tab,"document.readyState==='complete'"))
        def night(**kw):return sv.cmd({'do':'night','id':tab,**kw})
        night(enabled=True,mode='always',appearance='dark');assert wait(lambda:night()['status']['state']=='adapted')
        def isolated(js):return sv.cmd({'do':'eval','id':tab,'js':js,'world':'search'}).get('value')
        isolated("Object.defineProperty(document,'hidden',{value:true,configurable:true});dispatchEvent(new Event('visibilitychange'));true")
        t.ok('Night Colors has no animation polling while hidden',wait(lambda:night()['status']['motionPolling']==False))
        isolated("Object.defineProperty(document,'hidden',{value:false,configurable:true});dispatchEvent(new Event('visibilitychange'));true")
        t.ok('Night Colors resumes polling for a visible adapted page',wait(lambda:night()['status']['motionPolling']==True))
        night(enabled=False);t.ok('disabling Night Colors releases polling',wait(lambda:night()['status']['motionPolling']==False))
finally:sv.finish();t.done()
sys.exit(1 if t.failed else 0)
