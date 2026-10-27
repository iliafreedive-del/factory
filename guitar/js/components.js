// Интерактивные блоки: тюнер, проверка нот и аккордов, тренажёр боя, таймер, тест.
import { CHORDS, OPEN, PATTERNS, COUNT, chordPcs, chordMidis, midiAt, noteName, pcName, sIdx } from './data.js';
import { ctx, mic, micErrorText, playNote, strum, click, beep, Clock, freqToMidi, midiToFreq, keepAwake } from './audio.js';
import { chordSVG, fretboardSVG } from './svg.js';
import { S, save, setBest } from './store.js';
import { activity } from './activity.js';

export const $ = (sel, root = document) => root.querySelector(sel);
export function html(str) {
  const t = document.createElement('template');
  t.innerHTML = str.trim();
  return t.content.firstElementChild;
}

async function startMic(statusEl) {
  try {
    ctx();
    await mic.start();
    activity.add('mic');
    keepAwake(true);
    return true;
  } catch (err) {
    if (statusEl) statusEl.innerHTML = `<div class="warn">${micErrorText(err)}</div>`;
    return false;
  }
}
function stopMic() {
  mic.stop();
  activity.delete('mic');
  keepAwake(false);
}

const median = a => { const s = [...a].sort((x, y) => x - y); return s[Math.floor(s.length / 2)]; };

// ============ Тюнер ============
export function Tuner(el, { onAllTuned } = {}) {
  el.innerHTML = `<div class="tuner">
    <div class="tuner-note"><span class="tn-name">—</span><span class="tn-oct"></span></div>
    <div class="tuner-freq muted">Дёрните струну</div>
    <div class="meter"><div class="meter-scale">${[-50, -25, 0, 25, 50].map(v => `<span>${v > 0 ? '+' : ''}${v}</span>`).join('')}</div>
      <div class="meter-bar"><div class="meter-zone"></div><div class="needle"></div></div></div>
    <div class="tuner-hint">&nbsp;</div>
    <div class="strings-row">${[6, 5, 4, 3, 2, 1].map(n => {
      const m = OPEN[sIdx(n)];
      return `<button class="str-btn" data-s="${n}"><b>${noteName(m).lat}</b><small>${n}</small><i class="ok">✓</i></button>`;
    }).join('')}</div>
    <div class="row gap center"><label class="chk"><input type="checkbox" class="auto" checked> Авто-выбор струны</label>
      <button class="btn ghost ref">▶ Эталон</button></div>
    <div class="status"></div>
    <button class="btn primary start">🎤 Включить микрофон</button>
  </div>`;
  const nameEl = $('.tn-name', el), octEl = $('.tn-oct', el), freqEl = $('.tuner-freq', el), needle = $('.needle', el), hintEl = $('.tuner-hint', el);
  const auto = $('.auto', el);
  let manual = null, running = false, timer = null, hist = [];
  const tuned = new Set(), inTuneFor = {};
  const btns = [...el.querySelectorAll('.str-btn')];

  btns.forEach(b => b.onclick = () => {
    manual = +b.dataset.s; auto.checked = false; highlight(manual);
    playNote(OPEN[sIdx(manual)], 0, 0.5);
  });
  auto.onchange = () => { if (auto.checked) manual = null; };
  $('.ref', el).onclick = () => {
    const s = manual || +((btns.find(b => b.classList.contains('cur')) || btns[0]).dataset.s);
    playNote(OPEN[sIdx(s)], 0, 0.6);
  };
  function highlight(s) { btns.forEach(b => b.classList.toggle('cur', +b.dataset.s === s)); }

  let last = performance.now();
  function frame() {
    const now = performance.now(), dt = (now - last) / 1000; last = now;
    const p = mic.pitch();
    if (!p || p.clarity < 0.85 || p.freq < 70 || p.freq > 700) { hist = []; return; }
    hist.push(freqToMidi(p.freq)); if (hist.length > 5) hist.shift();
    const m = median(hist);
    let target = manual;
    if (!target) {
      let best = 99;
      [6, 5, 4, 3, 2, 1].forEach(n => { const d = Math.abs(m - OPEN[sIdx(n)]); if (d < best) { best = d; target = n; } });
    }
    const tm = OPEN[sIdx(target)], cents = (m - tm) * 100;
    highlight(target);
    const nn = noteName(m);
    nameEl.textContent = nn.lat; octEl.textContent = nn.ru;
    freqEl.textContent = `${p.freq.toFixed(1)} Гц · струна ${target} (${noteName(tm).lat})`;
    const shown = Math.max(-50, Math.min(50, cents));
    needle.style.left = `${50 + shown}%`;
    const good = Math.abs(cents) < 5;
    el.querySelector('.tuner').classList.toggle('good', good);
    if (Math.abs(cents) > 150) hintEl.textContent = cents < 0
      ? `Звук сильно ниже ${noteName(tm).lat} — закручивайте колок (натягивайте).`
      : `Звук сильно выше ${noteName(tm).lat} — ослабьте струну, чтобы не порвать.`;
    else if (good) hintEl.textContent = '✓ В строю!';
    else hintEl.textContent = cents < 0 ? `Ниже на ${Math.round(-cents)} центов — чуть подтяните колок ↑` : `Выше на ${Math.round(cents)} центов — чуть ослабьте колок ↓`;
    if (good) {
      inTuneFor[target] = (inTuneFor[target] || 0) + dt;
      if (inTuneFor[target] > 0.8 && !tuned.has(target)) {
        tuned.add(target);
        btns.find(b => +b.dataset.s === target).classList.add('done');
        if (tuned.size === 6 && onAllTuned) onAllTuned();
      }
    } else inTuneFor[target] = 0;
  }

  $('.start', el).onclick = async () => {
    if (running) { stop(); return; }
    if (!(await startMic($('.status', el)))) return;
    running = true; $('.start', el).textContent = '⏹ Выключить микрофон';
    last = performance.now();
    timer = setInterval(frame, 50);
  };
  function stop() {
    clearInterval(timer); running = false; stopMic();
    $('.start', el).textContent = '🎤 Включить микрофон';
  }
  return () => running && stop();
}

// ============ Проверка нот по очереди ============
export function NoteChecker(el, { targets, onDone }) {
  el.innerHTML = `<div class="checker">
    <div class="fb"></div>
    <div class="target big"></div>
    <div class="hint">&nbsp;</div>
    <div class="row gap wrap center">
      <button class="btn primary start">🎤 Слушать</button>
      <button class="btn ghost listen">▶ Как звучит</button>
      <button class="btn ghost skip">Пропустить →</button>
    </div><div class="status"></div></div>`;
  let i = 0, running = false, timer = null, offOnset = null, armed = true, stable = { r: null, since: 0 }, lastHint = 0;
  const fb = $('.fb', el), tgt = $('.target', el), hint = $('.hint', el);
  const fingerFor = f => (f === 0 ? 'открытая' : `палец ${Math.min(f, 4)}`);

  function render() {
    fb.innerHTML = fretboardSVG(targets.map((t, k) => ({ s: t.s, f: t.f, cls: k < i ? 'done' : k === i ? 'target' : 'next' })), Math.max(5, ...targets.map(t => t.f + 1)));
    if (i >= targets.length) { tgt.innerHTML = '🎉 Всё сыграно!'; return; }
    const t = targets[i], n = noteName(midiAt(t.s, t.f));
    tgt.innerHTML = `<span class="pill">${i + 1}/${targets.length}</span> Струна <b>${t.s}</b>, ${t.f === 0 ? '<b>открытая</b>' : `лад <b>${t.f}</b>`} → ${n.ru} (${n.lat}) ${t.f ? `<span class="muted">· ${fingerFor(t.f)}</span>` : ''}`;
  }
  render();

  function describeWrong(r, t, cents) {
    const target = midiAt(t.s, t.f), d = r - target;
    const heard = noteName(r), want = noteName(target);
    if (d === 0) return `Нота верная, но фальшивит на ${cents > 0 ? '+' : ''}${Math.round(cents)} центов — проверьте строй в тюнере.`;
    let s = `Звучит ${heard.ru} (${heard.lat}), а нужна ${want.ru} (${want.lat}). `;
    const fretOnString = r - OPEN[sIdx(t.s)];
    if (Math.abs(d) <= 5 && fretOnString >= 0) {
      s += fretOnString === 0
        ? `Похоже, струна ${t.s} не прижата — дожмите палец на ${t.f}-м ладу.`
        : `Если вы на ${t.s}-й струне, палец стоит на ${fretOnString}-м ладу, а нужен ${t.f === 0 ? 'открытый звук (отпустите струну)' : `${t.f}-й`}.`;
    } else {
      const where = [];
      for (let n = 1; n <= 6; n++) { const f = r - OPEN[sIdx(n)]; if (f >= 0 && f <= 5) where.push(`${n}-я стр. ${f === 0 ? 'открытая' : f + '-й лад'}`); }
      s += `Наверное, звучит не та струна${where.length ? ` (такая нота: ${where.join(', ')})` : ''}. Нужна ${t.s}-я.`;
    }
    return s;
  }

  function frame() {
    if (i >= targets.length) return;
    const p = mic.pitch();
    const now = performance.now();
    if (!p || p.clarity < 0.82) { stable = { r: null, since: now }; return; }
    const m = freqToMidi(p.freq), r = Math.round(m), cents = (m - r) * 100;
    if (r !== stable.r) { stable = { r, since: now }; return; }
    if (now - stable.since < 160 || !armed) return;
    const t = targets[i], target = midiAt(t.s, t.f);
    const sameClass = (r - target) % 12 === 0 && Math.abs(r - target) <= 12;
    if (sameClass && Math.abs(cents) < 40) {
      i++; armed = false;
      hint.innerHTML = `<span class="good-t">✓ ${noteName(r).ru}! ${i < targets.length ? 'Дальше.' : ''}</span>`;
      render();
      if (i >= targets.length) { stop(); onDone && onDone(); }
    } else if (now - stable.since > 350 && now - lastHint > 900) {
      lastHint = now;
      hint.innerHTML = `<span class="bad-t">${describeWrong(sameClass ? target : r, t, cents)}</span>`;
    }
  }

  $('.listen', el).onclick = () => { const t = targets[Math.min(i, targets.length - 1)]; playNote(midiAt(t.s, t.f), 0, 0.6); };
  $('.skip', el).onclick = () => { if (i < targets.length) { i++; render(); if (i >= targets.length) { stop(); onDone && onDone(); } } };
  $('.start', el).onclick = async () => {
    if (running) return stop();
    if (!(await startMic($('.status', el)))) return;
    running = true; $('.start', el).textContent = '⏹ Стоп';
    offOnset = mic.onOnset(() => { armed = true; });
    armed = true;
    timer = setInterval(frame, 40);
    hint.textContent = 'Слушаю… играйте ноту.';
  };
  function stop() {
    clearInterval(timer); offOnset && offOnset(); running = false; stopMic();
    $('.start', el).textContent = '🎤 Слушать';
  }
  return () => running && stop();
}

// ============ Аккорды: разбор хромаграммы ============
// Струны, чья основная частота почти не слышна. Проверяем только ноты,
// которые не совпадают с обертонами более низких струн аккорда.
function silentStrings(ch, spec) {
  if (!spec) return [];
  const { a, bin } = spec;
  const amp = f => { let m = 0; for (let i = Math.floor(f * 0.983 / bin); i <= Math.ceil(f * 1.017 / bin) && i < a.length; i++) m = Math.max(m, a[i]); return m; };
  let top = 0; for (let i = 0; i < a.length; i++) top = Math.max(top, a[i]);
  const voiced = chordMidis(ch).map((m, i) => ({ m, i, f: midiToFreq(m) })).filter(o => o.m != null);
  return voiced.filter(o =>
    !voiced.some(l => l.m < o.m && [2, 3, 4, 5, 6].some(k => Math.abs(o.f / l.f - k) < 0.03 * k)) &&
    amp(o.f) < top * 0.03).map(o => o.i);
}

export function evalChord(name, c, spec) {
  const ch = CHORDS[name], tones = chordPcs(ch);
  let inChord = 0; tones.forEach(pc => (inChord += c[pc]));
  const silent = silentStrings(ch, spec);
  const missing = tones.filter(pc => c[pc] < 0.045);
  let foreign = null, fv = 0.13;
  for (let pc = 0; pc < 12; pc++) if (!tones.includes(pc) && c[pc] > fv) { fv = c[pc]; foreign = pc; }
  const ok = inChord >= 0.72 && missing.length === 0 && silent.length === 0;
  const score = inChord - missing.length * 0.15;
  return { ok, inChord, missing, foreign, score, silent };
}

function chordHints(name, res) {
  const ch = CHORDS[name], hints = [], bad = [];
  for (const pc of res.missing) {
    const strs = ch.frets.map((f, i) => ({ f, i })).filter(o => o.f >= 0 && (OPEN[o.i] + o.f) % 12 === pc);
    const fretted = strs.filter(o => o.f > 0), open = strs.filter(o => o.f === 0);
    strs.forEach(o => bad.push(o.i));
    if (fretted.length) {
      const o = fretted[0];
      hints.push(`Не слышно ноты ${pcName(pc)}: ${6 - o.i}-я струна, ${o.f}-й лад (палец ${ch.fingers[o.i]}). Прижмите сильнее кончиком, ближе к порожку.`);
    } else if (open.length) {
      hints.push(`Глушится открытая ${open.map(o => 6 - o.i).join(' и ')}-я струна (${pcName(pc)}). Её задевает соседний палец: держите пальцы круче, «домиком».`);
    }
  }
  for (const i of res.silent || []) {
    if (bad.includes(i)) continue;
    bad.push(i);
    const f = ch.frets[i];
    hints.push(f > 0
      ? `Не звучит ${6 - i}-я струна (${f}-й лад, палец ${ch.fingers[i]}). Дожмите её кончиком пальца ближе к порожку.`
      : `Не звучит открытая ${6 - i}-я струна: её глушит соседний палец. Держите пальцы «домиком».`);
  }
  if (res.foreign != null) {
    const pc = res.foreign;
    const mutedStr = ch.frets.map((f, i) => ({ f, i })).find(o => o.f < 0 && OPEN[o.i] % 12 === pc);
    const neighbour = ch.frets.map((f, i) => ({ f, i })).find(o => o.f > 0 && [1, 11].includes(((OPEN[o.i] + o.f - pc) % 12 + 12) % 12));
    if (mutedStr) { hints.push(`Звучит ${6 - mutedStr.i}-я струна, которую в ${name} не играют. Начинайте удар с ${6 - ch.frets.findIndex(f => f >= 0)}-й струны.`); bad.push(mutedStr.i); }
    else if (neighbour) { hints.push(`Слышна лишняя нота ${pcName(pc)}. Возможно, палец на ${6 - neighbour.i}-й струне стоит не на том ладу (нужен ${neighbour.f}-й).`); bad.push(neighbour.i); }
    else hints.push(`Слышна посторонняя нота ${pcName(pc)}. Проверьте строй тюнером.`);
  }
  if (!hints.length) hints.push('Почти! Ударьте увереннее по всем нужным струнам и дайте аккорду прозвучать.');
  return { hints, bad };
}

function bestChordGuess(c, exclude) {
  let best = null, bs = 0.6;
  for (const n of Object.keys(CHORDS)) { const r = evalChord(n, c); if (r.score > bs && n !== exclude) { bs = r.score; best = n; } }
  return best;
}

// Слушаем удар: ждём атаку, копим спектр ~0.45 с и выносим вердикт
function listenStrums(onResult) {
  let collecting = null, timer = null;
  const off = mic.onOnset(t => {
    if (collecting) return;
    collecting = { start: performance.now() + 120, sum: new Float32Array(12), spec: null, n: 0, max: -200 };
  });
  timer = setInterval(() => {
    if (!collecting || performance.now() < collecting.start) return;
    const { c, max, spec, bin } = mic.chroma();
    collecting.max = Math.max(collecting.max, max);
    if (max > -75) {
      for (let k = 0; k < 12; k++) collecting.sum[k] += c[k];
      if (!collecting.spec) collecting.spec = { a: new Float32Array(spec.length), bin };
      for (let i = 0; i < spec.length; i++) collecting.spec.a[i] += spec[i];
      collecting.n++;
    }
    if (performance.now() - collecting.start > 450) {
      const col = collecting; collecting = null;
      let s = 0; for (let k = 0; k < 12; k++) s += col.sum[k];
      if (col.n < 3 || s === 0) onResult(null, col.max);
      else onResult(col.sum.map(v => v / s), col.max, col.spec);
    }
  }, 30);
  return () => { off(); clearInterval(timer); };
}

function chromaBars(c, tones) {
  return `<div class="chroma">${[...Array(12)].map((_, pc) =>
    `<div class="cb ${tones.includes(pc) ? 'in' : ''}"><i style="height:${Math.round(Math.min(1, c[pc] * 2.5) * 100)}%"></i><span>${noteName(pc + 60).lat}</span></div>`).join('')}</div>`;
}

export function ChordChecker(el, { chord, need = 3, onDone }) {
  const tones = chordPcs(CHORDS[chord]);
  el.innerHTML = `<div class="checker">
    <div class="row gap center wrap"><div class="diagram">${chordSVG(chord)}</div>
      <div class="cc-side"><div class="big cc-count">${need === Infinity ? '' : `0 / ${need}`}</div><div class="viz">${chromaBars(new Float32Array(12), tones)}</div></div></div>
    <div class="hint">Поставьте аккорд, включите микрофон и ударьте по струнам.</div>
    <div class="row gap center wrap"><button class="btn primary start">🎤 Слушать</button><button class="btn ghost listen">▶ Как звучит</button></div>
    <div class="status"></div></div>`;
  let running = false, off = null, good = 0;
  const hint = $('.hint', el);
  $('.listen', el).onclick = () => strum(chord, 'D');
  $('.start', el).onclick = async () => {
    if (running) return stop();
    if (!(await startMic($('.status', el)))) return;
    running = true; $('.start', el).textContent = '⏹ Стоп';
    hint.textContent = 'Слушаю… ударьте по струнам.';
    off = listenStrums((c, max, spec) => {
      if (!c) { hint.innerHTML = '<span class="bad-t">Слишком тихо. Ударьте сильнее или поднесите телефон ближе.</span>'; return; }
      $('.viz', el).innerHTML = chromaBars(c, tones);
      const r = evalChord(chord, c, spec);
      if (r.ok) {
        good++;
        if (need !== Infinity) $('.cc-count', el).textContent = `${Math.min(good, need)} / ${need}`;
        hint.innerHTML = `<span class="good-t">✓ Чисто! Все струны звучат.</span>`;
        $('.diagram', el).innerHTML = chordSVG(chord);
        if (good === need) { stop(); onDone && onDone(); }
      } else {
        const { hints, bad } = chordHints(chord, r);
        const guess = bestChordGuess(c, chord);
        hint.innerHTML = `<span class="bad-t">${hints.join('<br>')}${guess ? `<br>Сейчас звучит больше похоже на ${guess}.` : ''}</span>`;
        $('.diagram', el).innerHTML = chordSVG(chord, { bad });
      }
    });
  };
  function stop() { off && off(); running = false; stopMic(); $('.start', el).textContent = '🎤 Слушать'; }
  return () => running && stop();
}

// ============ Смены аккордов за минуту ============
export function ChangesCounter(el, { chords, goal = 8, onDone, bestKey }) {
  const [a, b] = chords;
  el.innerHTML = `<div class="checker">
    <div class="row gap center">${chords.map(n => `<div class="diagram sm" data-c="${n}">${chordSVG(n)}</div>`).join('')}</div>
    <div class="row gap center"><div class="big time">1:00</div><div class="big cnt">0</div></div>
    <div class="hint">Цель: ${goal} смен. Рекорд: ${S.bests[bestKey] || 0}. Микрофон сам считает смены; если он не успевает, жмите «+1».</div>
    <div class="row gap center wrap"><button class="btn primary start">▶ Старт</button><button class="btn ghost plus">+1</button></div>
    <div class="status"></div></div>`;
  let running = false, count = 0, prev = null, end = 0, timer = null, off = null, micOn = false;
  const set = () => { $('.cnt', el).textContent = count; };
  $('.plus', el).onclick = () => { if (running) { count++; set(); } };
  $('.start', el).onclick = async () => {
    if (running) return finish(false);
    count = 0; prev = null; set();
    micOn = await startMic($('.status', el));
    if (micOn) off = listenStrums(c => {
      if (!c) return;
      const ra = evalChord(a, c), rb = evalChord(b, c);
      const cur = Math.max(ra.score, rb.score) < 0.55 ? null : ra.score > rb.score ? a : b;
      el.querySelectorAll('.diagram').forEach(d => d.classList.toggle('cur', d.dataset.c === cur));
      if (cur && prev && cur !== prev) { count++; set(); }
      if (cur) prev = cur;
    });
    running = true; activity.add('changes');
    $('.start', el).textContent = '⏹ Стоп';
    end = performance.now() + 60000;
    timer = setInterval(() => {
      const left = Math.max(0, end - performance.now());
      $('.time', el).textContent = `0:${String(Math.ceil(left / 1000)).padStart(2, '0')}`;
      if (left <= 0) finish(true);
    }, 200);
  };
  function finish(complete) {
    clearInterval(timer); off && off(); running = false; activity.delete('changes');
    if (micOn) stopMic();
    $('.start', el).textContent = '▶ Ещё раз';
    if (!complete) return;
    beep(660, 0.4);
    const rec = setBest(bestKey, count);
    $('.hint', el).innerHTML = count >= goal
      ? `<span class="good-t">✓ ${count} смен за минуту${rec ? ' — новый рекорд!' : ''}. Следующая цель: ${Math.max(goal * 2, count + 5)}.</span>`
      : `<span class="bad-t">${count} смен. Цель ${goal}. Не смотрите на струны: поднимайте все пальцы вместе и ставьте их одновременно.</span>`;
    if (count >= goal && onDone) onDone();
  }
  return () => running && finish(false);
}

// ============ Таймер ============
export function TimerWidget(el, { seconds, metronome, onDone }) {
  el.innerHTML = `<div class="checker"><div class="big time">${fmt(seconds)}</div>
    <div class="pbar"><i></i></div>
    ${metronome ? `<label class="chk"><input type="checkbox" class="met" checked> Метроном ${metronome} уд/мин</label>` : ''}
    <div class="row gap center"><button class="btn primary start">▶ Старт</button><button class="btn ghost reset">↺ Сброс</button></div></div>`;
  let left = seconds, timer = null, clock = null, last = 0;
  const upd = () => { $('.time', el).textContent = fmt(left); $('.pbar i', el).style.width = `${100 - (left / seconds) * 100}%`; };
  function pause() {
    clearInterval(timer); timer = null; clock && clock.stop(); clock = null; activity.delete('timer'); keepAwake(false);
    $('.start', el).textContent = left > 0 ? '▶ Продолжить' : '▶ Старт';
  }
  $('.start', el).onclick = () => {
    if (timer) return pause();
    if (left <= 0) left = seconds;
    ctx(); activity.add('timer'); keepAwake(true);
    if (metronome && $('.met', el).checked) { clock = new Clock(metronome, (t, step) => click(t, step % 4 === 0), 1); clock.start(); }
    last = performance.now();
    timer = setInterval(() => {
      const now = performance.now(); left -= (now - last) / 1000; last = now;
      if (left <= 0) { left = 0; upd(); pause(); beep(880, 0.5); onDone && onDone(); return; }
      upd();
    }, 200);
    $('.start', el).textContent = '⏸ Пауза';
  };
  $('.reset', el).onclick = () => { pause(); left = seconds; upd(); };
  return () => timer && pause();
}
export function fmt(s) { s = Math.ceil(s); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; }

// ============ Вопрос ============
export function Quiz(el, { q, options, answer, onDone }) {
  el.innerHTML = `<div class="checker"><div class="q">${q}</div><div class="opts">${options.map((o, i) => `<button class="btn opt" data-i="${i}">${o}</button>`).join('')}</div><div class="hint">&nbsp;</div></div>`;
  el.querySelectorAll('.opt').forEach(b => b.onclick = () => {
    const ok = +b.dataset.i === answer;
    b.classList.add(ok ? 'right' : 'wrong');
    $('.hint', el).innerHTML = ok ? '<span class="good-t">✓ Верно!</span>' : '<span class="bad-t">Не совсем, попробуйте ещё.</span>';
    if (ok && onDone) onDone();
  });
  return () => {};
}

// ============ Тренажёр боя ============
// mode: 'free' (всё доступно), 'tap' (проверка тапами), 'mic' (проверка микрофоном)
export function StrumTrainer(el, opts) {
  const o = { pattern: 'down4', bpm: 70, bars: 4, chord: 'Am', mode: 'free', ...opts };
  const chords = Array.isArray(o.chord) ? o.chord : [o.chord];
  const free = o.mode === 'free';
  el.innerHTML = `<div class="strum">
    ${free ? `<div class="chips">${Object.entries(PATTERNS).map(([k, p]) => `<button class="chip ${k === o.pattern ? 'on' : ''}" data-p="${k}">${p.name}</button>`).join('')}</div>
      <div class="chips">${['Am', 'Em', 'C', 'G', 'Dm', 'E', 'D', 'A'].map(n => `<button class="chip ch ${n === chords[0] ? 'on' : ''}" data-c="${n}">${n}</button>`).join('')}
      <button class="chip ch" data-c="Am,Dm,E,Am">Am–Dm–E–Am</button><button class="chip ch" data-c="G,Em,C,D">G–Em–C–D</button></div>` : ''}
    <div class="row gap center bpm-row"><button class="btn ghost sm minus">−5</button><div class="bpm"><b>${o.bpm}</b> уд/мин</div><button class="btn ghost sm plus">+5</button></div>
    <div class="now-chord"><span class="cur-ch"></span><span class="next-ch muted"></span><span class="beat-flash"></span></div>
    <div class="grid8"></div>
    <div class="pad" tabindex="0"><div class="pad-strings">${'<i></i>'.repeat(6)}</div><div class="hand"></div><div class="pad-fb"></div></div>
    <div class="row gap center tapbtns"><button class="btn big-arrow" data-d="D">↓</button><button class="btn big-arrow" data-d="U">↑</button></div>
    <div class="row gap center wrap ctrls">
      <button class="btn ghost demo">▶ Демо</button>
      ${o.mode !== 'mic' ? '<button class="btn primary tap">Проверить меня</button>' : ''}
      ${o.mode !== 'tap' ? '<button class="btn primary micb">🎤 Проверить на гитаре</button>' : ''}
    </div>
    <div class="row gap center wrap small-opts">
      <label class="chk"><input type="checkbox" class="clk" checked> Щелчки</label>
      ${o.mode !== 'tap' ? '<label class="chk"><input type="checkbox" class="hp"> Щелчки в наушниках</label>' : ''}
    </div>
    <div class="status"></div>
    <div class="result"></div>
  </div>`;

  let pattern = o.pattern, bpm = o.bpm, prog = chords;
  let clock = null, run = null, raf = 0;
  const grid = $('.grid8', el), pad = $('.pad', el), hand = $('.hand', el), padFb = $('.pad-fb', el);

  function drawGrid(marks = {}) {
    const cells = PATTERNS[pattern].cells;
    grid.innerHTML = cells.map((c, i) => `<div class="cell ${marks[i] || ''}" data-i="${i}"><div class="arr">${c === 'D' ? '↓' : c === 'U' ? '↑' : c === 'X' ? '✕' : '·'}</div><div class="cnt">${COUNT[i]}</div></div>`).join('');
  }
  drawGrid();
  const setChordLabel = bar => {
    const cur = prog[bar % prog.length], nxt = prog[(bar + 1) % prog.length];
    $('.cur-ch', el).textContent = cur || '—';
    $('.next-ch', el).textContent = prog.length > 1 ? `дальше: ${nxt}` : '';
  };
  setChordLabel(0);

  if (free) {
    el.querySelectorAll('.chip[data-p]').forEach(b => b.onclick = () => {
      el.querySelectorAll('.chip[data-p]').forEach(x => x.classList.toggle('on', x === b));
      pattern = b.dataset.p; drawGrid();
    });
    el.querySelectorAll('.chip.ch').forEach(b => b.onclick = () => {
      el.querySelectorAll('.chip.ch').forEach(x => x.classList.toggle('on', x === b));
      prog = b.dataset.c.split(','); setChordLabel(0);
    });
  }
  const setBpm = v => { bpm = Math.max(40, Math.min(180, v)); $('.bpm b', el).textContent = bpm; clock && clock.setBpm(bpm); };
  $('.minus', el).onclick = () => setBpm(bpm - 5);
  $('.plus', el).onclick = () => setBpm(bpm + 5);

  // run: {kind:'demo'|'tap'|'mic', t0, expected:[], strokes:[], countIn}
  function start(kind) {
    stop();
    $('.result', el).innerHTML = '';
    const c = ctx();
    const cells = PATTERNS[pattern].cells;
    const countIn = kind === 'demo' ? 0 : 8;
    const total = kind === 'demo' ? Infinity : countIn + o.bars * 8;
    const clicks = $('.clk', el).checked;
    const hp = $('.hp', el) && $('.hp', el).checked;
    run = { kind, expected: [], strokes: [], countIn, total, cells };
    clock = new Clock(bpm, (t, step) => {
      if (step >= total) { if (step === total) setTimeout(() => finish(), (t - c.currentTime) * 1000 + 300); return; }
      const inPlay = step >= countIn, ps = step - countIn, cell = cells[((ps % 8) + 8) % 8];
      const bar = Math.floor(ps / 8);
      if (step % 2 === 0) {
        const countClick = !inPlay;
        const playClick = inPlay && clicks && (kind !== 'mic' || hp);
        if (countClick || playClick) click(t, step % 8 === 0);
      }
      if (inPlay && cell) {
        if (kind === 'demo') strum(prog[bar % prog.length], cell, t);
        else run.expected.push({ t, dir: cell === 'X' ? 'D' : cell, cell: ps % 8, hit: null });
      }
      const delay = Math.max(0, (t - c.currentTime) * 1000);
      setTimeout(() => {
        if (!run) return;
        if (inPlay) {
          grid.querySelectorAll('.cell').forEach((x, i) => x.classList.toggle('now', i === ps % 8));
          if (ps % 8 === 0) setChordLabel(bar);
        } else {
          $('.cur-ch', el).textContent = `${(step >> 1) + 1}…`;
          $('.next-ch', el).textContent = 'отсчёт';
        }
        if (step % 2 === 0) { const f = $('.beat-flash', el); f.classList.remove('on'); void f.offsetWidth; f.classList.add('on'); }
      }, delay);
    });
    run.t0 = clock.start(0.2) + countIn * clock.stepDur;
    activity.add('strum');
    animate();
    if (kind === 'mic') {
      startMic($('.status', el)).then(ok => {
        if (!ok) return stop();
        mic.setSens(S.settings.sens);
        run && (run.off = mic.onOnset(t => addStroke(t - latency(), null)));
      });
    }
    el.querySelector('.strum').classList.toggle('testing', kind !== 'demo');
    $('.demo', el).textContent = kind === 'demo' ? '⏹ Стоп' : '▶ Демо';
  }

  function latency() { return S.settings.latency ?? 0.06; }

  function animate() {
    cancelAnimationFrame(raf);
    const c = ctx();
    const loop = () => {
      if (!run) return;
      const st = 60 / bpm / 2;
      const ph = (c.currentTime - (run.t0 - run.countIn * st)) / st;
      // вниз на чётной восьмой, вверх на нечётной; рука движется всегда
      const k = ((ph % 2) + 2) % 2;
      const y = k < 1 ? (1 - Math.cos(Math.PI * k)) / 2 : (1 + Math.cos(Math.PI * (k - 1))) / 2;
      hand.style.top = `${8 + y * 74}%`;
      raf = requestAnimationFrame(loop);
    };
    loop();
  }

  function addStroke(t, dir) {
    if (!run || run.kind === 'demo') {
      if (dir) strum(prog[0], dir);
      flashPad(dir, '');
      return;
    }
    if (run.kind === 'tap' && dir) strum(prog[Math.max(0, Math.floor((t - run.t0) / (60 / bpm) / 4)) % prog.length], dir);
    const tol = Math.min(0.13, (60 / bpm / 2) * 0.48);
    let best = null, bd = tol;
    for (const e of run.expected) { if (e.hit) continue; const d = Math.abs(t - e.t); if (d < bd) { bd = d; best = e; } }
    if (t < run.t0 - tol) return; // во время отсчёта не считаем
    if (!best) { run.strokes.push({ t, extra: true }); flashPad(dir, 'extra'); return; }
    const off = t - best.t;
    best.hit = dir && dir !== best.dir ? 'dir' : 'ok';
    best.off = off;
    run.strokes.push({ t, off });
    flashPad(dir, best.hit === 'dir' ? 'dir' : Math.abs(off) < 0.05 ? 'perfect' : off < 0 ? 'early' : 'late');
  }

  function flashPad(dir, kind) {
    const txt = { perfect: '✓ точно', early: 'рано', late: 'поздно', dir: 'не то направление', extra: 'лишний удар', '': '' }[kind];
    padFb.textContent = txt; padFb.className = `pad-fb ${kind}`;
    pad.classList.remove('hitD', 'hitU'); void pad.offsetWidth;
    pad.classList.add(dir === 'U' ? 'hitU' : 'hitD');
  }

  function finish() {
    if (!run || run.kind === 'demo') return;
    const r = run; stop();
    const exp = r.expected, hits = exp.filter(e => e.hit === 'ok'), dirErr = exp.filter(e => e.hit === 'dir');
    const extras = r.strokes.filter(s => s.extra).length;
    const acc = exp.length ? Math.round((100 * hits.length) / (exp.length + extras * 0.5)) : 0;
    const offs = exp.filter(e => e.hit).map(e => e.off);
    const mean = offs.length ? offs.reduce((a, b) => a + b, 0) / offs.length : 0;
    const sd = offs.length ? Math.sqrt(offs.reduce((a, b) => a + (b - mean) ** 2, 0) / offs.length) : 0;
    // по ячейкам
    const per = {};
    exp.forEach(e => { per[e.cell] = per[e.cell] || { n: 0, ok: 0, miss: 0, dir: 0 }; per[e.cell].n++; if (e.hit === 'ok') per[e.cell].ok++; else if (e.hit === 'dir') per[e.cell].dir++; else per[e.cell].miss++; });
    const marks = {};
    Object.entries(per).forEach(([i, p]) => (marks[i] = p.ok / p.n >= 0.75 ? 'good' : p.ok / p.n >= 0.4 ? 'mid' : 'bad'));
    drawGrid(marks);
    const hints = [];
    if (!offs.length && extras) hints.push('Удары слышны, но мимо долей. Слушайте отсчёт «1-2-3-4» и бейте вместе со вспышкой кружка.');
    else if (!offs.length) hints.push(r.kind === 'mic' ? 'Микрофон не услышал ударов. Играйте громче, положите телефон ближе или увеличьте чувствительность в «Прогресс → Настройки».' : 'Ударов не было. Свайпайте по полосе со струнами или жмите ↓ ↑.');
    else {
      if (mean > 0.04) hints.push(`Вы опаздываете в среднем на ${Math.round(mean * 1000)} мс. Начинайте движение чуть раньше щелчка.`);
      if (mean < -0.04) hints.push(`Вы спешите в среднем на ${Math.round(-mean * 1000)} мс. Слушайте щелчок, не убегайте вперёд.`);
      if (sd > 0.045) hints.push('Ритм неровный. Считайте вслух «раз-и-два-и» и держите руку в постоянном движении.');
      if (dirErr.length) {
        const cell = Object.entries(per).sort((a, b) => b[1].dir - a[1].dir)[0];
        hints.push(`Путаете направление (${dirErr.length} раз), чаще всего на «${COUNT[cell[0]]}». На цифрах рука идёт вниз, на «и» — вверх.`);
      }
      const worst = Object.entries(per).filter(([, p]) => p.miss / p.n > 0.5).map(([i]) => `«${COUNT[i]}»`);
      if (worst.length) hints.push(`Пропускаете удары на ${worst.join(', ')}.`);
      if (extras > 1) hints.push(`Лишних ударов: ${extras}. Там, где пауза (·), рука проходит мимо струн.`);
      if (!hints.length) hints.push('Отлично! Поднимите темп на 5 ударов в минуту.');
    }
    const pass = acc >= (r.kind === 'mic' ? 75 : 80);
    $('.result', el).innerHTML = `<div class="res ${pass ? 'pass' : ''}"><div class="big">${acc}%</div>
      <div>точность · попаданий ${hits.length} из ${exp.length}${offs.length ? ` · разброс ±${Math.round(sd * 1000)} мс` : ''}</div>
      <ul class="list">${hints.map(h => `<li>${h}</li>`).join('')}</ul></div>`;
    setBest(`strum:${pattern}:${bpm}`, acc);
    o.onResult && o.onResult({ acc, pass, kind: r.kind });
  }

  function stop() {
    if (clock) clock.stop(); clock = null;
    cancelAnimationFrame(raf);
    if (run && run.off) run.off();
    if (run && run.kind === 'mic') stopMic();
    run = null; activity.delete('strum');
    grid.querySelectorAll('.cell').forEach(x => x.classList.remove('now'));
    el.querySelector('.strum').classList.remove('testing');
    $('.demo', el).textContent = '▶ Демо';
    setChordLabel(0);
  }

  $('.demo', el).onclick = () => (run && run.kind === 'demo' ? stop() : start('demo'));
  $('.tap', el) && ($('.tap', el).onclick = () => start('tap'));
  $('.micb', el) && ($('.micb', el).onclick = () => start('mic'));

  // Ввод: свайп по полосе, кнопки, стрелки клавиатуры
  const toAudio = ts => ctx().currentTime + (ts - performance.now()) / 1000;
  let down = null;
  pad.addEventListener('pointerdown', e => { down = { y: e.clientY, used: false }; pad.setPointerCapture(e.pointerId); });
  pad.addEventListener('pointermove', e => {
    if (!down || down.used) return;
    const dy = e.clientY - down.y;
    if (Math.abs(dy) > 14) { down.used = true; addStroke(toAudio(e.timeStamp), dy > 0 ? 'D' : 'U'); }
  });
  pad.addEventListener('pointerup', () => (down = null));
  el.querySelectorAll('.big-arrow').forEach(b => b.addEventListener('pointerdown', e => { e.preventDefault(); addStroke(toAudio(e.timeStamp), b.dataset.d); }));
  const onKey = e => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); addStroke(toAudio(e.timeStamp), e.key === 'ArrowDown' ? 'D' : 'U'); }
  };
  document.addEventListener('keydown', onKey);
  return () => { stop(); document.removeEventListener('keydown', onKey); };
}

// ============ Метроном ============
export function Metronome(el) {
  el.innerHTML = `<div class="checker metro">
    <div class="row gap center bpm-row"><button class="btn ghost sm m10">−10</button><button class="btn ghost sm m1">−1</button>
      <div class="bpm"><b>80</b> уд/мин</div><button class="btn ghost sm p1">+1</button><button class="btn ghost sm p10">+10</button></div>
    <input type="range" min="40" max="200" value="80" class="slider">
    <div class="dots"></div>
    <div class="chips"><button class="chip on" data-b="4">4/4</button><button class="chip" data-b="3">3/4</button><button class="chip" data-b="2">2/4</button></div>
    <div class="row gap center"><button class="btn primary start">▶ Старт</button><button class="btn ghost tapt">Тап-темп</button></div></div>`;
  let bpm = 80, beats = 4, clock = null, taps = [];
  const dots = $('.dots', el);
  const drawDots = () => (dots.innerHTML = '<i></i>'.repeat(beats));
  drawDots();
  const set = v => { bpm = Math.max(40, Math.min(200, Math.round(v))); $('.bpm b', el).textContent = bpm; $('.slider', el).value = bpm; clock && clock.setBpm(bpm); };
  [['m10', -10], ['m1', -1], ['p1', 1], ['p10', 10]].forEach(([c, d]) => ($(`.${c}`, el).onclick = () => set(bpm + d)));
  $('.slider', el).oninput = e => set(+e.target.value);
  el.querySelectorAll('.chip').forEach(b => b.onclick = () => { el.querySelectorAll('.chip').forEach(x => x.classList.toggle('on', x === b)); beats = +b.dataset.b; drawDots(); });
  $('.tapt', el).onclick = () => {
    const now = performance.now(); taps = taps.filter(t => now - t < 3000); taps.push(now);
    if (taps.length >= 3) set(60000 / ((taps[taps.length - 1] - taps[0]) / (taps.length - 1)));
  };
  function stop() { clock && clock.stop(); clock = null; activity.delete('metro'); $('.start', el).textContent = '▶ Старт'; }
  $('.start', el).onclick = () => {
    if (clock) return stop();
    const c = ctx();
    clock = new Clock(bpm, (t, step) => {
      const b = step % beats; click(t, b === 0);
      setTimeout(() => dots.querySelectorAll('i').forEach((d, i) => d.classList.toggle('on', i === b)), Math.max(0, (t - c.currentTime) * 1000));
    }, 1);
    clock.start(); activity.add('metro');
    $('.start', el).textContent = '⏹ Стоп';
  };
  return stop;
}

// ============ Калибровка задержки микрофона ============
export async function calibrateLatency(statusEl) {
  if (!(await startMic(statusEl))) return null;
  const c = ctx(), heard = [], times = [];
  const off = mic.onOnset(t => heard.push(t));
  const t0 = c.currentTime + 0.4;
  for (let k = 0; k < 8; k++) { const t = t0 + k * 0.5; times.push(t); click(t, true); }
  await new Promise(r => setTimeout(r, 4700));
  off(); stopMic();
  const offs = times.map(t => { const h = heard.filter(x => x > t - 0.02 && x < t + 0.35); return h.length ? h[0] - t : null; }).filter(v => v != null);
  if (offs.length < 4) return null;
  const lat = median(offs);
  S.settings.latency = Math.round(lat * 1000) / 1000; save();
  return lat;
}
