#!/usr/bin/env python3
"""PiP state/replacement/speed regression on synthetic local video only."""
import functools,json,re,subprocess,sys,tempfile,threading,time
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
sys.path.insert(0,str(Path(__file__).resolve().parent));import split_view as sv
sv.use('pip-refinements');t=sv.T();out=sv.ROOT/'artifacts/canvas-pip-refinement';out.mkdir(parents=True,exist_ok=True)
def wait(check):
    until=time.monotonic()+8
    while time.monotonic()<until:
        if check():return True
        time.sleep(.1)
    return False
def floating(action='controls',**kw):return sv.cmd({'do':'float','action':action,**kw})
with tempfile.TemporaryDirectory(prefix='locus-pip-refine-') as folder:
    root=Path(folder)
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-t','8','-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart',str(root/'sample.mp4')],check=True)
    (root/'index.html').write_text('<!doctype html><title>PiP replacement fixture</title><section id="player"><video id="main" muted autoplay playsinline src="sample.mp4" style="width:640px;height:360px"></video></section><video id="background" muted loop src="sample.mp4" style="width:40px;height:30px"></video>')
    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=folder));threading.Thread(target=server.serve_forever,daemon=True).start()
    try:
        sv.setup(sidebar=False);sv.launch();tab=sv.sp('open',url=f'http://127.0.0.1:{server.server_port}/index.html')['resultID']
        assert wait(lambda:sv.ev(tab,"!!document.querySelector('#main') && document.querySelector('#main').readyState>=3"))
        sv.ev(tab,"document.querySelector('#main').loop=true;true")
        sv.cmd({'do':'film','action':'float','path':str(out/'pip-lift'),'seconds':.2})
        assert wait(lambda:floating()['seekable'])
        def isolated(js):return sv.cmd({'do':'eval','id':tab,'js':js,'world':'search'}).get('value')
        def key(code,chars=''):floating('key',code=code,chars=chars)
        floating('rate',rate=1.5)
        t.ok('native Playback speed menu changes source rate',wait(lambda:sv.ev(tab,"document.querySelector('#main').playbackRate===1.5")))
        t.ok('speed change preserves authored mute and loop',sv.ev(tab,"document.querySelector('#main').muted && document.querySelector('#main').loop"))
        key(49,' ');assert wait(lambda:sv.ev(tab,"document.querySelector('#main').paused"))
        sv.ev(tab,"var old=document.querySelector('#main');var next=old.cloneNode();next.removeAttribute('data-office-float');next.removeAttribute('autoplay');next.id='replacement';next.loop=false;old.replaceWith(next);next.load();true")
        t.ok('paused replacement in original player gets PiP mark',wait(lambda:sv.ev(tab,"document.querySelector('#replacement').hasAttribute('data-office-float')")))
        t.ok('replacement is not forced to autoplay',sv.ev(tab,"document.querySelector('#replacement').paused"))
        isolated("Object.defineProperty(document.querySelector('#replacement'),'readyState',{value:0,configurable:true});true")
        t.ok('loading source has Loading rather than Live label',wait(lambda:floating()['time']=='Loading…'))
        isolated("delete document.querySelector('#replacement').readyState;true")
        key(49,' ');assert wait(lambda:sv.ev(tab,"!document.querySelector('#replacement').paused"))
        isolated("Object.defineProperty(document.querySelector('#replacement'),'readyState',{value:2,configurable:true});true")
        t.ok('buffering source retains its recording clock',wait(lambda:floating()['time'].startswith('Buffering… · ')))
        isolated("delete document.querySelector('#replacement').readyState;true")
        sv.ev(tab,"document.querySelector('#replacement').pause();document.querySelector('#replacement').currentTime=7.9;document.querySelector('#replacement').play();true")
        t.ok('ended player exposes Replay and an ended clock',wait(lambda:'Replay video' in floating()['labels'] and floating()['time'].startswith('Ended · ')))
        key(49,' ')
        t.ok('Replay restarts the same player',wait(lambda:sv.ev(tab,"!document.querySelector('#replacement').paused && document.querySelector('#replacement').currentTime<2")))
        isolated("Object.defineProperty(document.querySelector('#replacement'),'error',{value:{code:3},configurable:true});true")
        t.ok('playback error disables seeking',wait(lambda:floating()['time']=='Playback error' and not floating()['seekable']))
        isolated("delete document.querySelector('#replacement').error;true")
        assert wait(lambda:floating()['time']!='Playback error')
        key(49,' ');assert wait(lambda:sv.ev(tab,"document.querySelector('#replacement').paused"))
        key(46,'m');time.sleep(.2)
        assert wait(lambda:'Play video' in floating()['labels'])
        floating('picture',path=str(out/'pip-paused-native-render.png'))
        sv.ev(tab,"document.querySelector('#replacement').remove();true")
        t.ok('missing player reports unavailable and disables stepping',wait(lambda:floating()['time']=='Video unavailable' and not floating()['canSkip']))
        before=sv.ev(tab,"[document.querySelector('#background').paused,document.querySelector('#background').muted]")
        key(49,' ');key(46,'m');time.sleep(.4)
        t.ok('missing player actions never control background video',sv.ev(tab,"[document.querySelector('#background').paused,document.querySelector('#background').muted]")==before and sv.ev(tab,"!document.querySelector('#background').hasAttribute('data-office-float')"))
        sv.ev(tab,"var v=document.createElement('video');v.id='recovered';v.src='sample.mp4';v.muted=true;v.style='width:640px;height:360px';document.querySelector('#player').appendChild(v);v.load();true")
        t.ok('later replacement recovers without reloading the page',wait(lambda:sv.ev(tab,"document.querySelector('#recovered').hasAttribute('data-office-float')")))
        other=sv.sp('open',url=f'http://127.0.0.1:{server.server_port}/other')['resultID']
        key(53)
        t.ok('Close retains current browser tab',wait(lambda:sv.sp('state')['activeID']==other and not sv.ev(tab,"document.documentElement.classList.contains('office-floating')")))
        t.ok('landing stops recovery watch and removes mark',wait(lambda:isolated("window.__officeFloatWatch===null && !document.querySelector('[data-office-float]')")))
    finally:sv.finish();server.shutdown();t.done()
sys.exit(1 if t.failed else 0)
