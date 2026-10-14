#!/usr/bin/env python3
"""Night Colors on synthetic local pages, using a disposable profile and app copy."""
import functools,json,subprocess,sys,tempfile,threading,time
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
sys.path.insert(0,str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('night-colors');t=sv.T();out=sv.ROOT/'artifacts/night-colors'
def wait(check,seconds=6):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        if check():return True
        time.sleep(.15)
    return check()
def night(tab,**kw):return sv.cmd({'do':'night','id':tab,**kw})
def value(tab,js):return sv.ev(tab,js)
def background(tab,selector):return value(tab,f"getComputedStyle(document.querySelector({json.dumps(selector)})).backgroundColor")
def status(tab):return night(tab)['status']['state']
html='''<!doctype html><meta charset="utf-8"><title>Night Colors research fixture</title>
<style>
body{margin:0;background:#fafafa;color:#171717;font:16px -apple-system,BlinkMacSystemFont,sans-serif}main{max-width:1040px;margin:auto;padding:40px}h1{font-size:36px;color:#111;margin:8px 0 12px}h2{font-size:22px}a{color:#2563eb}.lead{color:#404040}.secondary{color:#888}.grid{display:grid;grid-template-columns:1fr 1fr;gap:22px}.card{background:white;border:1px solid #ddd;border-radius:16px;padding:24px;box-shadow:0 8px 24px rgba(0,0,0,.1)}.card::before{content:'●';color:#f59e0b}.nested{background:#f4f4f5;border:1px solid #ddd;border-radius:8px;padding:14px}button{background:#2563eb;color:#fff;border:0;border-radius:8px;padding:10px 16px;font:600 14px -apple-system}input{background:white;color:#222;border:1px solid #ccc;border-radius:6px;padding:10px}.hero{padding:20px;border-radius:12px;background:linear-gradient(90deg,#f59e0b,#dc2626);color:#111;margin:20px 0}iframe{width:100%;height:130px;border:1px solid #ddd;border-radius:8px}svg{margin-top:12px}
</style><main><h1>Research, with its colors intact</h1><p class="lead">A brand-aware night canvas, without changing typography or layout.</p><p class="secondary">Secondary context keeps its place in the hierarchy.</p><section class="hero">Warm colors belong here too.</section><section class="grid"><article class="card" id="card"><h2>Surfaces and controls</h2><p><a href="#details">A blue reference link</a> and ordinary body text.</p><div class="nested">Nested surface</div><p><input placeholder="Search notes"> <button id="button">Continue</button></p><svg id="icon" width="24" height="24" viewBox="0 0 24 24"><path fill="#2563eb" d="M2 2h20v20H2z"/></svg></article><article class="card"><h2>Original artwork</h2><svg role="img" id="art" width="300" height="80"><rect width="300" height="80" fill="#f59e0b"/></svg><p>Artwork and video receive no inversion or dimming filter.</p><video id="video" width="160" height="60"></video><div id="shadow"></div></article></section><p id="details">Colors are adapted by role, not inverted.</p><iframe id="frame" src="frame.html"></iframe></main><script>document.querySelector('#shadow').attachShadow({mode:'open'}).innerHTML='<style>button{background:#fff;color:#111;border:1px solid #ddd;padding:8px}</style><button>Shadow-root control</button>';</script>'''
with tempfile.TemporaryDirectory(prefix='locus-night-ui-') as directory:
    root=Path(directory);(root/'index.html').write_text(html);(root/'frame.html').write_text('<!doctype html><style>body{background:white;color:#111;font:16px -apple-system;padding:12px}</style><p>Frame content retains a readable relationship.</p><script>window.nightSignals=[];addEventListener(\"message\",e=>{if(e.data?.type?.startsWith(\"locus-night\"))nightSignals.push(Object.keys(e.data).sort())})</script>')
    (root/'native.html').write_text('<!doctype html><style>body{background:#202020;color:#eee;font:18px -apple-system}</style><h1>A native dark theme</h1>Retain this design.')
    (root/'cross.html').write_text('<!doctype html><style>body{background:white;color:#111}</style><p>Different-origin frame</p><script>setInterval(()=>parent.postMessage({type:"fixture-bg",color:getComputedStyle(document.body).backgroundColor},"*"),100)</script>')
    (root/'strict.html').write_text('<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src \'self\'; style-src \'self\'"><link rel="stylesheet" href="strict.css"><h1>Strict stylesheet policy</h1>')
    (root/'strict.css').write_text('body{background:white;color:#111}')
    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=directory));threading.Thread(target=server.serve_forever,daemon=True).start()
    base=f'http://localhost:{server.server_port}'
    try:
        sv.setup(sidebar=False);subprocess.run(['defaults','write',sv.SUITE,'look','-string','dark'],check=True);sv.launch()
        tab=sv.sp('open',url=base+'/index.html')['resultID'];assert wait(lambda:value(tab,"!!document.querySelector('#card') && document.readyState==='complete'"))
        original=background(tab,'body');bodyStyle=value(tab,"document.body.getAttribute('style')")
        t.ok('built-in extension is dormant by default',not night(tab)['enabled'] and original=='rgb(250, 250, 250)')
        geometry=value(tab,"(()=>{const r=document.querySelector('#card').getBoundingClientRect();return [r.x,r.y,r.width,r.height]})()")
        sv.cmd({'do':'picture','path':str(out/'01-source-native-render.png'),'page':False})
        night(tab,enabled=True);t.ok('opt-in adapts light page on exact night canvas',wait(lambda:status(tab)=='adapted') and background(tab,'body')=='rgb(28, 28, 28)',night(tab))
        t.ok('kernel and control runtime stay outside page JavaScript',not value(tab,'!!globalThis.__locusNight || !!globalThis.__locusNightMath'))
        afterGeometry=value(tab,"(()=>{const r=document.querySelector('#card').getBoundingClientRect();return [r.x,r.y,r.width,r.height]})()")
        t.ok('page layout and typography remain unchanged',geometry==afterGeometry and value(tab,"getComputedStyle(document.querySelector('h1')).fontSize")=='36px',(geometry,afterGeometry))
        contrasts=sv.cmd({'do':'eval','id':tab,'world':'search','js':"(()=>{const M=__locusNightMath,el=document.querySelector('#button'),s=getComputedStyle(el);return M.contrast(M.parse(s.color),M.parse(s.backgroundColor))})()"})['value']
        t.ok('adapted button text meets solid-background contrast',contrasts>=4.5,contrasts)
        t.ok('large artwork and video are untouched',value(tab,"getComputedStyle(document.querySelector('#art rect')).fill")=='rgb(245, 158, 11)' and value(tab,"getComputedStyle(document.querySelector('#video')).filter")=='none')
        t.ok('small SVG icon is adapted without filters',value(tab,"getComputedStyle(document.querySelector('#icon path')).fill")!='rgb(37, 99, 235)' and value(tab,"getComputedStyle(document.querySelector('#icon')).filter")=='none')
        t.ok('open shadow-root controls are adapted',value(tab,"getComputedStyle(document.querySelector('#shadow').shadowRoot.querySelector('button')).backgroundColor")!='rgb(255, 255, 255)')
        t.ok('subframe receives the built-in extension',wait(lambda:value(tab,"getComputedStyle(document.querySelector('#frame').contentDocument.body).backgroundColor")=='rgb(28, 28, 28)'))
        t.ok('frame refresh messages carry no remembered site choices',value(tab,"(()=>{const signals=document.querySelector('#frame').contentWindow.nightSignals;return signals.length>0&&signals.every(keys=>keys.join(',')==='token,type')})()"))
        t.ok('pseudo-element color retains hue while adapting luminance',value(tab,"getComputedStyle(document.querySelector('#card'),'::before').color")!='rgb(245, 158, 11)')
        sv.cmd({'do':'picture','path':str(out/'02-night-native-render.png'),'page':False})
        sv.cmd({'do':'ui','settings':True,'settingsPage':'extensions'});time.sleep(.8)
        sv.cmd({'do':'picture','path':str(out/'03-settings-native-render.png'),'page':False});sv.cmd({'do':'ui','settings':False})
        value(tab,"const p=document.createElement('p');p.id='dynamic';p.style.cssText='background:white;color:#111';p.textContent='Dynamic content';document.body.appendChild(p);true")
        t.ok('dynamic inserted elements are adapted',wait(lambda:background(tab,'#dynamic')!='rgb(255, 255, 255)'))
        value(tab,"document.querySelector('#dynamic').style.color='rgb(0, 100, 0)';true");time.sleep(.3)
        night(tab,mode='off');t.ok('site Off restores original page and subframe styling',wait(lambda:background(tab,'body')==original) and wait(lambda:value(tab,"getComputedStyle(document.querySelector('#frame').contentDocument.body).backgroundColor")=='rgb(255, 255, 255)'))
        t.ok('restoration preserves author changes and removes own markers',value(tab,"getComputedStyle(document.querySelector('#dynamic')).color")=='rgb(0, 100, 0)' and value(tab,"document.body.getAttribute('style')")==bodyStyle and value(tab,"document.querySelectorAll('[data-locus-night-style]').length")==0)
        crossURL=f'http://127.0.0.1:{server.server_port}/cross.html'
        value(tab,"addEventListener('message',e=>{if(e.origin==="+json.dumps(f'http://127.0.0.1:{server.server_port}')+"&&e.data?.type==='fixture-bg')window.crossBG=e.data.color});const cross=document.createElement('iframe');cross.src="+json.dumps(crossURL)+";document.body.appendChild(cross);true")
        t.ok('cross-origin frame resolves its own mode instead of parent Off',wait(lambda:value(tab,'window.crossBG')=='rgb(28, 28, 28)'))
        cross=sv.sp('open',url=crossURL)['resultID'];assert wait(lambda:value(cross,"location.pathname==='/cross.html' && document.readyState==='complete'"))
        night(cross,mode='off');t.ok('cross-origin site Off refreshes its embedded frame',wait(lambda:value(tab,'window.crossBG')=='rgb(255, 255, 255)') and background(tab,'body')==original)
        night(cross,mode='automatic');t.ok('cross-origin frame returns to its own Automatic mode',wait(lambda:value(tab,'window.crossBG')=='rgb(28, 28, 28)'))
        native=sv.sp('open',url=base+'/native.html')['resultID'];assert wait(lambda:value(native,"location.pathname==='/native.html' && document.readyState==='complete'"))
        t.ok('site Off applies to later navigation',status(native)=='disabled' and background(native,'body')=='rgb(32, 32, 32)')
        night(native,mode='automatic');t.ok('automatic retains existing native dark theme',wait(lambda:status(native)=='native-dark') and background(native,'body')=='rgb(32, 32, 32)')
        night(native,mode='always');t.ok('Always adapt can normalize a native dark site',wait(lambda:background(native,'body')=='rgb(28, 28, 28)'))
        sv.cmd({'do':'eval','id':native,'world':'search','js':"window.webkit.messageHandlers.locusNightPolicy.postMessage({host:'spoof.invalid',mode:'off',enabled:false}).then(p=>globalThis.__nightProof=p);true"})
        t.ok('native frame policy ignores page-supplied host and mode',wait(lambda:sv.cmd({'do':'eval','id':native,'world':'search','js':"globalThis.__nightProof?.mode"}).get('value')=='always') and night(native)['enabled'])
        night(native,enabled=False);t.ok('global disable restores every live tab without reload',wait(lambda:background(native,'body')=='rgb(32, 32, 32)') and background(tab,'body')==original)
        night(tab,enabled=True,mode='automatic');night(tab,appearance='light')
        lightRestored=wait(lambda:status(tab)=='waiting-dark') and background(tab,'body')==original
        t.ok('automatic restores inactive tab colors in light appearance',lightRestored,{'status':night(tab),'background':background(tab,'body'),'pageDark':value(tab,"matchMedia('(prefers-color-scheme: dark)').matches")})
        t.ok('inactive subframe also follows browser appearance',wait(lambda:value(tab,"getComputedStyle(document.querySelector('#frame').contentDocument.body).backgroundColor")=='rgb(255, 255, 255)'))
        night(tab,mode='always');t.ok('Always adapt overrides light browser appearance',wait(lambda:status(tab)=='adapted') and background(tab,'body')=='rgb(28, 28, 28)')
        night(tab,mode='automatic');assert wait(lambda:status(tab)=='waiting-dark')
        night(tab,appearance='dark');t.ok('automatic follows return to dark appearance',wait(lambda:status(tab)=='adapted'))
        strict=sv.sp('open',url=base+'/strict.html')['resultID'];assert wait(lambda:value(strict,"location.pathname==='/strict.html' && document.readyState==='complete'"));time.sleep(.5)
        t.ok('strict stylesheet policy uses guarded color fallback',background(strict,'body')=='rgb(28, 28, 28)' and night(strict)['status'].get('fallback'))
        revision=night(strict)['status']['revision'];time.sleep(.7)
        t.ok('fallback ignores its own writes while the page is idle',night(strict)['status']['revision']==revision)
        value(strict,"document.body.style.color='rgb(0, 90, 0)';true");night(strict,mode='off')
        t.ok('fallback restoration keeps later author edits',background(strict,'body')=='rgb(255, 255, 255)' and value(strict,"getComputedStyle(document.body).color")=='rgb(0, 90, 0)')
        value(tab,"document.body.style.setProperty('background-color','white','important');true");night(tab,mode='automatic')
        t.ok('author important colors can adapt with guarded ownership',wait(lambda:background(tab,'body')=='rgb(28, 28, 28)') and night(tab)['status'].get('fallback'))
        night(tab,mode='off')
        t.ok('important declaration and priority restore exactly',background(tab,'body')=='rgb(255, 255, 255)' and value(tab,"document.body.style.getPropertyPriority('background-color')")=='important')
        value(tab,"document.body.style.removeProperty('background-color');true");night(tab,mode='automatic')
        # Synthetic large pages must report a bound instead of processing indefinitely.
        sv.sp('select',id=tab);value(tab,"const f=document.createDocumentFragment();for(let i=0;i<3500;i++){const p=document.createElement('span');p.textContent='Token ';f.appendChild(p)}document.body.appendChild(f);true")
        t.ok('large DOM processing is bounded and reported',wait(lambda:night(tab)['status']['truncated']) and night(tab)['status']['elements']<=3000)
    finally:t.done();sv.finish();server.shutdown()
sys.exit(1 if t.failed else 0)
