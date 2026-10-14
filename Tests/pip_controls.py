#!/usr/bin/env python3
"""Native PiP controls on generated local media, with no remote page or user session."""
import functools,json,subprocess,sys,tempfile,threading,time
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
sys.path.insert(0,str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('pip-controls');t=sv.T();out=sv.ROOT/'artifacts/refinement'
def wait(check):
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        if check():return True
        time.sleep(.1)
    return False
with tempfile.TemporaryDirectory(prefix='locus-pip-') as directory:
    root=Path(directory)
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-t','30','-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart',str(root/'sample.mp4')],check=True)
    (root/'index.html').write_text('<!doctype html><title>Local PiP sample</title><video muted autoplay loop playsinline src="sample.mp4" style="width:640px;height:360px"></video>')
    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=directory));threading.Thread(target=server.serve_forever,daemon=True).start()
    try:
        sv.setup(sidebar=False);sv.launch();tab=sv.sp('open',url=f'http://127.0.0.1:{server.server_port}/index.html')['resultID']
        assert wait(lambda:sv.ev(tab,"!!document.querySelector('video') && document.querySelector('video').readyState >= 3"))
        sv.cmd({'do':'film','action':'float','path':str(out/'pip-lift'),'seconds':.2})
        assert wait(lambda:sv.cmd({'do':'float','action':'controls'})['seekable'])
        controls=sv.cmd({'do':'float','action':'controls'})
        t.ok('native PiP offers seek and accessible playback labels',controls['seekable'] and 'Pause video' in controls['labels'] and 'Return to video tab' in controls['labels'],controls)
        def key(code,chars=''):sv.cmd({'do':'float','action':'key','code':code,'chars':chars});time.sleep(.25)
        key(49,' ');t.ok('Space pauses the same live video',wait(lambda:sv.ev(tab,"document.querySelector('video').paused")))
        sv.cmd({'do':'float','action':'seek','fraction':.5});t.ok('timeline scrubs to halfway and updates its clock',wait(lambda:abs(sv.ev(tab,"document.querySelector('video').currentTime")-15)<.5 and sv.cmd({'do':'float','action':'controls'})['time'].startswith('0:15')))
        sv.cmd({'do':'float','action':'picture','path':str(out/'pip-native-render.png')})
        key(123);t.ok('Left seeks back without leaving the media range',wait(lambda:sv.ev(tab,"document.querySelector('video').currentTime")<.5))
        key(46,'m');t.ok('M unmutes the source video',wait(lambda:sv.ev(tab,"!document.querySelector('video').muted")))
        key(46,'m');t.ok('M toggles mute back',wait(lambda:sv.ev(tab,"document.querySelector('video').muted")))
        def isolated(js):return sv.cmd({'do':'eval','id':tab,'js':js,'world':'search'}).get('value')
        isolated("Object.defineProperty(document.querySelector('video'),'duration',{value:Infinity,configurable:true});true")
        t.ok('live DVR shows Live with no finite scrubber',wait(lambda:not sv.cmd({'do':'float','action':'controls'})['seekable'] and sv.cmd({'do':'float','action':'controls'})['time']=='Live'))
        key(124);t.ok('live DVR retains range-bounded stepping',wait(lambda:abs(sv.ev(tab,"document.querySelector('video').currentTime")-15)<.5))
        isolated("Object.defineProperty(document.querySelector('video'),'seekable',{value:{length:0},configurable:true});true")
        assert wait(lambda:not sv.cmd({'do':'float','action':'controls'})['canSkip'])
        before=sv.ev(tab,"document.querySelector('video').currentTime");key(123)
        t.ok('unseekable live media ignores stepping',sv.ev(tab,"document.querySelector('video').currentTime")==before)
        isolated("delete document.querySelector('video').duration;delete document.querySelector('video').seekable;true")
        key(36);t.ok('Return closes PiP and selects its source tab',wait(lambda:sv.sp('state')['activeID']==tab and not sv.ev(tab,"document.documentElement.classList.contains('office-floating')")))
    finally:sv.finish();server.shutdown();t.done()
sys.exit(1 if t.failed else 0)
