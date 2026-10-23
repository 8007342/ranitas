import sharp from 'sharp';
import {readdirSync, mkdirSync} from 'node:fs';
mkdirSync('assets/images', {recursive: true});
for (const name of readdirSync('art/source').filter(n => n.endsWith('.png'))) {
  const output = `assets/images/${name.replace('.png', '.webp')}`;
  const isSpriteSheet = name.endsWith('-sheet.png');
  const width = isSpriteSheet ? 1031 : 2557;
  const height = isSpriteSheet ? 521 : 1439;
  const fit = isSpriteSheet ? 'contain' : 'cover';
  await sharp(`art/source/${name}`)
    .resize(width, height, {
      fit,
      kernel: 'nearest',
      background: {r: 0, g: 0, b: 0, alpha: 0},
    })
    .webp({lossless: true, effort: 6})
    .toFile(output);
  console.log(output, `${width} × ${height} (both prime), lossless WebP`);
}
