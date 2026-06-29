const vm = require('vm');
const REAL_IDS=new Set(require('./ids.json'));
const fs = require('fs');
const code = fs.readFileSync('check.js','utf8');

// permissive stub: any property access returns a callable/indexable proxy
function makeStub(name){
  const fn = function(){ return makeStub(name+'()'); };
  return new Proxy(fn, {
    get(t,p){ if(p==='toString')return ()=>name;
      if(p===Symbol.toPrimitive) return ()=>0;
      if(p==='classList') return {add(){},remove(){},toggle(){},contains(){return false;}};
      if(p==='style') return makeStub(name+'.style');
      if(p==='length') return 0;
      return makeStub(name+'.'+String(p)); },
    set(){ return true; },
    apply(){ return makeStub(name+'()'); },
    construct(){ return makeStub('new '+name); }
  });
}
const docStub = {
  getElementById:(id)=>(REAL_IDS.has(id)?makeStub('#'+id):null),
  querySelector:()=>makeStub('q'),
  querySelectorAll:()=>[],
  createElement:()=>makeStub('el'),
  addEventListener:()=>{},
  body:makeStub('body'),
  documentElement:makeStub('docEl')
};
const sandbox = {
  document:docStub,
  window:{},
  addEventListener:()=>{},
  requestAnimationFrame:()=>0,
  performance:{now:()=>0},
  localStorage:{getItem:()=>null,setItem:()=>{},removeItem:()=>{}},
  navigator:{clipboard:{writeText:()=>{}}},
  location:{href:'',search:''},
  console, Math, Date, JSON, Set, Map, Array, Object, parseInt, parseFloat,
  setInterval:()=>0, clearInterval:()=>{}, setTimeout:()=>0,
  Image:function(){ return makeStub('img'); },
  AudioContext:function(){ return makeStub('actx'); },
  fetch:()=>Promise.resolve({json:()=>({})}),
  encodeURIComponent:encodeURIComponent, decodeURIComponent:decodeURIComponent,
  atob:s=>s, btoa:s=>s, isNaN, prompt:()=>"", alert:()=>{}, URLSearchParams, URL, Promise, Proxy, Symbol, RegExp, Float32Array, Uint8Array
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
try{
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, {filename:'game.js'});
  console.log('TOP-LEVEL OK — no load-time throw');
}catch(e){
  console.log('THROW AT LOAD:', e.message);
  console.log(e.stack.split('\n').slice(0,3).join('\n'));
}

// now try to actually run the render + start paths
try{
  sandbox.state = undefined;
  if(sandbox.draw){ sandbox.draw(); console.log('draw()/drawTitleScene OK'); }
}catch(e){ console.log('THROW in draw():', e.message, '\n', e.stack.split('\n')[1]); }
try{
  if(sandbox.drawTitleScene){ sandbox.drawTitleScene(); console.log('drawTitleScene() OK'); }
}catch(e){ console.log('THROW in drawTitleScene():', e.message); }
try{
  if(sandbox.showAuth){ sandbox.showAuth(); console.log('showAuth() OK'); }
}catch(e){ console.log('THROW in showAuth():', e.message, '\n', e.stack.split('\n')[1]); }
try{
  if(sandbox.startMusic){ sandbox.startMusic('theme'); console.log('startMusic() OK'); }
}catch(e){ console.log('THROW in startMusic():', e.message); }
try{
  if(sandbox.showReg){ sandbox.showReg(); console.log('showReg() OK'); }
}catch(e){ console.log('THROW in showReg():', e.message, '\n', e.stack.split('\n')[1]); }
