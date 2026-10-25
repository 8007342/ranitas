/* Original procedural pond soundscape. Load before flutter_bootstrap.js. */
(() => {
  'use strict';
  if (window.ranitasAudio) return;
  const clamp = (value) => Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0;
  let context, master, noise, timer;
  let disposed = false, unlocked = false, started = false, suspended = false;
  let unlockPointer = null, unlockKey = null, gestureEnded = false;
  let unlockPending = false, unlockAttempt = 0;
  let state = { progress: 0, richness: 0, weather: 'clear', sleeping: false,
    rainIntensity: 0, species: {}, elapsedSeconds: 0 };
  const reveal = (seconds, start, end) => {
    const x = clamp((seconds - start) / (end - start));
    return clamp(x * x * x * (x * (x * 6 - 15) + 10));
  };
  // Volume fade and orchestration are separate. A full master at 10 s does
  // not imply a full soundscape: the last layers finish entering at 180 s.
  function soundLayers(seconds) {
    return { master: reveal(seconds, 0, 10), water: reveal(seconds, 0, 60),
      breeze: reveal(seconds, 20, 100), rain: reveal(seconds, 35, 170),
      insects: reveal(seconds, 50, 160), frogs: reveal(seconds, 70, 165),
      distant: reveal(seconds, 110, 180) };
  }
  const voices = new Set();
  const beds = [];
  const next = { cricket: 0, water: 0, frog: 0, owl: 0, thunder: 0,
    chorus: 0, katydid: 0, bee: 0, cicada: 0 };
  // Scheduling memory for the thunder plan: when the last heavy rumble fell.
  const thunderMemory = { heavyAt: -Infinity };
  const random = (a, b) => a + Math.random() * (b - a);
  const active = () => context && unlocked && !unlockPending && started && !suspended && !document.hidden && !disposed;

  // Thunder follows the rain intensity envelope (design D1). Pure: the same
  // inputs and the same `rnd` draws give the same plan, so it is testable
  // without an AudioContext (scripts/ambience.test.mjs).
  //
  //  - Distant rumble (the original voice): low-pass 180 Hz noise, 3.5 s,
  //    gain 0.18, every 22–45 s while the storm label is active.
  //  - Heavy rumble: allowed only while the rain is a downpour (intensity at
  //    or above HEAVY_RAIN), at most once per HEAVY_SPACING seconds, and
  //    brief: a 0.05 s attack into a 1.6 s decay, still low-passed (260 Hz),
  //    gain capped at HEAVY_GAIN, which is the level of one croak syllable.
  //    Lulls drop the rain under the threshold, so they return to distant
  //    rumbles on their own. Never any lightning or flash.
  const THUNDER = Object.freeze({
    HEAVY_RAIN: 0.75,
    HEAVY_SPACING: 60,
    HEAVY_GAIN: 0.26,
    HEAVY_DURATION: 1.6,
    HEAVY_ATTACK: 0.05,
    HEAVY_CUTOFF: 260,
    DISTANT_GAIN: 0.18,
    DISTANT_DURATION: 3.5,
    DISTANT_CUTOFF: 180,
    INTERVAL_MIN: 22,
    INTERVAL_MAX: 45,
  });
  function thunderPlan(rain, now, lastHeavyAt, rnd = Math.random) {
    const intensity = clamp(rain);
    const since = now - (Number.isFinite(lastHeavyAt) ? lastHeavyAt : -Infinity);
    const eligible = intensity >= THUNDER.HEAVY_RAIN && since >= THUNDER.HEAVY_SPACING;
    // Chance grows from 35 % at the threshold to 75 % in a full downpour.
    const chance = 0.35 + 0.4 * clamp((intensity - THUNDER.HEAVY_RAIN) / (1 - THUNDER.HEAVY_RAIN));
    const roll = rnd();
    const interval = THUNDER.INTERVAL_MIN + rnd() * (THUNDER.INTERVAL_MAX - THUNDER.INTERVAL_MIN);
    if (eligible && roll < chance) {
      return { kind: 'heavy', cutoff: THUNDER.HEAVY_CUTOFF, duration: THUNDER.HEAVY_DURATION,
        gain: THUNDER.HEAVY_GAIN, attack: THUNDER.HEAVY_ATTACK, nextAt: now + interval };
    }
    return { kind: 'distant', cutoff: THUNDER.DISTANT_CUTOFF, duration: THUNDER.DISTANT_DURATION,
      gain: THUNDER.DISTANT_GAIN, attack: 0.08, nextAt: now + interval };
  }

  // `cricket:3,bee:1` → { cricket: 3, bee: 1 }. Unknown or malformed entries
  // are dropped; counts are clamped to a small integer.
  function parseSpecies(text) {
    const out = {};
    if (typeof text !== 'string' || !text) return out;
    for (const part of text.split(',')) {
      const [name, count] = part.split(':');
      const n = Math.floor(Number(count));
      if (/^[a-z]+$/.test(name || '') && Number.isFinite(n) && n > 0) out[name] = Math.min(n, 32);
    }
    return out;
  }

  function smooth(param, value, seconds = 0.8) {
    const now = context.currentTime;
    param.cancelScheduledValues(now);
    param.setTargetAtTime(value, now, seconds);
  }

  function makeBed(type, frequency, q) {
    const source = context.createBufferSource();
    const filter = context.createBiquadFilter();
    const gain = context.createGain();
    source.buffer = noise;
    source.loop = true;
    filter.type = type;
    filter.frequency.value = frequency;
    filter.Q.value = q;
    gain.gain.value = 0;
    source.connect(filter).connect(gain).connect(master);
    source.start();
    beds.push({ source, filter, gain });
  }

  function construct() {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return false;
    context = new AudioContext();
    master = context.createGain();
    master.gain.value = 0;
    master.connect(context.destination);
    noise = context.createBuffer(1, context.sampleRate * 4, context.sampleRate);
    const data = noise.getChannelData(0);
    let brown = 0;
    for (let i = 0; i < data.length; i++) {
      brown = (brown + Math.random() * 0.04 - 0.02) / 1.02;
      data[i] = brown * 3 + (Math.random() * 2 - 1) * 0.25;
    }
    makeBed('lowpass', 550, 0.5); // wind
    makeBed('bandpass', 2200, 0.6); // leaves and reeds
    makeBed('highpass', 1600, 0.5); // rain
    return true;
  }

  function activationKey(event) {
    if (event.key === ' ' || event.code === 'Space') return 'Space';
    if (event.key === 'Enter' || event.code === 'Enter' || event.code === 'NumpadEnter') return 'Enter';
    return null;
  }

  function unlockFailed(attempt) {
    if (disposed || attempt !== unlockAttempt) return;
    // Keep scene state and the context, but require another real input gesture.
    unlockAttempt++;
    unlocked = false;
    unlockPending = false;
    started = false;
    gestureEnded = false;
    // Retain the matching input so its release can retry after a press rejection.
    stop();
  }

  // Each gesture-stack attempt supersedes older pending resume promises.
  function resumeFromGesture() {
    const attempt = ++unlockAttempt;
    unlockPending = true;
    unlocked = true;
    try {
      const promise = context.resume();
      Promise.resolve(promise).then(() => {
        if (disposed || attempt !== unlockAttempt) return;
        if (context.state !== 'running') { unlockFailed(attempt); return; }
        unlockPending = false;
        if (started) sync();
        else if (suspended || document.hidden) stop();
      }).catch(() => unlockFailed(attempt));
    } catch (_) { unlockFailed(attempt); }
  }

  // Resume inside the synchronous browser input stack, before Flutter handles it.
  let lastActionCroak = 0;
  function unlock(event) {
    const key = event.type === 'keydown' ? activationKey(event) : null;
    if (key === 'Space') event.preventDefault();
    if (event.isTrusted === false) return;
    if (event.type === 'keydown' && (!key || event.repeat || event.isComposing ||
        event.altKey || event.ctrlKey || event.metaKey)) return;
    if (disposed || document.hidden) return;
    if (unlocked && started && context && context.state === 'running') {
      const now = context.currentTime;
      if (now - lastActionCroak > 0.65 && !state.sleeping) {
        lastActionCroak = now;
        playCroak(random(0.95, 1.18));
      }
      return;
    }
    try {
      if (!context && !construct()) return;
      unlockPointer = key ? null : event.pointerId;
      unlockKey = key;
      gestureEnded = true;
      started = true;
      resumeFromGesture();
    } catch (_) { unlockFailed(unlockAttempt); }
  }
  function endGesture(event) {
    if (disposed || !context || event.isTrusted !== true) return;
    const matches = event.type === 'keyup'
      ? unlockKey !== null && activationKey(event) === unlockKey
      : unlockKey === null && unlockPointer !== null && event.pointerId === unlockPointer;
    if (!matches) return;
    if (event.type === 'pointercancel') {
      unlockPointer = null;
      unlockKey = null;
      gestureEnded = false;
      if (!started) {
        unlockAttempt++;
        unlocked = false;
        unlockPending = false;
        stop();
      }
      return;
    }
    if (document.hidden) return;
    gestureEnded = true;
    // Mobile browsers may grant activation only at release. Call synchronously
    // even if the press resume is still pending or has already been rejected.
    resumeFromGesture();
  }
  window.addEventListener('pointerdown', unlock, true);
  window.addEventListener('pointerup', endGesture, true);
  window.addEventListener('pointercancel', endGesture, true);
  window.addEventListener('keydown', unlock, true);
  window.addEventListener('keyup', endGesture, true);

  function clearVoices() {
    for (const voice of [...voices]) voice.finish();
  }

  // Each short voice owns every node it creates, with a hard concurrency limit.
  // `shape` (optional) refines the filter and envelope: { filter, cutoff, q,
  // attack, hold }. Noise voices default to a lowpass at `frequency`;
  // oscillators to a 6.5 kHz lowpass. `hold` keeps the voice at full level for
  // that share of its duration before the decay (insect drones).
  function voice(kind, frequency, duration, volume, sweep = frequency, delay = 0, shape = null) {
    if (!active() || context.state !== 'running' || voices.size >= 24) return;
    const source = kind === 'noise' ? context.createBufferSource() : context.createOscillator();
    const filter = context.createBiquadFilter();
    const gain = context.createGain();
    const pan = context.createStereoPanner ? context.createStereoPanner() : null;
    const at = context.currentTime + delay;
    if (kind === 'noise') source.buffer = noise;
    else {
      source.type = kind;
      source.frequency.setValueAtTime(frequency, at);
      source.frequency.exponentialRampToValueAtTime(Math.max(20, sweep), at + duration);
    }
    filter.type = (shape && shape.filter) || 'lowpass';
    filter.frequency.value = (shape && shape.cutoff) || (kind === 'noise' ? frequency : 6500);
    if (shape && shape.q) filter.Q.value = shape.q;
    const attack = shape && shape.attack
      ? Math.min(shape.attack, duration * 0.4) : Math.min(0.08, duration * 0.2);
    const hold = shape && shape.hold ? Math.min(duration * shape.hold, duration - attack - 0.05) : 0;
    gain.gain.setValueAtTime(0, at);
    gain.gain.linearRampToValueAtTime(volume, at + attack);
    if (hold > 0) gain.gain.setValueAtTime(volume, at + attack + hold);
    gain.gain.exponentialRampToValueAtTime(0.00001, at + duration);
    source.connect(filter).connect(gain);
    if (pan) {
      pan.pan.value = random(-0.75, 0.75);
      gain.connect(pan).connect(master);
    } else gain.connect(master);
    const nodes = [source, filter, gain, pan].filter(Boolean);
    const entry = { finish() {
      if (!voices.delete(entry)) return;
      source.onended = null;
      try { source.stop(); } catch (_) { /* Already ended. */ }
      nodes.forEach(node => node.disconnect());
    } };
    voices.add(entry);
    source.onended = entry.finish;
    source.start(at);
    source.stop(at + duration + 0.02);
  }

  function playCroak(pitchScale = 1.0, level = 1) {
    if (!active() || context.state !== 'running') return;
    const baseHz = random(148, 195) * pitchScale;
    // Syllable 1: resonant throat "rib-"
    voice('triangle', baseHz, 0.16, 0.22 * level, baseHz * 1.38, 0);
    voice('sine', baseHz * 2.02, 0.14, 0.14 * level, baseHz * 2.65, 0.01);
    // Syllable 2: expressive upward-then-downward "-bit!"
    voice('triangle', baseHz * 1.12, 0.24, 0.26 * level, baseHz * 0.72, 0.18);
    voice('sine', baseHz * 2.24, 0.20, 0.16 * level, baseHz * 1.45, 0.19);
    // Subtle pad/water plop resonance
    voice('sine', random(520, 760), 0.11, 0.09 * level, random(210, 310), 0.04);
  }

  function tick() {
    if (!active() || context.state !== 'running') return;
    const t = context.currentTime;
    const r = state.richness;
    const layers = soundLayers(state.elapsedSeconds);
    const night = state.sleeping;
    const storm = /storm|thunder|tormenta/i.test(state.weather);
    const rainLevel = storm ? 1 : /drizzle/i.test(state.weather) ? 0.35
      : /rain|lluvia/i.test(state.weather) ? 1 : 0;
    smooth(beds[0].gain.gain, layers.breeze * (0.065 + 0.02 * Math.sin(t * 0.17)) * (1 + 0.4 * rainLevel), 1.5);
    smooth(beds[1].gain.gain, layers.water * (0.022 + 0.012 * (1 + Math.sin(t * 0.31))), 1.2);
    smooth(beds[2].gain.gain, layers.rain * 0.16 * state.rainIntensity, 1.5);
    if (layers.insects > 0 && t >= next.cricket) {
      next.cricket = t + random(1.4, 3.8) / (0.5 + r);
      const hz = random(3400, 4700);
      for (let i = 0; i < 3; i++) voice('sine', hz, 0.065, layers.insects * (night ? 0.045 : 0.032), hz * 0.98, i * 0.14);
    }
    if (t >= next.water) {
      next.water = t + random(1.8, 4.8);
      voice('sine', random(900, 1500), 0.22, 0.065 * layers.water, random(300, 500));
    }
    if (layers.frogs > 0 && t >= next.frog) {
      next.frog = t + random(2.6, 5.8) / (0.6 + r);
      playCroak(random(0.88, 1.24), layers.frogs);
    }
    if (t >= next.owl) {
      next.owl = t + random(14, 28);
      if (layers.distant > 0 && (night || r > 0.35)) {
        voice('sine', 380, 0.65, 0.06 * layers.distant, 320);
        voice('sine', 350, 0.8, 0.05 * layers.distant, 300, 0.95);
      }
    }
    if (t >= next.thunder) {
      if (storm) {
        const plan = thunderPlan(state.rainIntensity, t, thunderMemory.heavyAt);
        next.thunder = plan.nextAt;
        if (plan.kind === 'heavy') thunderMemory.heavyAt = t;
        voice('noise', plan.cutoff, plan.duration, plan.gain * layers.rain, plan.cutoff, 0,
          { attack: plan.attack });
      } else next.thunder = t + random(THUNDER.INTERVAL_MIN, THUNDER.INTERVAL_MAX);
    }
    speciesVoices(t, r);
  }

  // Insect voices: each plays only while its species is present on screen
  // (the model reports visible counts), gently, and under the same richness
  // and concurrency rules as everything else. More singers mean a slightly
  // denser chorus, never a louder one: gain saturates at three.
  function speciesVoices(t, r) {
    const level = soundLayers(state.elapsedSeconds).insects;
    if (level === 0) return;
    const s = state.species;
    const dens = (n) => Math.min(1, n / 3);
    if (s.cricket && t >= next.chorus) {
      // Field crickets: a four-pulse trill above the generic cricket bed.
      next.chorus = t + random(0.9, 2.4) / (0.6 + r) / (0.7 + 0.3 * dens(s.cricket));
      const hz = random(4100, 4800);
      for (let i = 0; i < 4; i++) voice('sine', hz, 0.05, level * 0.028 * (0.6 + 0.4 * dens(s.cricket)), hz * 0.99, i * 0.09);
    }
    if (s.katydid && t >= next.katydid) {
      // Katydid rasp: three dry bandpassed noise ticks, "ch-ch-ch".
      next.katydid = t + random(2.4, 6) / (0.6 + r);
      for (let i = 0; i < 3; i++) {
        voice('noise', 3200, 0.07, level * 0.04 * (0.6 + 0.4 * dens(s.katydid)), 3200, i * 0.15,
          { filter: 'bandpass', cutoff: random(2900, 3500), q: 5, attack: 0.01 });
      }
    }
    if (s.bee && t >= next.bee) {
      // A bee passing: low sawtooth hum through a soft lowpass, panned.
      next.bee = t + random(3, 7.5) / (0.6 + r);
      const hz = random(215, 250);
      voice('sawtooth', hz, random(1.1, 1.9), level * 0.03 * (0.7 + 0.3 * dens(s.bee)), hz * random(0.94, 1.08), 0,
        { cutoff: 1100, attack: 0.35, hold: 0.3 });
    }
    if (s.cicada && t >= next.cicada) {
      // Cicada drone: a buzzy square swelling over seconds, kept far back.
      next.cicada = t + random(7, 15) / (0.6 + r);
      const hz = random(104, 126);
      voice('square', hz, random(2.6, 4.2), level * 0.022 * (0.7 + 0.3 * dens(s.cicada)), hz * 1.08, 0,
        { cutoff: 4200, attack: 1.0, hold: 0.35 });
    }
  }

  function stop() {
    if (timer !== undefined) window.clearInterval(timer);
    timer = undefined;
    if (!context) return;
    // Immediate mute also covers visibility changes while a fade is underway.
    master.gain.cancelScheduledValues(context.currentTime);
    master.gain.setValueAtTime(0, context.currentTime);
    clearVoices();
    context.suspend().catch(() => {});
  }

  function sync() {
    // Do not suspend or race a resume still pending from the gesture handler.
    if (unlockPending) return;
    if (!active()) { stop(); return; }
    const attempt = unlockAttempt;
    context.resume().then(() => {
      if (disposed || attempt !== unlockAttempt) return;
      if (!active()) { stop(); return; }
      smooth(master.gain, soundLayers(state.elapsedSeconds).master * 0.96, 0.08);
      if (timer === undefined) {
        tick();
        timer = window.setInterval(tick, 250);
      }
    }).catch(() => unlockFailed(attempt));
  }
  function visibility() { if (document.hidden) stop(); else if (started) sync(); }
  document.addEventListener('visibilitychange', visibility);

  window.ranitasAudio = Object.freeze({
    // `rainIntensity` (0–1) and `species` (`voice:count,…`) are optional; an
    // older caller that omits them gets the pre-envelope behaviour.
    update(progress, richness, weather, sleeping, rainIntensity, species, elapsedSeconds) {
      if (disposed) return;
      state = { progress: clamp(progress), richness: clamp(richness),
        weather: typeof weather === 'string' ? weather : 'clear', sleeping: sleeping === true,
        rainIntensity: rainIntensity === undefined ? (/storm|thunder|tormenta/i.test(String(weather)) ? 0.6 : 0) : clamp(rainIntensity),
        species: parseSpecies(species),
        elapsedSeconds: Number.isFinite(elapsedSeconds) ? Math.max(0, elapsedSeconds) : clamp(richness) * 180 };
      // A pre-gesture update cannot queue sound for the intro press. Require a
      // fresh positive update after the unlocking pointer or key has been released.
      if (!started && unlocked && gestureEnded && state.richness > 0) started = true;
      if (started) sync();
    },
    suspend() { if (!disposed) { suspended = true; stop(); } },
    resume() { if (!disposed) { suspended = false; if (started) sync(); } },
    dispose() {
      if (disposed) return;
      disposed = true;
      stop();
      window.removeEventListener('pointerdown', unlock, true);
      window.removeEventListener('pointerup', endGesture, true);
      window.removeEventListener('pointercancel', endGesture, true);
      window.removeEventListener('keydown', unlock, true);
      window.removeEventListener('keyup', endGesture, true);
      document.removeEventListener('visibilitychange', visibility);
      for (const bed of beds) {
        bed.source.stop();
        bed.source.disconnect(); bed.filter.disconnect(); bed.gain.disconnect();
      }
      beds.length = 0;
      if (master) master.disconnect();
      noise = null;
      if (context) context.close().catch(() => {});
    },
    // Pure helpers exposed for tests; they touch no audio state.
    thunderPlan,
    soundLayers,
    parseSpecies,
    thunderLimits: THUNDER,
  });
})();
