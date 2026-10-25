// Retain existing carefully keyed lights as editable sources, and manually
// isolate the stars on all five star-bearing scenes without a sky halo.
import sharp from 'sharp';
import {existsSync} from 'node:fs';
const size={width:1376,height:768};
for(const name of ['grotto','crystal-grotto','sanctuary','jade-sanctuary','dusk','firefly']) {
  const path=`art/source/emissive-pond-${name}.png`;
  if(!existsSync(path))await sharp(`assets/images/emissive-pond-${name}.webp`)
    .resize(size.width,size.height,{kernel:'nearest'}).png().toFile(path);
}
const stars={dusk:[[435,35]],firefly:[[435,35]],blossom:[[253,65],[350,62]],lotus:[[253,65],[350,62]],alpine:[[408,34]]};
for(const name of ['dusk','firefly','blossom','lotus','alpine','maple','mist','autumn-mist']) {
  const rgb=await sharp(`art/source/pond-${name}.png`).removeAlpha().raw().toBuffer();
  const mask=name==='firefly'
    ? await sharp('art/source/emissive-pond-firefly.png').ensureAlpha().raw().toBuffer()
    : Buffer.alloc(size.width*size.height*4);
  for(const [cx,cy] of stars[name]??[]) {
    const sx=Math.round(cx/641*size.width),sy=Math.round(cy/359*size.height);
    const ring=[];
    for(let y=sy-14;y<=sy+14;y++)for(let x=sx-14;x<=sx+14;x++) {
      if(Math.abs(y-sy)<10&&Math.abs(x-sx)<10)continue;
      const i=(y*size.width+x)*3;
      ring.push(.2126*rgb[i]+.7152*rgb[i+1]+.0722*rgb[i+2]);
    }
    ring.sort((a,b)=>a-b);
    const background=ring[Math.floor(ring.length/2)];
    // Remove the old dilated halo, which carried sky into the additive pass.
    for(let y=sy-28;y<=sy+28;y++)for(let x=sx-28;x<=sx+28;x++)mask.fill(0,(y*size.width+x)*4,(y*size.width+x)*4+4);
    for(let y=sy-8;y<=sy+8;y++)for(let x=sx-8;x<=sx+8;x++) {
      const i=y*size.width+x;
      const r=rgb[i*3],g=rgb[i*3+1],b=rgb[i*3+2];
      // Local hand-selected bounds exclude blossoms, snow and sky dithering.
      const luma=.2126*r+.7152*g+.0722*b;
      if(Math.min(r,g,b)<180||luma<225||luma<background+24)continue;
      mask[i*4]=mask[i*4+1]=mask[i*4+2]=255;
      mask[i*4+3]=Math.round(Math.min(255,(luma-background-24)*4));
    }
  }
  await sharp(mask,{raw:{...size,channels:4}}).png()
    .toFile(`art/source/emissive-pond-${name}.png`);
}
