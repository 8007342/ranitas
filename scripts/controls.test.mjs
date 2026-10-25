import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../web/controls.js',import.meta.url),'utf8');
function setup(){
  let handler, exits=0, location, disposed=0;
  const document={fullscreenElement:{},exitFullscreen(){exits++;}};
  const window={addEventListener(type,h,capture){assert.equal(capture,true);handler=h;},
    location:{href:'https://pond.test/?seed=1&duration=10&keep=yes',replace(url){location=url;}},
    ranitasAudio:{dispose(){disposed++;}}};
  new Function('window','document',source)(window,document);
  return {key(key,extra={}){handler({key,preventDefault(){},...extra});},
    get exits(){return exits;},get location(){return location;},get disposed(){return disposed;}};
}
test('Escape and F exit page fullscreen even with Flutter focused',()=>{
  const s=setup();s.key('Escape');s.key('f');s.key('F');assert.equal(s.exits,3);
});
test('R disposes sound and reloads without a pinned seed or preview duration',()=>{
  const s=setup();s.key('r');const url=new URL(s.location);
  assert.equal(url.searchParams.has('seed'),false);
  assert.equal(url.searchParams.has('duration'),false);
  assert.equal(url.searchParams.get('keep'),'yes');assert.equal(s.disposed,1);
});
test('shortcuts ignore held keys, text fields and browser modifier shortcuts',()=>{
  const s=setup();for(const extra of [{repeat:true},{ctrlKey:true},{metaKey:true},
    {altKey:true},{isComposing:true},{target:{tagName:'INPUT'}},{target:{isContentEditable:true}}])s.key('r',extra);
  assert.equal(s.location,undefined);assert.equal(s.disposed,0);
});
