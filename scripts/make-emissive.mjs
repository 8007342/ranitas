// Generates first-pass emissive masks for the painted backdrops
// (art/ASSET_REQUESTS.md §5, design D3): alpha = light. A painted mask with the
// same filename replaces the generated one.
//
//   node scripts/make-emissive.mjs [--preview <dir>] [--only <stem,...>] [--all]
//
// Keying: a pixel emits when it is bright and stands out from its blurred
// surroundings (so smooth sunset skies are ignored) and is either saturated in
// a light hue (amber lanterns, cyan or violet fungi) or near-white (moon,
// stars, lit windows). Blue sky and green foliage hues never emit. Blobs larger
// than `maxBlob` are dropped (snow caps, sky patches), and the mask is dilated
// one pixel and softened for a halo. Backdrops whose mask covers too little of
// the frame are skipped, so plain grading is their fallback.
//
// Only the backdrops in `candidates` are processed by default: on the others
// (blossom, lotus, maple, mist, alpine, autumn-mist) the key picks up petals,
// sun glitter and dithered sky rather than lights, as checked by eye on the
// previews. Pass `--all` to regenerate every backdrop for a new inspection.
import sharp from 'sharp';
import {existsSync, mkdirSync, readdirSync, statSync} from 'node:fs';

const args = process.argv.slice(2);
const previewDir = args.includes('--preview')
  ? args[args.indexOf('--preview') + 1]
  : null;
const only = args.includes('--only')
  ? new Set(args[args.indexOf('--only') + 1].split(','))
  : null;
const all = args.includes('--all');
const candidates = new Set([
  'pond-grotto',
  'pond-crystal-grotto',
  'pond-sanctuary',
  'pond-jade-sanctuary',
  'pond-dusk',
  'pond-firefly',
]);

const artDir = 'art/source';
const outDir = 'assets/images';
// Matches the whole-number scenic export (2 × 1376 × 768).
const OUT_W = 2752;
const OUT_H = 1536;

// Tuning (per source pixel at 1376 × 768).
const T = {
  blurSigma: 9, // local-background radius
  minLuma: 0.52, // nothing darker emits
  minContrast: 0.16, // luma above local background
  saturated: 0.42, // HSV saturation for coloured lights
  whiteLuma: 0.86, // near-white lights (moon, stars, windows)
  whiteSat: 0.28,
  minColouredContrast: 0.04, // coloured lights fill their own blur radius
  maxBlob: 2600, // px; larger white blobs are scenery, not lights
  maxColouredBlob: 16000, // px; a fungus cluster or a lit lantern with its sill
  minBlob: 3, // px; one or two dithered pixels are noise
  minCoverage: 0.0006, // of frame area; below it the mask is skipped
};

function luma(r, g, b) {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}
function saturation(r, g, b) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  return max === 0 ? 0 : (max - min) / max;
}
function hue(r, g, b) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  if (d === 0) return 0;
  let h;
  if (max === r) h = ((g - b) / d) % 6;
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return ((h * 60) + 360) % 360;
}
// Light hues: amber/yellow lanterns, cyan fungi and crystals, violet/magenta
// fungi. Greens (foliage, 70–160°) and sky blues (200–262°) are excluded.
function lightHue(h) {
  return (h >= 20 && h < 70) || (h >= 160 && h < 200) || (h >= 262 && h < 340);
}

async function makeMask(name) {
  const path = `${artDir}/${name}`;
  const image = sharp(path).removeAlpha();
  const {width, height} = await image.metadata();
  const rgb = await image.clone().raw().toBuffer();
  const blurred = await image
    .clone()
    .greyscale()
    .blur(T.blurSigma)
    .raw()
    .toBuffer();
  const n = width * height;
  const raw = new Float32Array(n);
  const isColoured = new Uint8Array(n);
  for (let i = 0; i < n; i++) {
    const r = rgb[i * 3];
    const g = rgb[i * 3 + 1];
    const b = rgb[i * 3 + 2];
    const l = luma(r, g, b);
    if (l < T.minLuma) continue;
    const contrast = l - blurred[i] / 255;
    const s = saturation(r, g, b);
    const coloured = s >= T.saturated && lightHue(hue(r, g, b));
    // A coloured light fills its own blur radius (a fungus cap, a lantern
    // window), so it needs less contrast against the local background.
    if (contrast < (coloured ? T.minColouredContrast : T.minContrast)) {
      continue;
    }
    const white = l >= T.whiteLuma && s <= T.whiteSat;
    if (!coloured && !white) continue;
    const byContrast = Math.min(1, (contrast - T.minContrast) / 0.22);
    const byLuma = Math.min(1, (l - T.minLuma) / 0.3);
    raw[i] = Math.min(1, 0.35 + 0.65 * Math.max(coloured ? .6 : 0, byContrast) * byLuma);
    isColoured[i] = coloured ? 1 : 0;
  }

  // Connected components (4-neighbour) to drop large and tiny blobs.
  const label = new Int32Array(n);
  const stack = new Int32Array(n);
  let kept = 0;
  for (let start = 0; start < n; start++) {
    if (raw[start] === 0 || label[start] !== 0) continue;
    let top = 0;
    stack[top++] = start;
    label[start] = 1;
    const members = [];
    while (top > 0) {
      const i = stack[--top];
      members.push(i);
      const x = i % width;
      if (x > 0 && raw[i - 1] > 0 && label[i - 1] === 0) {
        label[i - 1] = 1;
        stack[top++] = i - 1;
      }
      if (x < width - 1 && raw[i + 1] > 0 && label[i + 1] === 0) {
        label[i + 1] = 1;
        stack[top++] = i + 1;
      }
      if (i >= width && raw[i - width] > 0 && label[i - width] === 0) {
        label[i - width] = 1;
        stack[top++] = i - width;
      }
      if (i + width < n && raw[i + width] > 0 && label[i + width] === 0) {
        label[i + width] = 1;
        stack[top++] = i + width;
      }
    }
    // Coloured blobs (fungi clusters, lantern windows with their lit sills)
    // may be large; only white blobs (snow, sky patches) are capped tightly.
    let colouredMembers = 0;
    for (const i of members) colouredMembers += isColoured[i];
    const maxBlob =
      colouredMembers * 2 >= members.length ? T.maxColouredBlob : T.maxBlob;
    if (members.length > maxBlob || members.length < T.minBlob) {
      for (const i of members) raw[i] = 0;
    } else {
      kept += members.length;
    }
  }
  const coverage = kept / n;

  // One-pixel dilation, then a soft halo.
  const dilated = new Uint8Array(n);
  for (let i = 0; i < n; i++) {
    let v = raw[i];
    const x = i % width;
    if (x > 0) v = Math.max(v, raw[i - 1] * 0.7);
    if (x < width - 1) v = Math.max(v, raw[i + 1] * 0.7);
    if (i >= width) v = Math.max(v, raw[i - width] * 0.7);
    if (i + width < n) v = Math.max(v, raw[i + width] * 0.7);
    dilated[i] = Math.round(v * 255);
  }
  const soft = await sharp(Buffer.from(dilated), {
    raw: {width, height, channels: 1},
  })
    .blur(0.8)
    .raw()
    .toBuffer();

  // RGBA: white under a light alpha; black under zero so lossless packs well.
  const rgba = Buffer.alloc(n * 4);
  for (let i = 0; i < n; i++) {
    const a = soft[i];
    rgba[i * 4] = a ? 255 : 0;
    rgba[i * 4 + 1] = a ? 255 : 0;
    rgba[i * 4 + 2] = a ? 255 : 0;
    rgba[i * 4 + 3] = a;
  }
  return {width, height, rgba, coverage};
}

mkdirSync(outDir, {recursive: true});
if (previewDir) mkdirSync(previewDir, {recursive: true});

const names = readdirSync(artDir)
  .filter((f) => /^pond-.*\.png$/.test(f) && !f.endsWith('-sheet.png'))
  .filter((f) => only ? only.has(f.replace('.png', '')) : all || candidates.has(f.replace('.png', '')));

for (const name of names) {
  const stem = name.replace('.png', '');
  const {width, height, rgba, coverage} = await makeMask(name);
  const out = `${outDir}/emissive-${stem}.webp`;
  const pct = (coverage * 100).toFixed(3);
  if (coverage < T.minCoverage) {
    console.log(`${stem}: ${pct}% lit — too little, no mask (plain grading)`);
    if (previewDir) await preview(name, stem, width, height, rgba);
    continue;
  }
  await sharp(rgba, {raw: {width, height, channels: 4}})
    .resize(OUT_W, OUT_H, {fit: 'cover', kernel: 'nearest'})
    .webp({lossless: true, effort: 6})
    .toFile(out);
  const kb = (statSync(out).size / 1024).toFixed(0);
  console.log(`${out} ${OUT_W} × ${OUT_H}, ${pct}% lit, ${kb} KB`);
  if (previewDir) await preview(name, stem, width, height, rgba);
}

// Side-by-side preview: source | source dimmed with the mask lit, at half size.
async function preview(name, stem, width, height, rgba) {
  const src = await sharp(`${artDir}/${name}`).removeAlpha().raw().toBuffer();
  const n = width * height;
  const lit = Buffer.alloc(n * 3);
  for (let i = 0; i < n; i++) {
    const a = rgba[i * 4 + 3] / 255;
    for (let c = 0; c < 3; c++) {
      const v = src[i * 3 + c];
      lit[i * 3 + c] = Math.min(255, Math.round(v * 0.3 + v * a * 0.9));
    }
  }
  const half = {width: Math.floor(width / 2), height: Math.floor(height / 2)};
  const left = await sharp(src, {raw: {width, height, channels: 3}})
    .resize(half.width, half.height)
    .png()
    .toBuffer();
  const right = await sharp(lit, {raw: {width, height, channels: 3}})
    .resize(half.width, half.height)
    .png()
    .toBuffer();
  await sharp({
    create: {
      width: half.width * 2,
      height: half.height,
      channels: 3,
      background: {r: 0, g: 0, b: 0},
    },
  })
    .composite([
      {input: left, left: 0, top: 0},
      {input: right, left: half.width, top: 0},
    ])
    .png()
    .toFile(`${previewDir}/${stem}.png`);
}

if (!existsSync(outDir)) process.exit(1);
