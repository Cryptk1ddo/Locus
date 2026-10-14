#!/usr/bin/env python3
"""Vault autosave and native rich previews, with synthetic files in an isolated app."""
import json,sys,time,tempfile,struct,zlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('canvas-vault-embeds');t=sv.T()
def wall(action='state',**kw):return sv.cmd({'do':'wall','action':action,**kw})
def key(code,chars='',mods=[]):
    sv.cmd({'do':'press','code':code,'chars':chars,'mods':mods});time.sleep(.15)
def edit(card):wall('canvasEdit',id=card);time.sleep(.15)
def fixture(path):
    wall('canvasFileFixture',path=str(path));state=wall();obj=state['objects'][-1]['id']
    return next(p['id'] for p in state['placementData'] if p['object']==obj)
def wait_for(predicate,seconds=4):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        if predicate():return True
        time.sleep(.15)
    return predicate()
def png(path):
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    width,height=320,100
    rows=b''.join(b'\0'+b''.join(bytes((40+int(x/width*110),110+int(y/height*70),160)) for x in range(width)) for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b''))
try:
    with tempfile.TemporaryDirectory(prefix='locus-vault-ui-') as folder:
        root=Path(folder)/'Vault';root.mkdir();source=root/'Research.md';original='# Research\n\nVault source\n';source.write_text(original)
        for name in ['Manual','Disconnected','ReadOnly']: (root/(name+'.md')).write_text('# '+name+'\n')
        outside=Path(folder)/'Outside.md';outside.write_text('# Outside\n')
        part=root/'Part.md';part.write_text('# Part\nHidden introduction\n\n## Details\nFour units\n- [ ] Review spacing\n\n## Other\nHidden ending\n');png(root/'Image.png')
        sv.setup(sidebar=False);sv.launch();sv.page('vault-embeds')
        config=wall('canvasVault',path=str(root));t.ok('Space connects an indexed vault with autosave',config['connected'] and config['autosave'] and 'Part.md' in config['entries'],config)
        card=fixture(source);wall('move',id=wall()['objects'][-1]['id'],x=40,y=40);wall('open');time.sleep(.5)
        revision=wall()['revision'];edit(card);t.ok('vault editor explains autosave',wall('canvasEditorInfo')['status']=='Autosave on')
        wall('canvasInsert',text='Autosaved addition\n')
        t.ok('typing saves the whole vault source after debounce',wait_for(lambda:source.read_text()==original+'Autosaved addition\n'))
        t.ok('autosave reports completion without Canvas history mutation',wall('canvasEditorInfo')['status']=='Autosaved' and wall()['revision']==revision)
        sv.cmd({'do':'picture','path':str(sv.ROOT/'artifacts/vault-embeds/vault-autosave-native-render.png'),'page':False})
        wall('canvasInsert',text='Flush on exit\n');key(53)
        t.ok('leaving vault editor flushes pending safe changes',source.read_text().endswith('Flush on exit\n'))
        edit(card);wall('canvasInsert',text='Conflicting draft\n');external=source.read_text()+'External source\n';source.write_text(external)
        t.ok('external change pauses autosave and preserves source',wait_for(lambda:wall('canvasEditorInfo')['status']=='Save paused · Draft kept') and source.read_text()==external)
        wall('canvasInsert',text='More draft\n');time.sleep(1.1)
        t.ok('paused autosave never retries over external changes',source.read_text()==external)
        key(53);sv.quit();sv.launch();wall('open');time.sleep(.5);edit(card);info=wall('canvasEditorInfo')
        t.ok('restart restores conflict draft with manual resume required','Conflicting draft' in info['text'] and info['status']=='Recovered draft · Save to resume',info)
        time.sleep(1);t.ok('recovered draft does not autosave over source',source.read_text()==external);key(53)
        manual=root/'Manual.md';mcard=fixture(manual);wall('canvasVault',autosave=False);edit(mcard);wall('canvasInsert',text='Manual addition\n');time.sleep(1.1)
        t.ok('disabled autosave keeps only recovery draft',manual.read_text()=='# Manual\n');key(1,'s',['cmd'])
        t.ok('manual Save remains available',manual.read_text()=='# Manual\nManual addition\n');key(53);wall('canvasVault',autosave=True)
        ocard=fixture(outside);edit(ocard);wall('canvasInsert',text='Outside draft\n');time.sleep(1.1)
        t.ok('file outside connected vault stays explicit-save',outside.read_text()=='# Outside\n');key(53)
        disconnected=root/'Disconnected.md';dcard=fixture(disconnected);edit(dcard);wall('canvasInsert',text='Pending disconnected\n');wall('canvasVault',disconnect=True);time.sleep(1.1);key(53)
        t.ok('disconnect cancels authority for a pending autosave',disconnected.read_text()=='# Disconnected\n');wall('canvasVault',path=str(root))
        readonly=root/'ReadOnly.md';rcard=fixture(readonly);edit(rcard);wall('canvasInsert',text='Pending read-only\n');wall('canvasOptions',readOnly=True);time.sleep(1.1);key(53)
        t.ok('read-only transition blocks a pending autosave',readonly.read_text()=='# ReadOnly\n');wall('canvasOptions',readOnly=False)
        edit(dcard);key(1,'s',['cmd'])
        t.ok('explicit Save resumes a recovered safe draft',disconnected.read_text()=='# Disconnected\nPending disconnected\n' and wall('canvasEditorInfo')['status']=='Saved')
        wall('canvasInsert',text='Automatic writes resumed\n')
        t.ok('typing after explicit recovery Save autosaves again',wait_for(lambda:disconnected.read_text().endswith('Automatic writes resumed\n')));key(53)
        sv.quit();sv.setup(sidebar=False);sv.launch();sv.page('rich-preview');wall('canvasVault',path=str(root))
        markdown='# Design research\n\n![[Part#Details]]\n\n| Token | Value |\n| --- | --- |\n| Spacing | 4 units |\n\n![[Image.png|240]]\n\n- [ ] Own task'
        wall('canvasImport',json=json.dumps({'nodes':[{'id':'rich','type':'text','text':markdown,'x':40,'y':40,'width':640,'height':620}],'edges':[]}))
        state=wall();obj=next(o['id'] for o in state['objects'] if o['type']=='note');richcard=next(p['id'] for p in state['placementData'] if p['object']==obj)
        wall('open');time.sleep(.5);wall('viewport',x=0,y=0,zoom=1);edit(richcard);key(53);time.sleep(.3)
        def preview():return next(p for p in wall('canvasContentInfo')['previews'] if p['object']==obj)
        row=preview();t.ok('section embed renders only requested heading','Four units' in row['text'] and 'Hidden introduction' not in row['text'] and 'Hidden ending' not in row['text'],row)
        t.ok('table and local image render as native content',row['images']==1 and row['tableCells']>=4,row)
        t.ok('embedded task opens source while outer task stays editable',len([l for l in row['links'] if l['url'].startswith('locus-task:')])==1 and any(l['url'].startswith('locus-note:') for l in row['links']))
        count=wall()['objects'].__len__();t.ok('preview expansion does not duplicate Space objects',count==1)
        sv.cmd({'do':'picture','path':str(sv.ROOT/'artifacts/vault-embeds/vault-rich-native-render.png'),'page':False})
        part.write_text(part.read_text().replace('Four units','Eight updated units'))
        t.ok('external vault edits refresh visible embedded preview',wait_for(lambda:'Eight updated units' in preview()['text'],6))
        link=next(l for l in preview()['links'] if l['url'].startswith('locus-note:'))
        sv.sp('mouse',points=[link['point'],link['point']],to='view');time.sleep(.4)
        state=wall();t.ok('following embedded source creates a granted file card',len(state['objects'])==2 and any(o['type']=='file' and o['title']=='Part.md' for o in state['objects']),state)
finally:
    t.done();sv.finish()
sys.exit(1 if t.failed else 0)
