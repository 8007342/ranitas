import sharp from 'sharp';
import {readdirSync, mkdirSync} from 'node:fs';
mkdirSync('assets/images',{recursive:true});
for(const name of readdirSync('art/source').filter(n=>n.endsWith('.png'))) {
 const output=`assets/images/${name.replace('.png','.webp')}`;
 await sharp(`art/source/${name}`).resize(1031,1543,{fit:'cover',kernel:'nearest'}).webp({lossless:true,effort:6}).toFile(output);
 console.log(output,'1031 × 1543 (both prime), lossless WebP');
}
