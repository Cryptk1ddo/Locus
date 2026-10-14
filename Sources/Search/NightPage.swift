import Foundation

/// Isolated-world DOM adapter with removable CSS and guarded color-only fallback.
enum NightPage {
    static let script = #"""
    (() => {
      if(globalThis.__locusNight)return;
      const M=globalThis.__locusNightMath,C=globalThis.__locusNightCSS,attribute='data-locus-night-'+Math.random().toString(36).slice(2);
      const sheets=new Map(),marked=new Set(),observers=new Map(),inline=new Map(),lastInline=new WeakMap();
      let config={enabled:false,mode:'automatic'},timer=null,working=false,dirty=false,serial=0,generation=0;
      let info={state:'disabled',elements:0,truncated:false,unsupported:0};
      let motion=new Map(),charts=new Map(),preservedMotion=0;const watchedAnimations=new WeakSet();let motionTimer=null,motionStamp='',animationSerial=0;const animationIDs=new WeakMap();
      const white=C.parse('#fff'),media=matchMedia('(prefers-color-scheme: dark)');
      const parentOf=e=>e.parentElement||(e.getRootNode().host||null);
      const mode=()=>config.mode||'automatic';
      const eligible=()=>/^https?:$/.test(location.protocol);
      function restoreInline(){
        for(const [element,record] of inline){
          for(const [property,entry] of record.properties){
            if(element.style.getPropertyValue(property)===entry.owned&&element.style.getPropertyPriority(property)==='important'){
              if(entry.value)element.style.setProperty(property,entry.value,entry.priority);else element.style.removeProperty(property);
            }
          }
          if(!record.hadStyle&&!element.style.cssText)element.removeAttribute('style');
        }
        inline.clear();
      }
      function applyInline(rows){
        let bytes=0,limited=false;
        for(const [element,declarations] of rows){
          bytes+=declarations.join(';').length;if(bytes>2_000_000){limited=true;break;}
          const properties=new Map(),hadStyle=element.hasAttribute('style');
          for(const declaration of declarations){
            const split=declaration.indexOf(':');if(split<0)continue;
            const property=declaration.slice(0,split),value=declaration.slice(split+1).replace(/ !important$/,'');
            const entry=properties.get(property)||{value:element.style.getPropertyValue(property),priority:element.style.getPropertyPriority(property)};
            element.style.setProperty(property,value,'important');entry.owned=element.style.getPropertyValue(property);properties.set(property,entry);
          }
          inline.set(element,{properties,hadStyle});lastInline.set(element,element.style.cssText);
        }
        return limited;
      }
      function clear(){
        if(timer!==null)clearTimeout(timer);timer=null;
        if(motionTimer!==null)clearInterval(motionTimer);motionTimer=null;motionStamp='';motion.clear();charts.clear();
        for(const observer of observers.values())observer.disconnect();for(const root of observers.keys())unobserveEvents(root);observers.clear();restoreInline();
        for(const sheet of sheets.values())sheet.remove();sheets.clear();
        for(const element of marked)element.removeAttribute(attribute);marked.clear();
      }
      function sheet(root){
        if(sheets.has(root))return sheets.get(root);
        const style=document.createElement('style');style.setAttribute('data-locus-night-style','');
        (root===document?(document.head||document.documentElement):root).appendChild(style);sheets.set(root,style);return style;
      }
      function observe(root){
        if(observers.has(root))return;
        const observer=new MutationObserver(records=>{
          if(records.some(r=>r.attributeName!==attribute&&!(r.attributeName==='style'&&inline.has(r.target)&&lastInline.get(r.target)===r.target.style.cssText)&&!r.target.closest?.('[data-locus-night-style]')&&
            !(r.type==='childList'&&[...r.addedNodes,...r.removedNodes].every(n=>n.nodeType===1&&n.hasAttribute?.('data-locus-night-style')))))schedule();
        });
        observer.observe(root,{subtree:true,childList:true,attributes:true,attributeFilter:['class','style','hidden','disabled','aria-disabled','aria-label','aria-roledescription','data-locus-night','fill','stroke','stop-color',attribute],characterData:true});observers.set(root,observer);
        for(const event of ['pointerover','pointerout','pointerdown','pointerup','focusin','focusout','input','change','animationstart','animationend','animationcancel'])root.addEventListener(event,stateChange,true);
      }
      function schedule(delay=120){if(timer!==null)clearTimeout(timer);timer=setTimeout(run,delay);}
      const events=['pointerover','pointerout','pointerdown','pointerup','focusin','focusout','input','change','animationstart','animationend','animationcancel'];
      function stateChange(){schedule(30);}
      function unobserveEvents(root){for(const event of events)root.removeEventListener(event,stateChange,true);}
      function motionSignature(){return (document.getAnimations?.()||[]).slice(0,256).filter(a=>a.playState!=='finished'&&a.playState!=='idle').map(a=>{if(!animationIDs.has(a))animationIDs.set(a,++animationSerial);return animationIDs.get(a)+':'+a.playState;}).join(',');}
      function watchMotion(){motionStamp=motionSignature();if(!document.hidden&&motionTimer===null)motionTimer=setInterval(()=>{if(document.hidden)return;const next=motionSignature();if(next!==motionStamp){motionStamp=next;schedule(30);}},400);}
      function collectMotion(){motion=new Map();preservedMotion=0;
        for(const animation of (document.getAnimations?.()||[]).slice(0,256)){
          if(animation.playState==='finished'||animation.playState==='idle')continue;
          const effect=animation.effect,e=effect?.target;if(!e||effect.pseudoElement)continue;
          const set=motion.get(e)||new Set();for(const frame of effect.getKeyframes().slice(0,64))for(const name of Object.keys(frame)){const property=name.replace(/[A-Z]/g,x=>'-'+x.toLowerCase());if(C.paints.has(property))set.add(property);}
          if(set.size){motion.set(e,set);if(!watchedAnimations.has(animation)){watchedAnimations.add(animation);animation.finished.then(stateChange,stateChange);}}
        }
      }
      const ratio=e=>{const r=e.getBoundingClientRect();return Math.min(1,Math.max(0,r.width*r.height)/Math.max(1,innerWidth*innerHeight));};
      function gradient(value,role,context){
        if(value==='none'||!/gradient\(/i.test(value))return null;
        return C.rewrite(value,c=>M.css(M.adapt(c,role,M.canvas,context)));
      }
      function palette(e,style,sourceBackground,targetBackground,depth,pseudo=false){
        const declarations=[],area=ratio(e),tag=e.tagName.toLowerCase();
        const retained=new Set([...C.transitions(style),...(pseudo&&style.animationName!=='none'?C.paints:motion.get(e)||[])]);
        if(retained.has('color'))retained.add('-webkit-text-fill-color');
        const disabled=e.matches(':disabled,[aria-disabled="true"]'),interactive=e.matches('button,input[type=button],input[type=submit],[role=button]');
        const heading=e.matches('h1,h2,h3,h4,h5,h6,[role=heading]');
        const font=parseFloat(style.fontSize)||14,weight=parseInt(style.fontWeight)||400,large=font>=24||(font>=18.66&&weight>=700);
        const context={area,depth,disabled,heading,large};
        const bg=C.parse(style.backgroundColor);let mapped=targetBackground;
        if(bg&&bg.a>.01){
          mapped=retained.has('background-color')?bg:M.adapt(bg,interactive&&M.lch(bg).c>.05?'accent-fill':'surface',targetBackground,context);
          declarations.push('background-color:'+M.css(mapped)+' !important');mapped=M.composite(mapped,targetBackground);
        }
        if(!pseudo&&!retained.has('background-color')&&(e===document.documentElement||e===document.body)){mapped=M.canvas;declarations.push('background-color:#1c1c1c !important','color-scheme:dark !important');}
        const fg=C.parse(style.color);
        if(fg&&fg.a>.01){
          const source=M.composite(fg,sourceBackground),adapted=M.adapt(source,'text',mapped,{...context,originalContrast:M.contrast(source,sourceBackground)});
          declarations.push('color:'+M.css(adapted)+' !important');
          if(style.webkitTextFillColor&&style.webkitTextFillColor!=='rgba(0, 0, 0, 0)')declarations.push('-webkit-text-fill-color:'+M.css(adapted)+' !important');
          if(['input','textarea'].includes(tag))declarations.push('caret-color:'+M.css(adapted)+' !important');
        }
        for(const side of ['Top','Right','Bottom','Left']){
          if(style['border'+side+'Style']==='none'||parseFloat(style['border'+side+'Width'])===0)continue;
          const c=C.parse(style['border'+side+'Color']);if(c&&c.a>.01)declarations.push('border-'+side.toLowerCase()+'-color:'+M.css(M.adapt(c,'border',mapped,{...context,strength:M.contrast(M.composite(c,sourceBackground),sourceBackground)/10}))+' !important');
        }
        const g=gradient(style.backgroundImage,'surface',context);if(g)declarations.push('background-image:'+g+' !important');
        for(const property of ['boxShadow','textShadow']){
          const raw=style[property];if(raw&&raw!=='none'&&raw.length<4000){
            const value=C.rewrite(raw,c=>M.css(M.adapt(c,'shadow',mapped,context)));
            if(value)declarations.push((property==='boxShadow'?'box-shadow':'text-shadow')+':'+value+' !important');
          }
        }
        // Graphic artwork is retained. Small SVG UI icons use explicit paint roles.
        const svg=e.closest('svg');if(svg){const r=svg.getBoundingClientRect();
          if(charts.get(svg)||r.width*r.height<=4096&&svg.getAttribute('role')!=='img')for(const property of ['fill','stroke']){
            const c=C.parse(style[property]);const neutral=c&&M.lch(c).c<.03,axis=e.closest('.axis,.grid,.tick,.recharts-cartesian-axis,.highcharts-axis,.highcharts-grid'),label=['text','tspan'].includes(tag);
            if(c&&c.a>.01&&(!charts.get(svg)||neutral&&(axis||label)))declarations.push(property+':'+M.css(M.adapt(c,charts.get(svg)&&!label?'border':'text',mapped,{...context,large:charts.get(svg)&&label?large:true,strength:axis?.matches('.grid,.highcharts-grid')?.1:.8,originalContrast:M.contrast(M.composite(c,sourceBackground),sourceBackground)}))+' !important');
            else if(charts.get(svg))declarations.push(property+':'+style[property]+' !important');
          }
        }
        if(style.outlineStyle!=='none'&&parseFloat(style.outlineWidth)>0){const c=C.parse(style.outlineColor);if(c)declarations.push('outline-color:'+M.css(M.adapt(c,'text',mapped,{...context,large:true}))+' !important');}
        const filtered=declarations.filter(d=>!retained.has(d.slice(0,d.indexOf(':'))));if(filtered.length!==declarations.length)preservedMotion++;
        return {declarations:filtered,mapped};
      }
      function run(){
        timer=null;if(working){dirty=true;return;}working=true;generation++;
        try{
          const choice=mode();if(!config.enabled||choice==='off'||!eligible()){clear();info={state:'disabled',elements:0,truncated:false,unsupported:0};return;}
          if(choice!=='always'&&!config.dark){clear();info={state:'waiting-dark',elements:0,truncated:false,unsupported:0};return;}
          if(!document.body){schedule();return;}
          restoreInline();for(const style of sheets.values())if(style.sheet)style.sheet.disabled=true;
          const body=getComputedStyle(document.body),root=getComputedStyle(document.documentElement);
          const rootBG=C.parse(root.backgroundColor)||white,bg=M.composite(C.parse(body.backgroundColor)||white,M.composite(rootBG,white)),fg=C.parse(body.color)||C.parse('#000');
          if(choice!=='always'&&M.lch(bg).l<.48&&M.contrast(M.composite(fg,bg),bg)>=4.5){
            clear();info={state:'native-dark',elements:0,truncated:false,unsupported:0};observe(document);return;
          }
          collectMotion();charts=new Map();
          const nodes=[],roots=new Set([document]),stack=[document.documentElement];let truncated=false;
          while(stack.length){const e=stack.pop();if(!e||e.hasAttribute('data-locus-night-style'))continue;
            if(nodes.length>=3000){truncated=true;break;}nodes.push(e);
            const remaining=3000-nodes.length-stack.length,children=[];
            for(let i=0;i<e.children.length&&children.length<remaining;i++)children.push(e.children[i]);
            if(e.children.length>children.length)truncated=true;
            if(e.shadowRoot){roots.add(e.shadowRoot);for(let i=0;i<e.shadowRoot.children.length&&children.length<remaining;i++)children.push(e.shadowRoot.children[i]);if(e.shadowRoot.children.length>remaining- Math.min(e.children.length,remaining))truncated=true;}
            for(let i=children.length-1;i>=0;i--)stack.push(children[i]);
          }
          const inlineRows=[],original=new Map(),adapted=new Map(),depths=new Map(),nextMarked=new Set(),rules=new Map([...roots].map(r=>[r,[]]));let unsupported=0;
          for(const e of nodes){
            const tag=e.tagName.toLowerCase();if(['script','style','link','meta','noscript','img','video','canvas','picture','source'].includes(tag))continue;
            const svg=e.closest('svg');let artwork=false;if(svg){const r=svg.getBoundingClientRect();if(!charts.has(svg))charts.set(svg,C.chart(svg));artwork=!charts.get(svg)&&(r.width*r.height>4096||svg.getAttribute('role')==='img');if(artwork&&e!==svg)continue;}
            const style=getComputedStyle(e),parent=parentOf(e),parentSource=original.get(parent)||bg,parentTarget=adapted.get(parent)||M.canvas;
            const color=C.parse(style.backgroundColor);if(!color)unsupported++;
            const source=color?M.composite(color,parentSource):parentSource;original.set(e,source);
            const depth=(e===document.documentElement||e===document.body)?0:(depths.get(parent)||0)+(color&&color.a>.1?1:0);depths.set(e,depth);
            const result=artwork?{declarations:['color:'+style.color+' !important'],mapped:parentTarget}:palette(e,style,source,parentTarget,Math.min(4,depth));adapted.set(e,result.mapped);
            if(charts.get(svg)&&e===svg)result.declarations=result.declarations.filter(d=>!d.startsWith('color:')).concat('color:'+style.color+' !important');
            const id=String(++serial);e.setAttribute(attribute,id);marked.add(e);nextMarked.add(e);
            const selector='['+attribute+'="'+id+'"]',list=rules.get(e.getRootNode());if(!list)continue;
            list.push(selector+'{'+result.declarations.join(';')+'}');inlineRows.push([e,result.declarations]);
            if(artwork)continue;for(const pseudo of ['::before','::after']){
              const s=getComputedStyle(e,pseudo);if(!s.content||s.content==='none'||s.content==='normal')continue;
              const p=palette(e,s,source,result.mapped,Math.min(4,depth+1),true);list.push(selector+pseudo+'{'+p.declarations.join(';')+'}');
            }
          }
          // Disconnected nodes and vanished open roots release their retained state.
          for(const e of marked)if(!nextMarked.has(e)){e.removeAttribute(attribute);marked.delete(e);}
          for(const [root,style] of sheets)if(!roots.has(root)){style.remove();sheets.delete(root);observers.get(root)?.disconnect();unobserveEvents(root);observers.delete(root);}
          let bytes=0;
          for(const [root,list] of rules){const css=list.join('\n');bytes+=css.length;const style=sheet(root);style.textContent=bytes<=2_000_000?css:'';if(bytes>2_000_000)truncated=true;if(style.sheet)style.sheet.disabled=false;observe(root);}
          const fallback=[...sheets.values()].some(style=>!style.sheet)||inlineRows.some(([e,ds])=>ds.some(d=>e.style.getPropertyPriority(d.slice(0,d.indexOf(':')))==='important'));
          if(fallback)truncated=applyInline(inlineRows)||truncated;
          watchMotion();info={state:'adapted',elements:nodes.length,truncated,unsupported,fallback,preservedMotion,charts:[...charts.values()].filter(Boolean).length};
        }catch(error){clear();info={state:'error',elements:0,truncated:false,unsupported:0,message:String(error).slice(0,300)};}finally{for(const style of sheets.values())if(style.sheet)style.sheet.disabled=false;working=false;if(dirty){dirty=false;schedule();}}
      }
      function notifyChildren(){for(const frame of document.querySelectorAll('iframe,frame'))try{frame.contentWindow.postMessage({type:'locus-night-refresh',token:config.token},'*');}catch{}}
      async function request(){
        try{const policy=await window.webkit.messageHandlers.locusNightPolicy.postMessage({});update({...policy,token:config.token},true);}
        catch{update({enabled:false,mode:'automatic',token:config.token});}
      }
      function update(next,broadcast=false){config=next;run();if(broadcast)notifyChildren();}
      addEventListener('message',event=>{if(event.source===parent&&event.data?.type==='locus-night-refresh'&&event.data.token===config.token)request();});
      // Inactive/detached WebKit views can retain their old media-query appearance.
      // The native browser appearance is authoritative; media changes request it again.
      addEventListener('visibilitychange',()=>{if(document.hidden){if(motionTimer!==null)clearInterval(motionTimer);motionTimer=null;}else{stateChange();if(config.enabled&&info.state==='adapted')watchMotion();}});
      media.addEventListener('change',request);addEventListener('resize',()=>schedule());addEventListener('load',()=>schedule(),true);
      globalThis.__locusNight={update,request,status:()=>({motionPolling:motionTimer!==null,...info,revision:generation}),refresh:run};
    })();
    """#
}
