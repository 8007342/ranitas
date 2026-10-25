// Retain existing carefully keyed lights as editable sources, and manually
// isolate the stars on the three scenes where global colour keying fails.
import sharp from 'sharp';
import {existsSync} from 'node:fs';
const size={width:1376,height:768};
for(const name of ['grotto','crystal-grotto','sanctuary','jade-sanctuary','dusk','firefly']) {
  const path=`art/source/emissive-pond-${name}.png`;
  if(!existsSync(path))await sharp(`assets/images/emissive-pond-${name}.webp`)
    .resize(size.width,size.height,{kernel:'nearest'}).png().toFile(path);
}
const stars={blossom:[[253,65],[350,62]],lotus:[[253,65],[350,62]],alpine:[[408,34]]};
for(const name of ['blossom','lotus','alpine','maple','mist','autumn-mist']) {
  const rgb=await sharp(`art/source/pond-${name}.png`).removeAlpha().raw().toBuffer();
  const mask=Buffer.alloc(size.width*size.height*4);
  for(const [cx,cy] of stars[name]??[]) {
    const sx=Math.round(cx/641*size.width),sy=Math.round(cy/359*size.height);
    for(let y=sy-8;y<=sy+8;y++)for(let x=sx-8;x<=sx+8;x++) {
      const i=y*size.width+x;
      const r=rgb[i*3],g=rgb[i*3+1],b=rgb[i*3+2];
      // Local hand-selected bounds exclude blossoms, snow and sky dithering.
      if(Math.min(r,g,b)<150||Math.max(r,g,b)<210)continue;
      mask[i*4]=mask[i*4+1]=mask[i*4+2]=255;
      mask[i*4+3]=Math.max(r,g,b);
    }
  }
  await sharp(mask,{raw:{...size,channels:4}}).png()
    .toFile(`art/source/emissive-pond-${name}.png`);
}
