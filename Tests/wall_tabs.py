#!/usr/bin/env python3
"""Native Wall tab lifecycle, web isolation and real app workflow screenshots."""
import json
import sys
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('wall-tab-tests')
t = sv.T()
out = sv.ROOT / 'artifacts' / 'wall-tabs'
out.mkdir(parents=True, exist_ok=True)
def wall(action='state', **fields): return sv.cmd({'do':'wall','action':action,**fields})
def wait_for(predicate):
    for _ in range(100):
        if predicate(): return True
        time.sleep(.1)
    return False
def picture(name):
    time.sleep(.5)
    sv.cmd({'do':'picture','path':str(out/name),'page':False})
try:
    sv.setup(sidebar=False, **{'tabs.groups':True}); sv.launch()
    page = sv.page('design-research')
    wait_for(lambda: wall()['canCapture'])
    sv.ev(page, """document.title='Design research'; window.locusKeep=73;
    document.head.insertAdjacentHTML('beforeend', `<style>body{background:#f6f5f1;color:#29312c;font:17px -apple-system;margin:0}main{max-width:760px;margin:60px auto;padding:24px}h1{font-size:52px;letter-spacing:-2px;font-weight:550;margin:45px 0 22px}p{color:#738075;line-height:1.6}section{background:white;border:1px solid #e2e5dc;border-radius:16px;padding:30px;margin-top:36px}button{background:#53664e;color:white;border:0;border-radius:9px;padding:14px 22px;font:500 15px -apple-system}small{font-size:12px;color:#879182}</style>`);
    document.body.innerHTML=`<main><small>LOCUS / LOCAL WORKFLOW SAMPLE</small><h1>A place for ideas<br>while you browse.</h1><p>Keep references, interface details and research in your Space.<br>Your page stays right where you left it.</p><section><h2>Quiet interfaces</h2><p>Collect a component, connect the evidence, return to the work.</p><button id='reference'>Save a reference</button></section></main>`; true""")
    sv.cmd({'do':'pages','on':True})
    before=sv.sp('state'); built=wall()['builtTabs']
    picture('01-page-and-wall-button.png')
    sv.sp('mouse',points=[[1127,26],[1127,26]],to='view')
    t.ok('toolbar button beside Bookmarks opens Wall',wall()['showing'])
    state=wall('open'); wid=state['wallTabs'][0]
    t.ok('Wall is a separate selected tab', sv.sp('state')['activeID']==wid and len(sv.order(sv.sp('state')))==len(sv.order(before))+1)
    t.ok('ordinary tabs retain their identities', all(x in sv.order(sv.sp('state')) for x in sv.order(before)))
    t.ok('opening native Wall creates no WebKit view', state['builtTabs']==built, {'before':built,'after':state['builtTabs'],'native':wid})
    t.ok('Wall remembers its named normal source', state['sourceTab']==page and state['canCaptureSource'])
    wall('open'); t.ok('repeated open selects the same Wall', wall()['wallTabs']==[wid])
    saved=wall('savePage'); obj=next(x['id'] for x in saved['objects'] if x['type']=='page')
    wall('note',title='Interface study',text='Keep controls close to their source. Capture CSS and geometry, then connect references.')
    picture('02-wall-as-a-tab.png')
    sv.sp('select',id=page)
    t.ok('selecting a page leaves Wall open', wall()['wallTabs']==[wid] and not wall()['showing'])
    t.ok('page document survives Wall switches',sv.ev(page,'window.locusKeep')==73)
    picture('03-back-to-the-page.png')
    wall('open'); wall('openPage',id=obj)
    t.ok('opening a Wall object returns to its bound page',sv.sp('state')['activeID']==page and wall()['wallTabs']==[wid])
    wall('open'); sv.cmd({'do':'press','code':53,'chars':'','mods':[]});time.sleep(.2)
    t.ok('Escape keeps the native Wall tab',wall()['showing'] and wall()['wallTabs']==[wid])
    sv.cmd({'do':'press','code':13,'chars':'w','mods':['cmd']});time.sleep(.3)
    t.ok('Command-W closes only the Wall tab',wall()['wallTabs']==[] and page in sv.order(sv.sp('state')))
    sv.cmd({'do':'press','code':17,'chars':'T','mods':['cmd','shift']});time.sleep(.3)
    t.ok('Reopen Closed Tab restores native content',wall()['showing'] and len(wall()['wallTabs'])==1 and len(wall()['builtTabs'])==len(built))
    wid=wall()['wallTabs'][0]
    sv.cmd({'do':'pin','id':wid});t.ok('Wall cannot become a web pin',sv.cmd({'do':'pin','id':wid})['pin']=='')
    grouped=sv.sp('group',id=wid); group=grouped['groups'][-1]['id']
    sv.cmd({'do':'group','name':group,'close':True});sv.sp('reopen')
    wid=wall()['wallTabs'][0];grouped=sv.sp('state')
    t.ok('Wall can return to a reopened tab group',grouped['groupIDs'][sv.order(grouped).index(wid)]==group)
    sv.sp('group',id=wid,group='none')
    sv.sp('enabled',on=True); count=len(sv.order(sv.sp('state')))
    sv.sp('start');sv.cmd({'do':'split','action':'pair','id':wid,'with':page})
    t.ok('Wall cannot enter a web split',not sv.sp('state')['splits'] and len(sv.order(sv.sp('state')))==count)
    # Omnibox must be available even with the split-view setting enabled.
    wall('search',typed='wall: Interface');time.sleep(.3)
    t.ok('object search remains usable from Wall',wall()['editing'] and any(x.get('object') for x in wall()['offers']))
    picture('04-wall-object-search.png')
    sv.sp('dismiss'); wall('search',typed=sv.BASE+'/new-page');wall('submitSearch')
    t.ok('URL from Wall opens an ordinary tab',not wall()['showing'] and wall()['wallTabs']==[wid] and sv.url(sv.sp('state'),sv.sp('state')['activeID'])==sv.BASE+'/new-page')
    sv.sp('select',id=page);wall('open');wall('captureSelector',selector='#reference')
    t.ok('capture selects source page first',sv.sp('state')['activeID']==page or not wall()['capturing'])
    t.ok('capture completes and returns to same Wall',wait_for(lambda:not wall()['capturing']) and wall()['showing'] and wall()['wallTabs']==[wid] and any(x['type']=='uiCapture' for x in wall()['objects']))
    t.ok('capture still preserves the original document',sv.ev(page,'window.locusKeep')==73)
    sv.cmd({'do':'ui','spaces':True});sv.cmd({'do':'space','action':'new','name':'Design'})
    state=wall('open'); other_space=state['spaceID']
    t.ok('each Space gets its own Wall tab and objects',state['showing'] and state['objects']==[] and state['wallTabs']!=[wid])
    wall('note',title='Design brief')
    sv.cmd({'do':'space','action':'go','index':1})
    t.ok('switching Spaces restores selected Wall',wall()['showing'] and wall()['wallTabs']==[wid] and len(wall()['objects'])==3)
    # Pinning/splits/native URI markers must not sneak in via restored session rows.
    group=sv.sp('group',id=wid)['groups'][-1]['id']
    sv.sp('save'); saved=sv.session(); native=next(e for e in saved['tabs'] if e.get('nativeKind')=='wall')
    t.ok('session records explicit native kind',native['url'].endswith(wall()['spaceID']) and saved['tabs'][saved['active']].get('nativeKind')=='wall')
    sv.quit()
    saved['tabs'] += [dict(native),dict(native,url='locus://wall/'+other_space),dict(native,nativeKind='future'),dict(native,nativeKind=123),dict(url=native['url'],title='Unmarked')]
    Path(sv.SUPPORT,'session.json').write_text(json.dumps(saved))
    sv.launch();state=wall()
    t.ok('restart restores selected Wall once and keeps ordinary tabs',state['showing'] and len(state['wallTabs'])==1 and sum(x['nativeKind']=='wall' for x in sv.sp('state')['tabs'])==1 and any(x['url']==sv.BASE+'/design-research' for x in sv.sp('state')['tabs']))
    restored=sv.sp('state'); restored_wall=state['wallTabs'][0]
    t.ok('restart preserves native Wall tab group',restored['groupIDs'][sv.order(restored).index(restored_wall)]==group)
    t.ok('restored native Wall remains free of WebKit',state['builtTabs']==[])
    t.ok('restored Wall requires explicit source selection',state['sourceTab']=='' and not state['canCaptureSource'])
    page=next(x['id'] for x in sv.sp('state')['tabs'] if x['url']==sv.BASE+'/design-research')
    sv.sp('select',id=page);wait_for(lambda:wall()['canCapture']);wall('open')
    t.ok('normal page can become the source after restart',wall()['sourceTab']==page)
    sv.sp('private');private=sv.page('private-research');wait_for(lambda:sv.ev(private,'document.readyState')=='complete')
    wall('open');count=len(wall()['objects']);wall('savePage')
    t.ok('private page never becomes a durable Wall source',wall()['sourceTab']=='' and not wall()['canCaptureSource'] and len(wall()['objects'])==count)
    (out/'manifest.json').write_text(json.dumps({'source':'Tests/wall_tabs.py','provenance':'Native app screenshots from an isolated test profile, with a local HTML fixture.','world':sv.W,'screenshots':sorted(p.name for p in out.glob('*.png'))},indent=2)+'\n')
finally:
    t.done();sv.finish()
sys.exit(1 if t.failed else 0)
