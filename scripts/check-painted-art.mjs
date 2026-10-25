import sharp from 'sharp';
import {readdirSync} from 'node:fs';
import assert from 'node:assert/strict';
const biomes=['willow','blossom','cypress','maple','sanctuary','grotto','alpine','lotus','firefly','autumn-mist','jade-sanctuary','crystal-grotto'];
let count=0;
async function check(name,w,h) {
  const {data,info}=await sharp(`art/source/${name}.png`).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  assert.equal(info.width,w,name);assert.equal(info.height,h,name);
  const exported=await sharp(`assets/images/${name}.webp`).metadata();
  const fixed=/^(frog-|foliage-|branches-|cycle-)/.test(name);
  assert.equal(exported.width,fixed?w:w*2,name);
  assert.equal(exported.height,fixed?h:h*2,name);
  for(let y=0;y<h;y++)for(let x=0;x<w;x++) {
    const i=(y*w+x)*4,a=data[i+3];
    if(name.startsWith('cycle-')) {
      assert.equal(data[i]%16,0,name);assert(data[i]<=240,name);
      assert.equal(data[i],data[i+1],name);assert.equal(data[i],data[i+2],name);
      continue;
    }
    if(name.startsWith('emissive-'))continue;
    assert(a===0||a===255,`${name}: soft alpha`);
    if(a===0)assert.equal(data[i]+data[i+1]+data[i+2],0,`${name}: hidden RGB`);
    if(name.startsWith('canopy-')&&x>=344&&x<1032&&y>=230)assert.equal(a,0,`${name}: jump lane`);
    if(name.startsWith('foreground-')&&(y<512||(x>=344&&x<1032)))assert.equal(a,0,`${name}: foreground lane`);
  }
  count++;
}
for(const biome of biomes) {
  for(const [kind,w,h] of [['canopy',1376,384],['midbank',1376,768],['foreground',1376,768],['foliage',256,128],['branches',576,32]])await check(`${kind}-${biome}`,w,h);
}
for(const frog of ['meadow','teal'])for(const depth of ['', '-depth'])await check(`frog-${frog}${depth}-sheet`,1031,521);
for(const name of readdirSync('art/source')) {
  if(name.startsWith('cycle-'))await check(name.slice(0,-4),641,359);
  if(name.startsWith('emissive-'))await check(name.slice(0,-4),1376,768);
}
console.log(`${count} painted/data assets: dimensions, exports, alpha, clear lanes and cycle slots valid.`);
