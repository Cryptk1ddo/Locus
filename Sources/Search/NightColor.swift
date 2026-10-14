import Foundation

/// Pure perceptual kernel shared by injected pages and JavaScriptCore tests.
enum NightColor {
    static let script = #"""
    (() => {
      const clamp=(x,a=0,b=1)=>Math.max(a,Math.min(b,x));
      const linear=x=>x<=.04045?x/12.92:Math.pow((x+.055)/1.055,2.4);
      const encoded=x=>x<=.0031308?12.92*x:1.055*Math.pow(x,1/2.4)-.055;
      const color=(r,g,b,a=1)=>({rgb:[r,g,b],a:clamp(a)});
      const angle=x=>x.endsWith('turn')?parseFloat(x)*360:x.endsWith('grad')?parseFloat(x)*.9:x.endsWith('rad')?parseFloat(x)*180/Math.PI:parseFloat(x);
      function lch(c) {
        const [r,g,b]=c.rgb.map(linear);
        const l=Math.cbrt(.4122214708*r+.5363325363*g+.0514459929*b);
        const m=Math.cbrt(.2119034982*r+.6806995451*g+.1073969566*b);
        const s=Math.cbrt(.0883024619*r+.2817188376*g+.6299787005*b);
        const L=.2104542553*l+.793617785*m-.0040720468*s;
        const A=1.9779984951*l-2.428592205*m+.4505937099*s;
        const B=.0259040371*l+.7827717662*m-.808675766*s;
        return {l:L,c:Math.hypot(A,B),h:(Math.atan2(B,A)*180/Math.PI+360)%360,a:c.a};
      }
      function rgb(c) {
        const A=c.c*Math.cos(c.h*Math.PI/180),B=c.c*Math.sin(c.h*Math.PI/180);
        const l=(c.l+.3963377774*A+.2158037573*B)**3;
        const m=(c.l-.1055613458*A-.0638541728*B)**3;
        const s=(c.l-.0894841775*A-1.291485548*B)**3;
        return color(encoded(4.0767416621*l-3.3077115913*m+.2309699292*s),encoded(-1.2684380046*l+2.6097574011*m-.3413193965*s),encoded(-.0041960863*l-.7034186147*m+1.707614701*s),c.a);
      }
      function gamut(c) {
        let out=rgb(c);if(out.rgb.every(x=>x>=-1e-7&&x<=1+1e-7))return {...out,rgb:out.rgb.map(x=>clamp(x))};
        let lo=0,hi=c.c;for(let i=0;i<24;i++){const mid=(lo+hi)/2;out=rgb({...c,c:mid});if(out.rgb.every(x=>x>=0&&x<=1))lo=mid;else hi=mid;}
        out=rgb({...c,c:lo});return {...out,rgb:out.rgb.map(x=>clamp(x))};
      }
      function parse(value) {
        const text=String(value).trim().toLowerCase();if(text==='transparent')return color(0,0,0,0);
        if(/^#[0-9a-f]{3,8}$/.test(text)){
          let h=text.slice(1);if(h.length===3||h.length===4)h=[...h].map(x=>x+x).join('');if(h.length!==6&&h.length!==8)return null;
          return color(parseInt(h.slice(0,2),16)/255,parseInt(h.slice(2,4),16)/255,parseInt(h.slice(4,6),16)/255,h.length===8?parseInt(h.slice(6),16)/255:1);
        }
        const match=text.match(/^(rgba?|oklch|oklab|color)\((.*)\)$/);if(!match)return null;
        const pieces=match[2].replace(/,/g,' ').replace(/\//g,' / ').trim().split(/\s+/),slash=pieces.indexOf('/');
        let alpha=slash>=0?pieces[slash+1]:(match[1]==='rgba'?pieces[3]:undefined);
        const a=alpha===undefined?1:parseFloat(alpha)*(alpha.endsWith('%')?.01:1);if(!Number.isFinite(a))return null;
        const p=slash>=0?pieces.slice(0,slash):pieces;
        if(match[1]==='rgb'||match[1]==='rgba'){
          const vals=p.slice(0,3).map(x=>parseFloat(x)*(x.endsWith('%')?.01:1/255));return vals.length===3&&vals.every(Number.isFinite)?color(...vals,a):null;
        }
        if(match[1]==='oklch'||match[1]==='oklab'){
          const L=parseFloat(p[0])*(p[0]?.endsWith('%')?.01:1),C=parseFloat(p[1])*(p[1]?.endsWith('%')?.004:1),third=match[1]==='oklch'?angle(p[2]||'nan'):parseFloat(p[2])*(p[2]?.endsWith('%')?.004:1);
          if(![L,C,third].every(Number.isFinite))return null;
          return rgb(match[1]==='oklch'?{l:L,c:Math.max(0,C),h:third,a}:{l:L,c:Math.hypot(C,third),h:Math.atan2(third,C)*180/Math.PI,a});
        }
        const space=p.shift(),v=p.map(Number);if(v.length!==3||!v.every(Number.isFinite))return null;
        if(space==='srgb')return color(...v,a);if(space==='srgb-linear')return color(...v.map(encoded),a);
        if(space==='display-p3'){
          const [r,g,b]=v.map(linear);return color(encoded(1.2249401763*r-.2249401763*g),encoded(-.0420569547*r+1.0420569547*g),encoded(-.0196375546*r-.0786360456*g+1.0982736002*b),a);
        }
        return null;
      }
      const composite=(fg,bg)=>color(...fg.rgb.map((x,i)=>x*fg.a+bg.rgb[i]*(1-fg.a)),1);
      const luminance=c=>c.rgb.map(x=>linear(clamp(x))).reduce((n,x,i)=>n+x*[.2126,.7152,.0722][i],0);
      const contrast=(a,b)=>{const x=luminance(a),y=luminance(b);return(Math.max(x,y)+.05)/(Math.min(x,y)+.05);};
      const css=c=>`rgba(${c.rgb.map(x=>Math.round(clamp(x)*255)).join(', ')}, ${Math.round(c.a*1000)/1000})`;
      const distance=(a,b)=>Math.min(Math.abs(a-b)%360,360-Math.abs(a-b)%360);
      const bump=(h,center,width)=>Math.exp(-.5*(distance(h,center)/width)**2);
      const envelope=h=>clamp(.89-.30*bump(h,95,25)-.10*bump(h,45,25)-.06*bump(h,150,30)+.06*bump(h,260,35),.5,.96);
      function solve(c,bg,minimum) {
        c={...c,a:1};let mapped=gamut(c);if(contrast(mapped,bg)>=minimum)return mapped;
        // Prefer the current polarity; switch only if its endpoint cannot meet contrast.
        let end=lch(bg).l<.58?1:0;
        if(contrast(gamut({...c,l:end}),bg)<minimum)end=1-end;
        let lo=0,hi=1;for(let i=0;i<24;i++){const t=(lo+hi)/2,result=gamut({...c,l:c.l+(end-c.l)*t});if(contrast(result,bg)>=minimum)hi=t;else lo=t;}
        return gamut({...c,l:c.l+(end-c.l)*hi});
      }
      const canvas=color(28/255,28/255,28/255);
      function adapt(source,role,background=canvas,context={}) {
        const c=lch(source),neutral=c.c<.025,area=clamp(context.area||0),depth=clamp(context.depth||0,0,4);
        if(role==='canvas')return canvas;
        const factor=envelope(c.h)*(1-.30*Math.sqrt(area));let L,C=c.c*factor;
        if(role==='surface'){
          if(neutral){const v=[28,34,40,48,56][depth]/255;return color(v,v,v,source.a);}
          L=.28+.025*depth;C*=.55;
        }else if(role==='accent-fill'){L=.54+.04*clamp(c.l);C*=.9;}
        else if(role==='border'){L=.35+.1*clamp(context.strength||0);C*=.45;}
        else if(role==='shadow'){L=.13;C*=.2;}
        else{
          const original=Number.isFinite(context.originalContrast)?context.originalContrast:7;
          L=context.disabled?.60:context.heading?.95:original>=10?.89:original>=5?.84:original>=3?.75:.69;
          if(!neutral)L=Math.max(L,.76+.035*bump(c.h,260,35));
          let result=solve({l:L,c:C,h:c.h,a:1},background,context.disabled?3:context.large?3:4.5);
          // Eight-bit rounding may reduce a borderline ratio: solve with a small margin.
          if(contrast(parse(css(result)),background)<(context.disabled||context.large?3:4.5))result=solve({l:L,c:C,h:c.h,a:1},background,(context.disabled||context.large?3:4.5)+.05);
          return result;
        }
        return gamut({l:L,c:C,h:c.h,a:source.a});
      }
      globalThis.__locusNightMath=Object.freeze({parse,lch,rgb,gamut,css,contrast,composite,adapt,envelope,canvas});
    })();
    """#
}
