// Звук: синтез струны, метроном, микрофон, определение высоты, хромаграмма, атаки.
import { CHORDS, chordMidis } from './data.js';
import { S } from './store.js';

let _ctx = null;
export function ctx() {
  if (!_ctx) _ctx = new (window.AudioContext || window.webkitAudioContext)();
  if (_ctx.state === 'suspended') _ctx.resume();
  return _ctx;
}

// ---- Синтез (Карплус — Стронг) ----
const bufCache = new Map();
function pluckBuffer(midi) {
  if (bufCache.has(midi)) return bufCache.get(midi);
  const c = ctx(), sr = c.sampleRate, f = 440 * 2 ** ((midi - 69) / 12);
  const len = Math.floor(sr * 2.2), N = Math.round(sr / f);
  const buf = c.createBuffer(1, len, sr), out = buf.getChannelData(0);
  const ring = new Float32Array(N);
  for (let i = 0; i < N; i++) ring[i] = Math.random() * 2 - 1;
  const decay = 0.996 - (midi - 40) * 0.00004;
  let p = 0, prev = 0;
  for (let i = 0; i < len; i++) {
    const cur = ring[p];
    const nxt = ring[(p + 1) % N];
    ring[p] = decay * 0.5 * (cur + nxt);
    out[i] = 0.7 * cur + 0.3 * prev; // лёгкое сглаживание
    prev = cur;
    p = (p + 1) % N;
  }
  bufCache.set(midi, buf);
  return buf;
}

let master = null;
function out() {
  const c = ctx();
  if (!master) { master = c.createGain(); master.gain.value = 0.5; master.connect(c.destination); }
  return master;
}

export function playNote(midi, when = 0, gain = 0.6, dur = 2) {
  const c = ctx(), t = Math.max(when, c.currentTime);
  const src = c.createBufferSource(), g = c.createGain();
  src.buffer = pluckBuffer(midi);
  g.gain.setValueAtTime(gain, t);
  g.gain.setTargetAtTime(0, t + dur, 0.08);
  src.connect(g).connect(out());
  src.start(t);
  src.stop(t + dur + 0.5);
}

// dir: 'D' вниз (с 6-й к 1-й), 'U' вверх (только тонкие), 'X' глушение
export function strum(chord, dir = 'D', when = 0) {
  const c = ctx(), t0 = Math.max(when, c.currentTime);
  if (dir === 'X') return mutedHit(t0);
  const midis = (typeof chord === 'string' ? chordMidis(CHORDS[chord]) : chord).map((m, i) => ({ m, i })).filter(o => o.m != null);
  let list = dir === 'U' ? midis.slice(-4).reverse() : midis;
  list.forEach((o, k) => playNote(o.m, t0 + k * 0.012, dir === 'U' ? 0.22 : 0.28, 1.6));
}

function mutedHit(t) {
  const c = ctx(), len = Math.floor(c.sampleRate * 0.06);
  const b = c.createBuffer(1, len, c.sampleRate), d = b.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len) ** 3;
  const s = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
  f.type = 'bandpass'; f.frequency.value = 900; f.Q.value = 0.8; g.gain.value = 0.9;
  s.buffer = b; s.connect(f).connect(g).connect(out()); s.start(t);
}

export function click(when, accent = false) {
  const c = ctx(), t = Math.max(when, c.currentTime);
  const o = c.createOscillator(), g = c.createGain();
  o.frequency.value = accent ? 1600 : 1000;
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(accent ? 0.6 : 0.35, t + 0.002);
  g.gain.exponentialRampToValueAtTime(0.0001, t + 0.05);
  o.connect(g).connect(out());
  o.start(t); o.stop(t + 0.06);
}

export function beep(freq = 880, dur = 0.25) {
  const c = ctx(), t = c.currentTime, o = c.createOscillator(), g = c.createGain();
  o.frequency.value = freq;
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(0.4, t + 0.01);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(out()); o.start(t); o.stop(t + dur + 0.05);
}

// ---- Планировщик: вызывает cb(time, step) заранее, шаг = восьмая ----
export class Clock {
  constructor(bpm, cb, stepsPerBeat = 2) {
    this.bpm = bpm; this.cb = cb; this.spb = stepsPerBeat; this.timer = null;
  }
  get stepDur() { return 60 / this.bpm / this.spb; }
  start(delay = 0.15) {
    const c = ctx();
    this.t0 = c.currentTime + delay; this.next = this.t0; this.step = 0;
    const tick = () => {
      while (this.next < c.currentTime + 0.12) {
        this.cb(this.next, this.step);
        this.step++;
        this.next = this.t0 + this.step * this.stepDur;
      }
    };
    tick();
    this.timer = setInterval(tick, 25);
    return this.t0;
  }
  setBpm(bpm) {
    // продолжаем с текущего шага без скачка
    const c = ctx(); this.bpm = bpm;
    this.t0 = this.next - this.step * this.stepDur;
    if (this.next < c.currentTime) this.t0 = c.currentTime - this.step * this.stepDur + 0.05;
  }
  stop() { clearInterval(this.timer); this.timer = null; }
}

// ---- Микрофон ----
const WORKLET = `
class Onset extends AudioWorkletProcessor {
  constructor(){ super(); this.prev=0; this.slow=1e-6; this.last=-1; this.sens=1; this.lvl=0; this.n=0;
    this.port.onmessage = e => { this.sens = e.data.sens; }; }
  process(inputs){
    const x = inputs[0] && inputs[0][0]; if(!x) return true;
    let e=0; for(let i=0;i<x.length;i++){ const d=x[i]-this.prev; this.prev=x[i]; e+=d*d; }
    e/=x.length;
    const thr = Math.max(4e-6 / this.sens, this.slow * 5 / this.sens);
    if (e > thr && currentTime - this.last > 0.09) { this.last = currentTime; this.port.postMessage({t: currentTime, e}); }
    this.slow = this.slow*0.985 + e*0.015;
    this.lvl = Math.max(e, this.lvl*0.9);
    if(++this.n % 8 === 0) this.port.postMessage({lvl: this.lvl});
    return true;
  }
}
registerProcessor('onset', Onset);`;

class Mic {
  constructor() { this.listeners = new Set(); this.stream = null; this.level = 0; }
  async start() {
    if (this.stream) return this;
    const c = ctx();
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    });
    this.src = c.createMediaStreamSource(this.stream);
    this.an = c.createAnalyser(); this.an.fftSize = 4096; this.an.smoothingTimeConstant = 0;
    this.fan = c.createAnalyser(); this.fan.fftSize = 16384; this.fan.smoothingTimeConstant = 0.3;
    this.src.connect(this.an); this.src.connect(this.fan);
    this.tbuf = new Float32Array(this.an.fftSize);
    this.fbuf = new Float32Array(this.fan.frequencyBinCount);
    try {
      if (!this.workletReady) {
        const url = URL.createObjectURL(new Blob([WORKLET], { type: 'application/javascript' }));
        await c.audioWorklet.addModule(url);
        this.workletReady = true;
      }
      this.node = new AudioWorkletNode(c, 'onset');
      this.node.port.postMessage({ sens: S.settings.sens });
      this.node.port.onmessage = e => {
        if (e.data.lvl != null) this.level = e.data.lvl;
        else this.listeners.forEach(fn => fn(e.data.t));
      };
      this.src.connect(this.node);
      const mute = c.createGain(); mute.gain.value = 0;
      this.node.connect(mute).connect(c.destination); // чтобы Safari не останавливал узел
    } catch (err) {
      console.warn('AudioWorklet недоступен, атаки по анализатору', err);
      this.pollOnsets();
    }
    return this;
  }
  pollOnsets() {
    let slow = 1e-6, last = 0;
    const buf = new Float32Array(1024);
    const loop = () => {
      if (!this.stream) return;
      this.an.getFloatTimeDomainData(this.tbuf);
      buf.set(this.tbuf.subarray(this.tbuf.length - 1024));
      let e = 0; for (let i = 1; i < buf.length; i++) { const d = buf[i] - buf[i - 1]; e += d * d; }
      e /= buf.length; this.level = e;
      const t = ctx().currentTime - 0.012;
      if (e > Math.max(4e-6, slow * 5) / S.settings.sens && t - last > 0.09) { last = t; this.listeners.forEach(fn => fn(t)); }
      slow = slow * 0.9 + e * 0.1;
      requestAnimationFrame(loop);
    };
    loop();
  }
  setSens(v) { this.node && this.node.port.postMessage({ sens: v }); }
  onOnset(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
  pitch() {
    this.an.getFloatTimeDomainData(this.tbuf);
    return yin(this.tbuf, ctx().sampleRate);
  }
  chroma() {
    this.fan.getFloatFrequencyData(this.fbuf);
    return chroma(this.fbuf, ctx().sampleRate, this.fan.fftSize);
  }
  rms() {
    this.an.getFloatTimeDomainData(this.tbuf);
    let s = 0; for (let i = 0; i < this.tbuf.length; i++) s += this.tbuf[i] ** 2;
    return Math.sqrt(s / this.tbuf.length);
  }
  stop() {
    if (!this.stream) return;
    this.stream.getTracks().forEach(t => t.stop());
    try { this.src.disconnect(); this.node && this.node.disconnect(); } catch { /* уже отключено */ }
    this.stream = null; this.node = null; this.listeners.clear();
  }
}
export const mic = new Mic();

export function micErrorText(err) {
  if (!navigator.mediaDevices) return 'Браузер не даёт доступ к микрофону. Откройте приложение по https-ссылке в Chrome или Safari.';
  if (err && err.name === 'NotAllowedError') return 'Доступ к микрофону запрещён. Разрешите его в настройках сайта (значок замка в адресной строке) и попробуйте снова.';
  if (err && err.name === 'NotFoundError') return 'Микрофон не найден.';
  return 'Не удалось включить микрофон: ' + (err && err.message || err);
}

// ---- YIN: основная частота ----
export function yin(buf, sr, thr = 0.15) {
  const W = 1536;
  const start = buf.length - W - 820;
  let rms = 0;
  for (let i = start; i < buf.length; i++) rms += buf[i] * buf[i];
  rms = Math.sqrt(rms / (buf.length - start));
  if (rms < 0.006) return null;
  const minTau = Math.floor(sr / 1200), maxTau = Math.min(Math.floor(sr / 65), 819);
  const d = new Float32Array(maxTau + 2);
  for (let tau = 1; tau <= maxTau + 1; tau++) {
    let s = 0;
    for (let i = start; i < start + W; i++) { const x = buf[i] - buf[i + tau]; s += x * x; }
    d[tau] = s;
  }
  let run = 0; d[0] = 1;
  for (let tau = 1; tau <= maxTau + 1; tau++) { run += d[tau]; d[tau] = run ? (d[tau] * tau) / run : 1; }
  let tau = -1;
  for (let t = minTau; t <= maxTau; t++) {
    if (d[t] < thr) { while (t + 1 <= maxTau && d[t + 1] < d[t]) t++; tau = t; break; }
  }
  if (tau < 0) return null;
  const a = d[tau - 1], b = d[tau], c = d[tau + 1], den = a + c - 2 * b;
  const shift = den ? (a - c) / (2 * den) : 0;
  return { freq: sr / (tau + shift), clarity: 1 - b, rms };
}

export const freqToMidi = (f, a4 = S.settings.a4) => 69 + 12 * Math.log2(f / a4);
export const midiToFreq = (m, a4 = S.settings.a4) => a4 * 2 ** ((m - 69) / 12);

// ---- Хромаграмма: сколько энергии в каждой из 12 нот ----
export function chroma(fd, sr, size) {
  const c = new Float32Array(12), bin = sr / size;
  const lo = Math.floor(75 / bin), hi = Math.ceil(1500 / bin);
  let max = -Infinity;
  for (let i = lo; i < hi; i++) if (fd[i] > max) max = fd[i];
  if (max < -70) return { c, max };
  const peaks = [];
  for (let i = lo + 1; i < hi; i++) {
    const v = fd[i];
    if (v < max - 40 || v <= fd[i - 1] || v < fd[i + 1]) continue;
    const a = fd[i - 1], b = v, cc = fd[i + 1], den = a + cc - 2 * b;
    peaks.push({ f: (i + (den ? (a - cc) / (2 * den) : 0)) * bin, a: 10 ** (v / 20) });
  }
  for (const p of peaks) {
    const m = freqToMidi(p.f), r = Math.round(m);
    if (Math.abs(m - r) > 0.3) continue;
    // 3-я, 5-я, 6-я, 7-я гармоники дают «чужие» ноты (квинту, терцию, септиму) — почти не учитываем их
    const harmonic = peaks.some(q => q !== p && q.a > p.a * 0.25 && [3, 5, 6, 7].some(k => Math.abs(p.f / q.f - k) < k * 0.015));
    c[((r % 12) + 12) % 12] += p.a * (harmonic ? 0.15 : 1) * (p.f < 330 ? 1.3 : 1);
  }
  let sum = 0;
  for (let k = 0; k < 12; k++) sum += c[k];
  if (sum > 0) for (let k = 0; k < 12; k++) c[k] /= sum;
  const spec = new Float32Array(hi);
  for (let i = lo; i < hi; i++) spec[i] = 10 ** (fd[i] / 20);
  return { c, max, spec, bin };
}

// Не даём экрану гаснуть во время занятий
let wakeLock = null;
export async function keepAwake(on) {
  try {
    if (on && !wakeLock && navigator.wakeLock) wakeLock = await navigator.wakeLock.request('screen');
    if (!on && wakeLock) { await wakeLock.release(); wakeLock = null; }
  } catch { /* не поддерживается */ }
}
