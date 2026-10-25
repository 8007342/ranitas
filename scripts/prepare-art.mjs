import sharp from 'sharp';
import {readdirSync, mkdirSync} from 'node:fs';
mkdirSync('assets/images', {recursive: true});
// Scenic art is exported at a whole-number multiple of its source so every
// source pixel becomes an exact SCALE × SCALE block; a non-integer resample
// here would bake uneven pixel widths into the files (docs/visual-envelope.md).
const SCALE = 2;
for (const name of readdirSync('art/source').filter(n => n.endsWith('.png'))) {
  const output = `assets/images/${name.replace('.png', '.webp')}`;
  const isSpriteSheet = name.endsWith('-sheet.png');
  const fixedGrid = /^(foliage-|branches-|cycle-)/.test(name);
  const source = sharp(`art/source/${name}`);
  const {width: srcW, height: srcH} = await source.metadata();
  // Sprite sheets keep their 1031 × 521 atlas size (sources already match).
  const width = isSpriteSheet ? 1031 : fixedGrid ? srcW : srcW * SCALE;
  const height = isSpriteSheet ? 521 : fixedGrid ? srcH : srcH * SCALE;
  await source
    .resize(width, height, {
      fit: isSpriteSheet ? 'contain' : 'fill',
      kernel: 'nearest',
      background: {r: 0, g: 0, b: 0, alpha: 0},
    })
    .webp({lossless: true, effort: 6})
    .toFile(output);
  console.log(output, `${width} × ${height}, lossless WebP`);
}
