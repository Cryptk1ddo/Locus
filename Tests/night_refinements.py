#!/usr/bin/env python3
"""Native modern-color, state, motion and SVG chart checks, in an isolated profile."""
import functools,json,subprocess,sys,tempfile,threading,time
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
sys.path.insert(0,str(Path(__file__).resolve().parent));import split_view as sv
sv.use('night-refinements');t=sv.T();out=sv.ROOT/'artifacts/color-export-refinement';out.mkdir(parents=True,exist_ok=True)
def wait(check,seconds=6):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        if check():return True
        time.sleep(.12)
    return check()
def ev(js):return sv.ev(tab,js)
def css(selector,property):return ev(f'getComputedStyle(document.querySelector({json.dumps(selector)})).getPropertyValue({json.dumps(property)})')
def night(**kw):return sv.cmd({'do':'night','id':tab,**kw})
html='''<!doctype html><meta charset="utf-8"><title>Night Colors · interactive research</title><style>
body{background:#fafafa;color:#111;font:16px -apple-system;margin:30px}main{max-width:900px;margin:auto}h1{font-size:30px}button{background:#2563eb;color:white;border:0;padding:18px;margin:10px}#state:hover{background:#9333ea}#state:focus{background:#d97706;outline:3px solid lab(55% 65 30)}#state:focus::before{color:lch(50% 70 40)}#state::before{content:'● ';color:#16a34a}#transition{transition:background-color .2s,transform .2s;background:#fff;color:#111}#transition:focus,#transition.on{background:#e6b0c0;transform:translateX(20px)}
#complex{padding:24px;margin:20px 0;color:lab(30% 20 -30);background-image:linear-gradient(90deg,color-mix(in oklch,orange 70%,red),lch(60% 50 300)),url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E");box-shadow:0 4px 12px color-mix(in srgb,black 20%,transparent)}
#animated{padding:20px;background:#fff;color:#111}svg{display:block;border:1px solid #ddd;margin:20px 0}#chart{background:white}.axis path,.grid line{fill:none;stroke:#333}.grid line{stroke:#ddd}text{fill:#111}#legend{fill:#dc2626}
</style><main><h1>Research colors, interaction and chart semantics</h1><p>Data colors stay consistent with their legend. Motion remains authored by the page.</p><button id="state">Focus to inspect</button><button id="transition">Native color transition</button><section id="complex">Lab, LCH, nested color-mix and a retained image layer</section><div id="animated">Authored motion</div><svg id="chart" role="img" aria-label="Research chart" width="850" height="240" viewBox="0 0 850 240"><g class="grid"><line id="grid" x1="40" y1="60" x2="800" y2="60"/></g><g class="axis"><path id="axis" d="M40 20V200H800"/><text id="label" x="10" y="225">0</text></g><rect id="series" fill="#dc2626" x="60" y="60" width="100" height="140"/><rect fill="#2563eb" x="180" y="90" width="100" height="110"/><text id="legend" fill="#dc2626" x="340" y="90">Red series</text><text x="340" y="130">Neutral chart labels</text></svg></main>'''
with tempfile.TemporaryDirectory(prefix='locus-night-motion-') as directory:
    (Path(directory)/'index.html').write_text(html)
    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self,*a):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=directory));threading.Thread(target=server.serve_forever,daemon=True).start()
    try:
        sv.setup(sidebar=False);subprocess.run(['defaults','write',sv.SUITE,'look','-string','dark'],check=True);sv.launch()
        tab=sv.sp('open',url=f'http://localhost:{server.server_port}/index.html')['resultID'];assert wait(lambda:ev("!!document.querySelector('#chart') && document.readyState==='complete'"))
        original={key:css(*values) for key,values in {'complex':('#complex','background-image'),'axis':('#axis','stroke'),'grid':('#grid','stroke'),'label':('#label','fill'),'series':('#series','fill'),'legend':('#legend','fill')}.items()}
        ev("window.motion=document.querySelector('#animated').animate([{backgroundColor:'#ffffff',transform:'translateX(0px)'},{backgroundColor:'#e6b0c0',transform:'translateX(12px)'}],{duration:1200,iterations:Infinity,direction:'alternate'});window.framesBefore=JSON.stringify(motion.effect.getKeyframes());true")
        night(enabled=True);assert wait(lambda:night()['status']['state']=='adapted')
        t.ok('Lab foreground and nested modern gradient colors adapt',css('#complex','background-image')!=original['complex'] and css('#complex','color').startswith('rgb'))
        t.ok('gradient syntax and URL image layer remain present','linear-gradient' in css('#complex','background-image') and 'data:image/svg+xml' in css('#complex','background-image'))
        t.ok('neutral chart axes and grid adapt',css('#axis','stroke')!=original['axis'] and css('#grid','stroke')!=original['grid'])
        t.ok('chart labels adapt while series and legend colors stay exact',css('#label','fill')!=original['label'] and css('#series','fill')==original['series'] and css('#legend','fill')==original['legend'],{'original':original,'label':css('#label','fill'),'legend':css('#legend','fill'),'series':css('#series','fill')})
        t.ok('chart recognized without becoming an artwork-wide inversion',night()['status'].get('charts')==1 and css('#chart','filter')=='none' and css('#chart','background-color')!='rgb(255, 255, 255)')
        ev('motion.currentTime=600;true')
        t.ok('authored keyframes and timing remain intact',ev('JSON.stringify(motion.effect.getKeyframes())===framesBefore') and ev('motion.effect.getTiming().duration')==1200 and night()['status'].get('preservedMotion',0)>0)
        t.ok('explicit animation clock keeps authored motion paint and transform',css('#animated','transform')=='matrix(1, 0, 0, 1, 6, 0)' and css('#animated','background-color')!='rgb(28, 28, 28)')
        revision=night()['status']['revision'];ev("document.querySelector('#state').dispatchEvent(new PointerEvent('pointerover',{bubbles:true}));true")
        t.ok('pointer state event triggers resampling',wait(lambda:night()['status']['revision']>revision))
        revision=night()['status']['revision'];ev("document.querySelector('#state').focus();true")
        t.ok('focus refreshes page palette without DOM mutations',wait(lambda:night()['status']['revision']>revision) and ev("document.activeElement.id")=='state')
        t.ok('focus outline adapts and retains its geometry',css('#state','outline-width')=='3px' and css('#state','outline-color').startswith('rgb'))
        t.ok('color transitions keep source timing and target paint',all(part.strip()=='0.2s' for part in css('#transition','transition-duration').split(',')) and css('#transition','background-color')=='rgb(255, 255, 255)',{'duration':css('#transition','transition-duration'),'background':css('#transition','background-color'),'retained':sv.cmd({'do':'eval','id':tab,'world':'search','js':"Array.from(__locusNightCSS.transitions(getComputedStyle(document.querySelector('#transition'))))"})})
        ev("const e=document.querySelector('#transition');e.classList.add('on');getComputedStyle(e).backgroundColor;e.getAnimations().forEach(a=>a.currentTime=250);true");time.sleep(.1)
        t.ok('authored color and transform transitions reach their targets',css('#transition','background-color')=='rgb(230, 176, 192)' and css('#transition','transform')=='matrix(1, 0, 0, 1, 20, 0)',{'bg':css('#transition','background-color'),'transform':css('#transition','transform'),'class':ev("document.querySelector('#transition').className"),'animations':ev("document.querySelector('#transition').getAnimations().map(a=>({time:a.currentTime,frames:a.effect.getKeyframes()}))")})
        ev('motion.cancel();true');t.ok('ending motion restores ordinary adaptation',wait(lambda:css('#animated','background-color')!='rgb(255, 255, 255)'))
        sv.cmd({'do':'picture','path':str(out/'night-chart-native-render.png'),'page':False})
        ev("document.querySelector('#series').setAttribute('fill','#16a34a');true")
        t.ok('dynamic chart data color changes remain authored',wait(lambda:css('#series','fill')=='rgb(22, 163, 74)'))
        night(enabled=False)
        t.ok('disable restores complex CSS and chart scaffolding',wait(lambda:css('#complex','background-image')==original['complex']) and css('#axis','stroke')==original['axis'] and css('#label','fill')==original['label'])
        rev=night()['status']['revision'];time.sleep(.65);t.ok('disabled extension releases active motion polling',night()['status']['revision']==rev)
    finally:t.done();sv.finish();server.shutdown()
sys.exit(1 if t.failed else 0)
