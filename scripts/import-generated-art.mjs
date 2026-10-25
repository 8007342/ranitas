// Normalize imagegen outputs to the game's exact raster contracts.
// Usage: node scripts/import-generated-art.mjs <manifest.json>
// Manifest: [{name, path, prompt}]. No API calls; nearest-neighbour only.
import sharp from 'sharp';
import {readFileSync, writeFileSync} from 'node:fs';

const jobs = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const transparent = {r: 0, g: 0, b: 0, alpha: 0};
const palette = {
  meadow: ['143534','3d7a52','6db364','a8db74','cde88b','f4eec1','e6d88a','ee8468','e58f8e','ffeaad','8f3247','e87a90'],
  teal: ['13303a','2e6b72','4ea69a','89d6be','b6ebd4','efe8bd','d6e5b8','e29578','d995a8','ffe39f','8f3247','e87a90'],
};

function hardAlpha(data, colors) {
  const rgb = colors?.map(c => [0,2,4].map(i => parseInt(c.slice(i,i+2),16)));
  for(let i=0;i<data.length;i+=4) {
    if(data[i+3]<128) {data.fill(0,i,i+4);continue;}
    data[i+3]=255;
    if(rgb) {
      const nearest=rgb.reduce((best,c)=>{
        const d=c.reduce((sum,v,k)=>sum+(v-data[i+k])**2,0);
        return d<best.d?{d,c}:best;
      },{d:Infinity});
      nearest.c.forEach((v,k)=>data[i+k]=v);
    }
  }
  return data;
}

async function grid(input,w,h,colors) {
  const data=await sharp(input).ensureAlpha().resize(w,h,{fit:'fill',kernel:'nearest'}).raw().toBuffer();
  return sharp(hardAlpha(data,colors),{raw:{width:w,height:h,channels:4}}).png().toBuffer();
}

async function atlas(path,columns,rows,cellW,cellH,name) {
  const {data,info}=await sharp(path).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  const bands=[];let start=-1;
  for(let y=0;y<=info.height;y++) {
    let count=0;
    if(y<info.height)for(let x=0;x<info.width;x++)if(data[(y*info.width+x)*4+3]>=128)count++;
    if(count>info.width*.003) {if(start<0)start=y;}
    else if(start>=0) {if(y-start>3)bands.push([start,y]);start=-1;}
  }
  // A generative atlas often has unequal row padding. Isolate each row before
  // packing cells so large leaves never bleed into their small flip frames.
  const rowBounds=bands.length===rows?bands:Array.from({length:rows},(_,r)=>[Math.round(r*info.height/rows),Math.round((r+1)*info.height/rows)]);
  const cells=[];
  for(let row=0;row<rows;row++)for(let col=0;col<columns;col++) {
    const left=Math.round(col*info.width/columns),[top,bottom]=rowBounds[row];
    let sprite=await sharp(path).extract({left,top,width:Math.round((col+1)*info.width/columns)-left,height:bottom-top}).png().toBuffer();
    sprite=await sharp(sprite).trim({background:transparent,threshold:8}).png().toBuffer();
    const branch=name.startsWith('branches-');
    const targetW=branch?cellW:row%2===1?9:15;
    const targetH=branch?Math.max(2,4-Math.floor(col/2)):row%2===1?9:15;
    sprite=await sharp(sprite).resize(targetW,targetH,{fit:branch?'fill':'inside',kernel:'nearest'}).png().toBuffer();
    const meta=await sharp(sprite).metadata();
    const hanging=!branch&&(/willow|cypress|firefly/.test(name)&&col<4||name==='foliage-lotus'&&col>=4);
    cells.push({input:sprite,left:col*cellW+Math.floor((cellW-meta.width)/2),top:row*cellH+(hanging?0:Math.floor((cellH-meta.height)/2))});
  }
  const packed=await sharp({create:{width:columns*cellW,height:rows*cellH,channels:4,background:transparent}}).composite(cells).png().toBuffer();
  return grid(packed,columns*cellW,rows*cellH);
}

for(const {name,path} of jobs) {
  let output;
  if(name.startsWith('frog-')) {
    const {width,height}=await sharp(path).metadata();
    const cells=[];
    for(let row=0;row<2;row++)for(let col=0;col<4;col++) {
      const left=Math.round(col*width/4), top=Math.round(row*height/2);
      const cell=await sharp(path).extract({left,top,width:Math.round((col+1)*width/4)-left,height:Math.round((row+1)*height/2)-top}).png().toBuffer();
      const logical=await grid(cell,42,36,palette[name.includes('meadow')?'meadow':'teal']);
      const enlarged=await sharp(logical).resize(252,216,{kernel:'nearest'}).png().toBuffer();
      cells.push({input:enlarged,left:Math.round(col*1031/4)+3,top:Math.round(row*521/2)+22});
    }
    output=await sharp({create:{width:1031,height:521,channels:4,background:transparent}}).composite(cells).png().toBuffer();
  } else if(name.startsWith('foliage-')) {
    output=await atlas(path,8,4,16,16,name);
    output=await sharp(output).resize(256,128,{kernel:'nearest'}).png().toBuffer();
  } else if(name.startsWith('branches-')) {
    output=await atlas(path,6,1,48,16,name);
    output=await sharp(output).resize(576,32,{kernel:'nearest'}).png().toBuffer();
  } else {
    const canopy=name.startsWith('canopy-');
    const w=688,h=canopy?192:384;
    const raw=await sharp(path).ensureAlpha().resize(w,h,{fit:'fill',kernel:'nearest'}).raw().toBuffer();
    hardAlpha(raw);
    for(let y=0;y<h;y++)for(let x=0;x<w;x++) {
      // Enforce the clear jump lane and corner framing, including alpha RGB.
      const clear=canopy ? (x>=172&&x<516&&y>=115)
        : name.startsWith('foreground-') ? (y<256||(x>=172&&x<516))
        : (x>=172&&x<516&&y>=210);
      if(clear)raw.fill(0,(y*w+x)*4,(y*w+x)*4+4);
    }
    output=await sharp(raw,{raw:{width:w,height:h,channels:4}}).resize(1376,canopy?384:768,{kernel:'nearest'}).png().toBuffer();
  }
  writeFileSync(`art/source/${name}.png`,output);
  console.log(name);
}
