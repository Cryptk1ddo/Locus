import Foundation

/// Injected on demand in Web.world, never in the page's JavaScript world.
enum UICaptureScript {
    static let library = #"""
    (() => {
      const previous = window.__locusCapture;
      if (previous) previous.stop();
      let stopped = false, outline = null;
      const bound = (v, n = 2048) => String(v || '').slice(0, n);
      const status = (value, state = 'captured', reason = '') => ({status: state, reason, value});
      const safeURL = value => {
        if (typeof value !== 'string' || !value.trim()) return '';
        try { const u = new URL(value, location.href);
          return ['http:', 'https:'].includes(u.protocol) ? u.origin + u.pathname : '';
        } catch { return ''; }
      };
      const sensitive = e => e.matches('input,textarea,select,[contenteditable]:not([contenteditable="false"])') ||
        !!e.closest('input,textarea,select,[contenteditable]:not([contenteditable="false"])');
      const inspect = element => {
        if (!(element instanceof Element) || element === outline) throw new Error('No element selected');
        if (sensitive(element)) throw new Error('Choose an element outside editable fields');
        let nodes = 0, truncated = false, unsafePixels = false, assetsCut = false;
        const assets = [];
        const attrs = new Set(['id','class','role','aria-label','aria-labelledby','aria-describedby','aria-expanded',
          'aria-hidden','aria-checked','aria-selected','aria-disabled','alt','title','href','src','viewBox','d','fill','stroke']);
        const serialize = (node, depth = 0) => {
          if (++nodes > 200 || depth > 8) { truncated = true; return null; }
          if (node.nodeType === Node.TEXT_NODE) { if ((node.textContent || '').length > 512) truncated = true; return {text: bound(node.textContent, 512)}; }
          if (!(node instanceof Element)) return null;
          if (sensitive(node)) { unsafePixels = true; return null; }
          if (node.localName.includes('-')) unsafePixels = true;
          if (node.matches('script,style,template,noscript')) return null;
          const css = getComputedStyle(node);
          if (css.display === 'none' || css.visibility !== 'visible' || Number(css.opacity) === 0) return null;
          if (assets.length >= 40 && ['img','svg'].includes(node.localName)) assetsCut = true;
          if (assets.length < 40 && node.localName === 'img') assets.push({type:'image', url:safeURL(node.currentSrc || node.src), alt:bound(node.alt,200)});
          if (assets.length < 40 && node.localName === 'svg') assets.push({type:'svg', inline:true, representation:'sanitized DOM subtree'});
          const attributes = {};
          for (const a of node.attributes) if (attrs.has(a.name)) {
            if (a.value.length > 2048) truncated = true;
            attributes[a.name] = ['href','src'].includes(a.name) ? safeURL(a.value) : bound(a.value);
          }
          const children = [];
          for (const child of node.childNodes) {
            if (nodes >= 200) { truncated = true; break; }
            const result = serialize(child, depth + 1); if (result) children.push(result);
          }
          const result = {tag: node.localName, attributes, children};
          if (node.shadowRoot) {
            result.shadowRoot = [];
            for (const child of node.shadowRoot.childNodes) {
              if (nodes >= 200) { truncated = true; break; }
              const found = serialize(child, depth + 1); if (found) result.shadowRoot.push(found);
            }
          }
          return result;
        };
        const computed = getComputedStyle(element), styles = {}, custom = {};
        let styleCut = false;
        for (let i = 0; i < Math.min(computed.length, 800); i++) {
          const key = computed[i], value = computed.getPropertyValue(key);
          const cleaned = value.replace(/url\(([^)]*)\)/g, (_, v) => 'url("' + safeURL(v.replace(/^['"]|['"]$/g, '')) + '")');
          (key.startsWith('--') ? custom : styles)[key] = bound(cleaned);
          if (value.length > 2048) styleCut = true;
        }
        styleCut ||= computed.length > 800;
        const path = [];
        for (let node = element; node && path.length < 20;) {
          if (node.id) { path.unshift('#' + CSS.escape(node.id)); break; }
          const siblings = Array.from(node.parentElement?.children || []).filter(e => e.localName === node.localName);
          path.unshift(node.localName + ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')');
          node = node.parentElement;
        }
        const fontFaces = [];
        for (const font of document.fonts) {
          if (fontFaces.length >= 40) break;
          fontFaces.push({family:bound(font.family,256),weight:font.weight,style:font.style,status:font.status});
        }
        const pseudo = {};
        for (const name of ['::before','::after']) {
          const css = getComputedStyle(element, name);
          pseudo[name] = {content: bound(css.content), display: css.display, color: css.color,
            fontFamily: css.fontFamily, fontSize: css.fontSize, width: css.width, height: css.height};
        }
        const rect = element.getBoundingClientRect();
        if (![rect.x,rect.y,rect.width,rect.height].every(Number.isFinite) || rect.width <= 0 || rect.height <= 0)
          throw new Error('The selected element has no visible geometry');
        const animations = element.getAnimations().slice(0, 20).map(a => {
          const t = a.effect?.getComputedTiming() || {};
          return {playState:a.playState, currentTime:a.currentTime, duration:Number.isFinite(t.duration)?t.duration:'infinite', delay:t.delay, iterations:Number.isFinite(t.iterations)?t.iterations:'infinite'};
        });
        const dom = serialize(element);
        unsafePixels ||= truncated || !!element.querySelector('input,textarea,select,[contenteditable]:not([contenteditable="false"])');
        const domText = tree => !tree ? '' : (tree.text || '') + (tree.children || []).map(domText).join(' ') + (tree.shadowRoot || []).map(domText).join(' ');
        const implicitRole = {button:'button', a:element.hasAttribute('href')?'link':'generic', img:'img', h1:'heading', h2:'heading'};
        return {
          url:safeURL(location.href), title:bound(element.getAttribute('aria-label') || element.getAttribute('alt') || element.localName, 150),
          extractedAt:new Date().toISOString(), documentURL:safeURL(location.href),
          locator:status({selector:bound(path.join(' > ')), root:element.getRootNode() === document ? 'document' : 'open shadow root'},'captured','Selector is a hint; no durable element identity'),
          interactions:status({tag:element.localName,href:safeURL(element.getAttribute('href')),tabIndex:element.tabIndex,
            cursor:computed.cursor,pointerEvents:computed.pointerEvents},'captured','Declared semantics; event listeners unavailable'),
          dom:status(dom,truncated?'truncated':'captured', '200 nodes, depth 8; editable/hidden/script content omitted'),
          css:status(styles,styleCut?'truncated':'captured'), customProperties:status(custom,styleCut?'truncated':'captured'),
          pseudoElements:status(pseudo),
          geometry:status({x:rect.x,y:rect.y,width:rect.width,height:rect.height,scrollX,scrollY,
            viewportWidth:innerWidth,viewportHeight:innerHeight,devicePixelRatio,coordinateSpace:'CSS viewport pixels'}),
          fonts:status({family:computed.fontFamily,size:computed.fontSize,weight:computed.fontWeight,lineHeight:computed.lineHeight,availableFaces:fontFaces},
            'captured','Computed declaration only; fallback resolution and font binaries unavailable'),
          assets:status(assets,assetsCut?'truncated':'captured','References only; queries/credentials redacted, no network fetches'),
          motion:status({animations,transition:computed.transition,animation:computed.animation},'captured','Declared/active motion, no interaction replay'),
          accessibility:status({role:element.getAttribute('role') || implicitRole[element.localName] || 'generic',
            name:bound(element.getAttribute('aria-label') || element.getAttribute('alt') || domText(dom),200),
            disabled:element.getAttribute('aria-disabled'),expanded:element.getAttribute('aria-expanded')},
            'captured','DOM inference; not the native accessibility tree'),
          frames:status(null,'unavailable','Top document only; frame and closed shadow internals are unavailable'),
          screenshotAllowed:!unsafePixels,
          screenshot:status(null,'unavailable',unsafePixels?'Editable, custom-element or truncated subtrees excluded from screenshots':'Snapshot pending')
        };
      };
      const stop = () => {
        if (stopped) return;
        stopped = true;
        window.removeEventListener('pointermove', hover, true);
        window.removeEventListener('pointerdown', block, true);
        window.removeEventListener('mousedown', block, true);
        window.removeEventListener('click', click, true);
        window.removeEventListener('keydown', key, true);
        window.removeEventListener('pagehide', stop);
        outline?.remove(); outline = null;
        if (window.__locusCapture?.stop === stop) delete window.__locusCapture;
      };
      const send = body => window.webkit.messageHandlers.locusUICapture.postMessage(body);
      const hover = e => {
        const target = e.composedPath().find(n => n instanceof Element && n !== outline);
        if (!target || !outline) return;
        const r = target.getBoundingClientRect();
        Object.assign(outline.style, {left:r.x+'px',top:r.y+'px',width:r.width+'px',height:r.height+'px'});
      };
      const block = e => { e.preventDefault(); e.stopImmediatePropagation(); };
      const click = e => {
        e.preventDefault(); e.stopImmediatePropagation();
        const target = e.composedPath().find(n => n instanceof Element && n !== outline);
        try { const capture = inspect(target); stop(); send({token:TOKEN, capture}); }
        catch (error) { stop(); send({token:TOKEN, error:String(error.message)}); }
      };
      const key = e => { if (e.key === 'Escape') { e.preventDefault(); e.stopImmediatePropagation(); stop(); send({token:TOKEN,cancelled:true}); } };
      window.__locusCapture = {stop, inspect, token:TOKEN, start() {
        outline = document.createElement('div');
        outline.setAttribute('aria-hidden','true');
        outline.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;outline:2px solid #888;border-radius:3px;background:transparent;';
        document.documentElement.appendChild(outline);
        window.addEventListener('pointermove', hover, true);
        window.addEventListener('pointerdown', block, true);
        window.addEventListener('mousedown', block, true);
        window.addEventListener('click', click, true);
        window.addEventListener('keydown', key, true);
        window.addEventListener('pagehide', stop);
      }};
      return true;
    })()
    """#

    static func install(token: UUID, picking: Bool) -> String {
        library.replacingOccurrences(of: "TOKEN", with: "'\(token.uuidString)'")
            + (picking ? ";window.__locusCapture.start();" : "")
    }
}
