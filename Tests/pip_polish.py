#!/usr/bin/env python3
"""Native portrait/square PiP sizing and captions when controls are hidden."""
import functools,subprocess,sys,tempfile,threading,time
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
sys.path.insert(0,str(Path(__file__).resolve().parent));import split_view as sv
sv.use('pip-polish');t=sv.T();out=sv.ROOT/'artifacts/preview-pip-polish';out.mkdir(parents=True,exist_ok=True)
def wait(check):
    until=time.monotonic()+8
    while time.monotonic()<until:
        if check():return True
        time.sleep(.1)
    return False
def floating(action='controls',**kw):return sv.cmd({'do':'float','action':action,**kw})
with tempfile.TemporaryDirectory(prefix='locus-pip-shape-') as directory:
    root=Path(directory)
    for name,size in [('portrait','360x640'),('square','480x480'),('landscape','640x360')]:
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size='+size+':rate=24','-t','8','-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart',str(root/(name+'.mp4'))],check=True)
    (root/'index.html').write_text('<!doctype html><title>Portrait PiP</title><section><video muted autoplay loop playsinline src="landscape.mp4" style="width:360px;height:640px"></video></section>')
    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=directory));threading.Thread(target=server.serve_forever,daemon=True).start()
    try:
        sv.setup(sidebar=False)
        subprocess.run(['defaults','write',sv.SUITE,'float.frame','-string','{{100, 100}, {300, 540}}'],check=True)
        sv.launch();tab=sv.sp('open',url=f'http://127.0.0.1:{server.server_port}/index.html')['resultID']
        assert wait(lambda:sv.ev(tab,"!!document.querySelector('video') && document.querySelector('video').readyState>=3"))
        sv.cmd({'do':'film','action':'float','path':str(out/'portrait-lift'),'seconds':.2})
        def isolated(js):return sv.cmd({'do':'eval','id':tab,'js':js,'world':'search'}).get('value')
        def ratio():
            size=floating()['size'];return size[0]/size[1]
        t.ok('remembered portrait window adapts to landscape video',wait(lambda:abs(ratio()-640/360)<.01))
        sv.ev(tab,"document.querySelector('video').src='portrait.mp4';document.querySelector('video').play();true")
        t.ok('PiP fits actual portrait media dimensions',wait(lambda:abs(ratio()-.5625)<.01))
        t.ok('normal playback hides caption and buttons without hover',wait(lambda:floating()['statusAlpha']==0 and max(floating()['buttonAlpha'])==0))
        isolated("Object.defineProperty(document.querySelector('video'),'readyState',{value:0,configurable:true});true")
        t.ok('loading caption is visible while buttons remain hidden',wait(lambda:floating()['time']=='Loading…' and floating()['statusAlpha']==1 and max(floating()['buttonAlpha'])==0))
        floating('picture',path=str(out/'pip-portrait-loading-native-render.png'))
        isolated("Object.defineProperty(document.querySelector('video'),'readyState',{value:2,configurable:true});true")
        t.ok('buffering caption remains visible without revealing buttons',wait(lambda:floating()['time'].startswith('Buffering…') and floating()['statusAlpha']==1 and max(floating()['buttonAlpha'])==0))
        isolated("delete document.querySelector('video').readyState;true")
        t.ok('recovered playback hides status again',wait(lambda:floating()['statusAlpha']==0))
        sv.ev(tab,"document.querySelector('video').src='square.mp4';document.querySelector('video').play();true")
        t.ok('changed video metadata updates PiP to square',wait(lambda:abs(ratio()-1)<.01 and floating()['seekable']))
        floating('key',code=49,chars=' ');assert wait(lambda:sv.ev(tab,"document.querySelector('video').paused"))
        floating('pointerExit');time.sleep(.3)
        t.ok('pointer exit hides ordinary paused controls and clock',floating()['statusAlpha']==0 and max(floating()['buttonAlpha'])==0)
        isolated("Object.defineProperty(document.querySelector('video'),'error',{value:{code:3},configurable:true});true")
        t.ok('playback error stays visible after pointer exit',wait(lambda:floating()['time']=='Playback error' and floating()['statusAlpha']==1))
        isolated("delete document.querySelector('video').error;true")
        sv.ev(tab,"document.querySelector('video').remove();true")
        t.ok('missing-player caption remains visible with controls hidden',wait(lambda:floating()['time']=='Video unavailable' and floating()['statusAlpha']==1 and max(floating()['buttonAlpha'])==0))
        floating('key',code=36,chars='\r')
        t.ok('Return still restores original tab and player ownership',wait(lambda:sv.sp('state')['activeID']==tab and not sv.ev(tab,"document.documentElement.classList.contains('office-floating')")))
    finally:sv.finish();server.shutdown();t.done()
sys.exit(1 if t.failed else 0)
