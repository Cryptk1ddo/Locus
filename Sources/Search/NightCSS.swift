import Foundation

/// CSS syntax is resolved by WebKit; only color tokens are replaced.
enum NightCSS {
    static let script = #"""
    (()=>{
      const M=globalThis.__locusNightMath,cache=new Map();let context;
      function parse(raw){
        const direct=M.parse(raw);if(direct)return direct;
        if(raw.length>4000||!CSS.supports('color',raw)||/\b(?:var|env|currentcolor|inherit|initial|unset|revert)\b/i.test(raw))return null;
        if(cache.has(raw))return cache.get(raw);
        // A private one-pixel color swatch, never page artwork or a DOM element.
        context ||= document.createElement('canvas').getContext('2d',{willReadFrequently:true});if(!context)return null;
        context.canvas.width=context.canvas.height=1;context.clearRect(0,0,1,1);context.fillStyle='#010203';context.fillStyle=raw;
        if(context.fillStyle==='#010203'){context.fillStyle='#040506';context.fillStyle=raw;if(context.fillStyle==='#040506')return null;}context.fillRect(0,0,1,1);
        const p=context.getImageData(0,0,1,1).data,c={rgb:[p[0]/255,p[1]/255,p[2]/255],a:p[3]/255};
        if(cache.size>=256)cache.clear();cache.set(raw,c);return c;
      }
      function rewrite(text,map){
        if(!text||text.length>16000)return null;let changed=false;
        function scan(value){let out='',i=0;
          while(i<value.length){
            const start=i,ch=value[i];
            if(ch==='"'||ch==="'"){const quote=ch;i++;while(i<value.length){if(value[i++]==='\\'){i++;continue;}if(value[i-1]===quote)break;}out+=value.slice(start,i);continue;}
            if(ch==='#'){const match=value.slice(i).match(/^#[\da-f]{3,8}\b/i);if(match){const c=parse(match[0]);out+=c?(changed=true,map(c)):match[0];i+=match[0].length;continue;}}
            const word=value.slice(i).match(/^[a-z][\w-]*/i);
            if(word){i+=word[0].length;const name=word[0].toLowerCase();
              if(value[i]==='('){let depth=1;i++;let quote=null;while(i<value.length&&depth){const c=value[i++];if(quote){if(c==='\\')i++;else if(c===quote)quote=null;}else if(c==='"'||c==="'")quote=c;else if(c==='(')depth++;else if(c===')')depth--;}
                const raw=value.slice(start,i);if(depth){out+=raw;continue;}
                if(name.endsWith('gradient'))out+=word[0]+'('+scan(raw.slice(word[0].length+1,-1))+')';
                else if(['rgb','rgba','hsl','hsla','hwb','lab','lch','oklab','oklch','color','color-mix','light-dark'].includes(name)){const c=parse(raw);out+=c?(changed=true,map(c)):raw;}
                else out+=raw; // URL/calc/var payloads are never tokenized as colors.
              }else{const c=parse(word[0]);out+=c?(changed=true,map(c)):word[0];}
              continue;
            }
            out+=ch;i++;
          }return out;
        }
        const result=scan(text);return changed?result:null;
      }
      const paints=new Set(['color','background-color','background-image','border-top-color','border-right-color','border-bottom-color','border-left-color','outline-color','box-shadow','text-shadow','fill','stroke','stop-color','caret-color','-webkit-text-fill-color']);
      function transitions(style){const result=new Set(),names=style.transitionProperty.split(','),durations=style.transitionDuration.split(',');
        names.forEach((name,i)=>{if(!(parseFloat(durations[i%durations.length])>0))return;name=name.trim();if(name==='all')paints.forEach(p=>result.add(p));else if(paints.has(name))result.add(name);else if(name==='background')result.add('background-color');else if(name==='border-color')for(const p of paints)if(p.startsWith('border-'))result.add(p);});return result;
      }
      function chart(svg){return /chart|graph|plot/i.test([svg.getAttribute('aria-roledescription'),svg.getAttribute('aria-label'),svg.getAttribute('class')].join(' '))||svg.getAttribute('data-locus-night')==='chart'||!!svg.querySelector('.axis,.grid,.tick,.recharts-cartesian-axis,.highcharts-axis');}
      globalThis.__locusNightCSS={parse,rewrite,transitions,paints,chart};
    })();
    """#
}
