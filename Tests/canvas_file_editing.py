#!/usr/bin/env python3
"""Native file editing in a disposable profile, using only synthetic local files."""
import sys,time,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import split_view as sv
sv.use('canvas-file-editing');t=sv.T()
def wall(action='state',**kw):return sv.cmd({'do':'wall','action':action,**kw})
def key(code,chars='',mods=[]):
    sv.cmd({'do':'press','code':code,'chars':chars,'mods':mods});time.sleep(.2)
def edit(card):wall('canvasEdit',id=card);time.sleep(.2)
try:
    with tempfile.TemporaryDirectory(prefix='locus-file-ui-') as folder:
        source=Path(folder)/'Research.md';original='# Research\n\nWhole file 🌿\n\n## Detail\nKeep this section\n';source.write_text(original)
        sv.setup(sidebar=False);sv.launch();sv.page('file-editor')
        wall('canvasFileFixture',path=str(source));objectID=wall()['objects'][0]['id'];wall('move',id=objectID,x=40,y=40);wall('open');time.sleep(.6)
        state=wall();card=state['placementData'][0]['id'];revision=state['revision']
        edit(card);t.ok('granted file opens in native card editor',wall('canvasEditorInfo')['text']==original)
        wall('canvasInsert',text='Draft text\n');key(53)
        t.ok('leaving editor keeps source untouched',source.read_text()==original)
        edit(card);t.ok('reopening restores draft',wall('canvasEditorInfo')['text']==original+'Draft text\n')
        sv.cmd({'do':'picture','path':str(sv.ROOT/'artifacts/file-editing/editor-native-render.png'),'page':False})
        key(1,'s',['cmd'])
        t.ok('Command-S saves the complete source',source.read_text()==original+'Draft text\n')
        t.ok('file save leaves Canvas snapshot history unchanged',wall()['revision']==revision)
        wall('canvasInsert',text='Restart draft\n');key(53)
        sv.quit();sv.launch();wall('open');time.sleep(.6);edit(card)
        t.ok('draft restored after browser restart',wall('canvasEditorInfo')['text']==original+'Draft text\nRestart draft\n')
        key(36,'\r',['cmd'])
        t.ok('Command-Return saves and closes editor',source.read_text().endswith('Restart draft\n') and not wall('canvasEditorInfo')['editing'])
        before=source.read_text();edit(card);wall('canvasInsert',text='Temporary edit\n');key(6,'z',['cmd']);key(6,'Z',['cmd','shift'])
        t.ok('native redo restores editor text without changing source',wall('canvasEditorInfo')['text']==before+'Temporary edit\n' and source.read_text()==before)
        key(6,'z',['cmd']);undoInfo=wall('canvasEditorInfo');key(53)
        drafts=list(Path(sv.SUPPORT).glob('workspaces/*/drafts/*.json'))
        t.ok('native text undo and clean exit remove the draft',not drafts and undoInfo['text']==before,undoInfo)
        outside=source.read_text()+'Outside edit\n';source.write_text(outside);edit(card)
        t.ok('clean reopening reads the latest external file',wall('canvasEditorInfo')['text']==outside)
        edit(card);wall('canvasInsert',text='Keep if file disappears\n');key(53)
        saved=source.read_text();source.unlink();edit(card)
        t.ok('missing source still opens its recoverable draft',wall('canvasEditorInfo')['text']==saved+'Keep if file disappears\n')
        key(53);source.write_text(saved)
        wall('canvasOptions',readOnly=True);edit(card)
        t.ok('read-only Wall rejects file editing',not wall('canvasEditorInfo')['editing'])
finally:t.done();sv.finish()
sys.exit(1 if t.failed else 0)
