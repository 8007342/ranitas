// Pure-function tests for web/ambience.js: thunder scheduling and the species
// presence parser. Run with `npm run test:ambience` (node --test). No
// AudioContext is created; the script only needs a window and a document.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, '..', 'web', 'ambience.js'), 'utf8');

function load() {
  const listeners = [];
  const window = { addEventListener: (...a) => listeners.push(a), removeEventListener() {} };
  const document = { hidden: false, addEventListener() {}, removeEventListener() {} };
  new Function('window', 'document', source)(window, document);
  return window.ranitasAudio;
}

const audio = load();
const { thunderPlan, parseSpecies, thunderLimits: L } = audio;

// A deterministic draw sequence for `rnd`.
const draws = (...values) => { let i = 0; return () => values[i++ % values.length]; };

test('ten-second master fade and three-minute staggered orchestration', () => {
  assert.ok(Object.values(audio.soundLayers(0)).every(v => v === 0));
  assert.equal(audio.soundLayers(5).master, 0.5);
  assert.equal(audio.soundLayers(10).master, 1);
  assert.equal(audio.soundLayers(10).insects, 0);
  assert.equal(audio.soundLayers(50).frogs, 0);
  assert.equal(audio.soundLayers(100).distant, 0);
  assert.ok(audio.soundLayers(150).distant < 1);
  assert.ok(Object.values(audio.soundLayers(180)).every(v => v === 1));
  for (let t = 0; t < 240; t += .1) {
    const a = audio.soundLayers(t), b = audio.soundLayers(t + .1);
    for (const key of Object.keys(a)) {
      assert.ok(b[key] >= a[key] && b[key] <= 1);
      assert.ok(b[key] - a[key] < .019, 'no abrupt entrance');
    }
  }
});

test('below the downpour threshold thunder stays a distant rumble', () => {
  for (const rain of [0, 0.3, 0.6, 0.74]) {
    const plan = thunderPlan(rain, 100, -Infinity, draws(0, 0.5));
    assert.equal(plan.kind, 'distant');
    assert.equal(plan.gain, 0.18);
    assert.equal(plan.duration, 3.5);
    assert.equal(plan.cutoff, 180);
  }
});

test('a downpour allows a heavy rumble that is brief, low-passed and capped', () => {
  const plan = thunderPlan(0.9, 100, -Infinity, draws(0.1, 0.5));
  assert.equal(plan.kind, 'heavy');
  assert.ok(plan.gain <= L.HEAVY_GAIN && plan.gain <= 0.26, 'gain capped at a croak syllable');
  assert.ok(plan.duration <= 1.6, 'brief');
  assert.ok(plan.attack <= 0.05, 'short attack');
  assert.ok(plan.cutoff <= 300, 'still low-passed');
});

test('heavy rumbles never repeat within sixty seconds', () => {
  const first = thunderPlan(1, 100, -Infinity, draws(0, 0.5));
  assert.equal(first.kind, 'heavy');
  for (const later of [100, 120, 159.9]) {
    assert.equal(thunderPlan(1, later, 100, draws(0, 0.5)).kind, 'distant');
  }
  assert.equal(thunderPlan(1, 160, 100, draws(0, 0.5)).kind, 'heavy');
});

test('lulls return to distant rumbles even right after a heavy one was allowed', () => {
  assert.equal(thunderPlan(0.2, 400, 100, draws(0, 0.5)).kind, 'distant');
});

test('heavy chance grows with intensity but never becomes certain', () => {
  // At the threshold a roll of 0.36 misses; in a full downpour it hits.
  assert.equal(thunderPlan(0.75, 0, -Infinity, draws(0.36, 0.5)).kind, 'distant');
  assert.equal(thunderPlan(1.0, 0, -Infinity, draws(0.36, 0.5)).kind, 'heavy');
  assert.equal(thunderPlan(1.0, 0, -Infinity, draws(0.76, 0.5)).kind, 'distant');
});

test('every plan keeps the 22–45 s scheduling interval', () => {
  for (const [rain, roll, u] of [[0, 0.5, 0], [1, 0, 1], [0.8, 0.99, 0.5]]) {
    const plan = thunderPlan(rain, 50, -Infinity, draws(roll, u));
    assert.ok(plan.nextAt - 50 >= 22 - 1e-9 && plan.nextAt - 50 <= 45 + 1e-9);
  }
});

test('the plan is a pure function of its inputs', () => {
  const a = thunderPlan(0.85, 10, -Infinity, draws(0.2, 0.3));
  const b = thunderPlan(0.85, 10, -Infinity, draws(0.2, 0.3));
  assert.deepEqual(a, b);
});

test('species presence parses compactly and ignores junk', () => {
  assert.deepEqual(parseSpecies('cricket:3,bee:1'), { cricket: 3, bee: 1 });
  assert.deepEqual(parseSpecies(''), {});
  assert.deepEqual(parseSpecies(undefined), {});
  assert.deepEqual(parseSpecies('cicada:x,katydid:2,:4,__proto__:1'), { katydid: 2 });
  assert.deepEqual(parseSpecies('bee:99'), { bee: 32 });
});

test('update accepts the old four-argument form', () => {
  assert.doesNotThrow(() => audio.update(0.5, 0.5, 'storm', false));
  assert.doesNotThrow(() => audio.update(0.5, 0.5, 'storm', false, 0.9, 'cricket:2'));
});
