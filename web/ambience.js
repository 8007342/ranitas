/* Original procedural pond soundscape. Load before flutter_bootstrap.js. */
(() => {
  'use strict';
  if (window.ranitasAudio) return;
  const clamp = (value) => Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0;
  let context, master, noise, timer;
  let disposed = false, unlocked = false, started = false, suspended = false;
  let unlockPointer = null, unlockKey = null, gestureEnded = false;
  let state = { progress: 0, richness: 0, weather: 'clear', sleeping: false };
  const voices = new Set();
  const beds = [];
  const next = { cricket: 0, water: 0, frog: 0, owl: 0, thunder: 0 };
  const random = (a, b) => a + Math.random() * (b - a);
  const active = () => context && unlocked && started && !suspended && !document.hidden && !disposed;

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

  // Resume inside the synchronous browser input stack, before Flutter handles it.
  function unlock(event) {
    const key = event.type === 'keydown' ? activationKey(event) : null;
    if (event.isTrusted === false) return;
    if (event.type === 'keydown' && (!key || event.repeat || event.isComposing ||
        event.altKey || event.ctrlKey || event.metaKey)) return;
    if (disposed || unlocked || document.hidden) return;
    try {
      if (!context && !construct()) return;
      unlockPointer = key ? null : event.pointerId;
      unlockKey = key;
      const promise = context.resume();
      if (promise) promise.catch(() => {});
      unlocked = true;
    } catch (_) { /* Audio is optional on unsupported browsers. */ }
  }
  function endGesture(event) {
    if (!unlocked) return;
    if (event.type === 'keyup') {
      if (unlockKey && activationKey(event) === unlockKey) gestureEnded = true;
    } else if (unlockKey === null && event.pointerId === unlockPointer) {
      gestureEnded = true;
    }
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
  function voice(kind, frequency, duration, volume, sweep = frequency, delay = 0) {
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
    filter.type = 'lowpass';
    filter.frequency.value = kind === 'noise' ? frequency : 6500;
    gain.gain.setValueAtTime(0, at);
    gain.gain.linearRampToValueAtTime(volume, at + Math.min(0.08, duration * 0.2));
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

  function tick() {
    if (!active() || context.state !== 'running') return;
    const t = context.currentTime;
    const r = state.richness;
    const night = state.sleeping;
    const rain = /rain|storm|thunder|lluvia|tormenta/i.test(state.weather);
    const storm = /storm|thunder|tormenta/i.test(state.weather);
    smooth(beds[0].gain.gain, (0.045 + 0.015 * Math.sin(t * 0.17)) * (rain ? 1.4 : 1), 1.5);
    smooth(beds[1].gain.gain, 0.012 + 0.008 * (1 + Math.sin(t * 0.31)), 1.2);
    smooth(beds[2].gain.gain, rain ? 0.13 : 0, 1.5);
    if (t >= next.cricket) {
      next.cricket = t + random(1.4, 4.5) / (0.5 + r);
      const hz = random(3400, 4700);
      for (let i = 0; i < 3; i++) voice('sine', hz, 0.065, night ? 0.025 : 0.018, hz * 0.98, i * 0.14);
    }
    if (t >= next.water) {
      next.water = t + random(2, 6);
      voice('sine', random(900, 1500), 0.22, 0.035, random(300, 500));
    }
    if (t >= next.frog) {
      next.frog = t + random(4, 10) / (0.5 + r);
      if (r > 0.22) {
        const hz = random(140, 230);
        voice('triangle', hz, 0.28, 0.045, hz * 0.65);
        voice('sine', hz * 1.07, 0.23, 0.03, hz * 0.7, 0.35);
      }
    }
    if (t >= next.owl) {
      next.owl = t + random(18, 35);
      if (night && r > 0.45) {
        voice('sine', 380, 0.65, 0.035, 320);
        voice('sine', 350, 0.8, 0.03, 300, 0.95);
      }
    }
    if (t >= next.thunder) {
      next.thunder = t + random(22, 45);
      if (storm) voice('noise', 180, 3.5, 0.12);
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
    if (!active()) { stop(); return; }
    context.resume().then(() => {
      if (!active()) { stop(); return; }
      smooth(master.gain, 0.32 * state.richness * (state.sleeping ? 0.7 : 1), 0.6);
      if (timer === undefined) {
        tick();
        timer = window.setInterval(tick, 250);
      }
    }).catch(() => {});
  }
  function visibility() { if (document.hidden) stop(); else if (started) sync(); }
  document.addEventListener('visibilitychange', visibility);

  window.ranitasAudio = Object.freeze({
    update(progress, richness, weather, sleeping) {
      if (disposed) return;
      state = { progress: clamp(progress), richness: clamp(richness),
        weather: typeof weather === 'string' ? weather : 'clear', sleeping: sleeping === true };
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
  });
})();
