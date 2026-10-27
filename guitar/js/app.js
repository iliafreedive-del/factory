// Экраны приложения и навигация.
import { LESSONS, CHORDS } from './data.js';
import { S, save, addSeconds, todayMinutes, streak, markDone, isDone, lessonProgress, dayKey, resetAll } from './store.js';
import { chordSVG, fretboardSVG, illustration } from './svg.js';
import { strum, beep, ctx } from './audio.js';
import { activity } from './activity.js';
import { $, html, Tuner, NoteChecker, ChordChecker, ChangesCounter, TimerWidget, Quiz, StrumTrainer, Metronome, calibrateLatency, fmt } from './components.js';

const main = $('#main');
let cleanup = [];
const onLeave = fn => fn && cleanup.push(fn);

// ---------- учёт времени и занятие ----------
let session = null; // {plan, idx, left, paused}
let tick = 0;
setInterval(() => {
  if (session && !session.paused) {
    session.left--;
    if (session.left <= 0) nextPhase();
    renderSessionBar();
  }
  if ((activity.size || (session && !session.paused)) && !document.hidden) {
    addSeconds(1);
    if (++tick % 15 === 0) save();
    renderBadge();
  }
}, 1000);
document.addEventListener('visibilitychange', () => document.hidden && save());

function renderBadge() {
  $('#today').textContent = `⏱ ${todayMinutes()}/${S.settings.goal} мин`;
}

function currentLesson() {
  return LESSONS.find(l => lessonProgress(l) < 1) || LESSONS[LESSONS.length - 1];
}

function sessionPlan(goal) {
  const l = currentLesson();
  const warm = Math.max(2, Math.round(goal * 0.15)), main = Math.max(4, Math.round(goal * 0.5)), rep = Math.max(2, Math.round(goal * 0.2));
  const free = Math.max(1, goal - 2 - warm - main - rep);
  return [
    { name: 'Настройка', min: 2, link: '#/tuner', desc: 'Проверьте строй всех 6 струн.' },
    { name: 'Разминка «паучок»', min: warm, link: '#/lesson/4', desc: 'Лады 1-2-3-4 на всех струнах, по ноте на щелчок.' },
    { name: `Урок ${l.id}: ${l.title}`, min: main, link: `#/lesson/${l.id}`, desc: l.goal },
    { name: 'Повторение', min: rep, link: '#/trainer', desc: 'Бой и смены аккордов из прошлых уроков.' },
    { name: 'Свободная игра', min: free, link: '#/chords', desc: 'Играйте то, что нравится: аккорды, мелодии, песни.' },
  ];
}

function startSession() {
  const plan = sessionPlan(S.settings.goal);
  session = { plan, idx: 0, left: plan[0].min * 60, paused: false };
  ctx();
  renderSessionBar();
  location.hash = plan[0].link;
}
function nextPhase() {
  beep(880, 0.3);
  session.idx++;
  if (session.idx >= session.plan.length) {
    session = null; save();
    toast('🎉 Занятие закончено! Отличная работа.');
    renderSessionBar();
    return;
  }
  session.left = session.plan[session.idx].min * 60;
  toast(`Дальше: ${session.plan[session.idx].name}`);
}
function renderSessionBar() {
  const bar = $('#session');
  if (!session) { bar.hidden = true; return; }
  const p = session.plan[session.idx];
  bar.hidden = false;
  bar.innerHTML = `<a href="${p.link}" class="sb-name">${session.idx + 1}/${session.plan.length} · ${p.name}</a>
    <b class="sb-time">${fmt(session.left)}</b>
    <button class="sb-btn" data-a="pause">${session.paused ? '▶' : '⏸'}</button>
    <button class="sb-btn" data-a="next">⏭</button><button class="sb-btn" data-a="stop">✕</button>`;
  bar.querySelectorAll('.sb-btn').forEach(b => b.onclick = () => {
    const a = b.dataset.a;
    if (a === 'pause') session.paused = !session.paused;
    if (a === 'next') { nextPhase(); if (session) location.hash = session.plan[session.idx].link; }
    if (a === 'stop') session = null;
    renderSessionBar();
  });
}

function toast(msg) {
  const t = html(`<div class="toast">${msg}</div>`);
  document.body.append(t);
  setTimeout(() => t.classList.add('show'), 10);
  setTimeout(() => { t.classList.remove('show'); setTimeout(() => t.remove(), 400); }, 2600);
}

// ---------- экраны ----------
function ring(value, max) {
  const r = 46, c = 2 * Math.PI * r, k = Math.min(1, value / max);
  return `<svg viewBox="0 0 110 110" class="ring"><circle cx="55" cy="55" r="${r}" class="ring-bg"/>
    <circle cx="55" cy="55" r="${r}" class="ring-fg" stroke-dasharray="${c * k} ${c}" transform="rotate(-90 55 55)"/>
    <text x="55" y="54" text-anchor="middle" class="ring-v">${value}</text><text x="55" y="72" text-anchor="middle" class="ring-l">из ${max} мин</text></svg>`;
}

function viewHome() {
  const l = currentLesson(), p = lessonProgress(l), st = streak();
  const doneLessons = LESSONS.filter(x => lessonProgress(x) === 1).length;
  main.innerHTML = `
    <section class="card hero">
      ${ring(todayMinutes(), S.settings.goal)}
      <div class="hero-txt">
        <h2>Сегодня</h2>
        <p>${st ? `🔥 ${st} ${plural(st, 'день', 'дня', 'дней')} подряд` : 'Начните серию: позанимайтесь от 5 минут.'}</p>
        <p class="muted">Пройдено уроков: ${doneLessons} из ${LESSONS.length}</p>
        <button class="btn primary go">▶ Занятие на ${S.settings.goal} мин</button>
      </div>
    </section>
    <a class="card next-lesson" href="#/lesson/${l.id}">
      <div class="muted">${p > 0 ? 'Продолжить' : 'Следующий урок'}</div>
      <h3>Урок ${l.id}. ${l.title}</h3><p>${l.goal}</p>
      <div class="pbar"><i style="width:${p * 100}%"></i></div>
    </a>
    <div class="tiles">
      <a class="tile" href="#/tuner"><span>🎚</span>Тюнер</a>
      <a class="tile" href="#/trainer"><span>🥁</span>Тренажёр боя</a>
      <a class="tile" href="#/chords"><span>🎸</span>Аккорды</a>
      <a class="tile" href="#/progress"><span>📈</span>Прогресс</a>
    </div>
    <section class="card">
      <h3>Сколько заниматься</h3>
      <ul class="list">
        <li><b>Первые 2 недели: 15–20 минут в день.</b> Подушечки пальцев привыкают, через силу играть не нужно.</li>
        <li><b>Дальше: 30 минут в день.</b> Каждый день по чуть-чуть лучше, чем 2 часа раз в неделю.</li>
        <li>Каждые 10 минут — минутный перерыв: встряхните руки.</li>
        <li>Кнопка «Занятие» сама разобьёт время: настройка → разминка → урок → повторение → свободная игра.</li>
      </ul>
    </section>
    ${session ? '' : `<section class="card plan"><h3>План занятия</h3>${sessionPlan(S.settings.goal).map(ph => `<div class="ph"><b>${ph.min} мин</b> ${ph.name}<div class="muted">${ph.desc}</div></div>`).join('')}</section>`}`;
  $('.go', main).onclick = startSession;
}

function plural(n, a, b, c) { const m = n % 10, h = n % 100; return m === 1 && h !== 11 ? a : m >= 2 && m <= 4 && (h < 12 || h > 14) ? b : c; }

function viewLessons() {
  main.innerHTML = `<h2 class="page-t">Уроки</h2><p class="muted">Идите по порядку: каждый урок опирается на предыдущий. Один урок — 1–3 дня занятий.</p>
    <div class="lessons">${LESSONS.map(l => {
      const p = lessonProgress(l);
      return `<a class="card lesson-card ${p === 1 ? 'done' : ''}" href="#/lesson/${l.id}">
        <div class="num">${p === 1 ? '✓' : l.id}</div>
        <div class="lc-body"><b>${l.title}</b><div class="muted">${l.goal}</div>
        <div class="pbar"><i style="width:${p * 100}%"></i></div></div></a>`;
    }).join('')}</div>`;
}

const EX_ICONS = { quiz: '❓', timer: '⏱', tuner: '🎚', notes: '🎵', chord: '🎸', changes: '🔁', strum: '👆', rhythm: '🎤' };

function viewLesson(id) {
  const l = LESSONS.find(x => x.id === id);
  if (!l) return viewLessons();
  const prev = LESSONS.find(x => x.id === id - 1), next = LESSONS.find(x => x.id === id + 1);
  main.innerHTML = `<a href="#/lessons" class="back">← Все уроки</a>
    <h2 class="page-t">Урок ${l.id}. ${l.title}</h2>
    <div class="goal">🎯 ${l.goal} <span class="muted">· ~${l.minutes} мин</span></div>
    <div class="blocks">${l.blocks.map(renderBlock).join('')}</div>
    ${l.exercises.length ? `<h3>Упражнения</h3><div class="exs">${l.exercises.map(e => `
      <div class="card ex ${isDone(l.id, e.id) ? 'done' : ''}" data-id="${e.id}">
        <div class="ex-head"><span class="ex-st">${isDone(l.id, e.id) ? '✓' : EX_ICONS[e.type]}</span><b>${e.title}</b>
          <button class="btn sm open">Начать</button></div>
        ${e.desc ? `<p class="muted">${e.desc}</p>` : ''}
        <div class="ex-body"></div>
        <button class="linkbtn manual" ${isDone(l.id, e.id) ? 'hidden' : ''}>Отметить выполненным вручную</button>
      </div>`).join('')}</div>`
      : `<button class="btn primary readbtn">${S.read[l.id] ? '✓ Прочитано' : 'Отметить прочитанным'}</button>`}
    <div class="row between nav-lessons">${prev ? `<a class="btn ghost" href="#/lesson/${prev.id}">← Урок ${prev.id}</a>` : '<span></span>'}
      ${next ? `<a class="btn ghost" href="#/lesson/${next.id}">Урок ${next.id} →</a>` : ''}</div>`;

  main.querySelectorAll('.chord-block .play').forEach(b => b.onclick = () => strum(b.dataset.c, 'D'));
  const rb = $('.readbtn', main);
  if (rb) rb.onclick = () => { S.read[l.id] = dayKey(); save(); rb.textContent = '✓ Прочитано'; toast('Урок пройден!'); };

  let openClean = null;
  const complete = (e, card) => {
    if (markDone(l.id, e.id)) toast('✓ Упражнение выполнено!');
    card.classList.add('done');
    $('.ex-st', card).textContent = '✓';
    $('.manual', card).hidden = true;
    if (lessonProgress(l) === 1) setTimeout(() => toast(`🎉 Урок ${l.id} пройден!${next ? ' Можно переходить к следующему.' : ''}`), 1200);
  };
  main.querySelectorAll('.ex').forEach(card => {
    const e = l.exercises.find(x => x.id === card.dataset.id);
    $('.manual', card).onclick = () => complete(e, card);
    $('.open', card).onclick = () => {
      const body = $('.ex-body', card);
      const wasOpen = card.classList.contains('open');
      openClean && openClean(); openClean = null;
      main.querySelectorAll('.ex').forEach(c => { c.classList.remove('open'); $('.ex-body', c).innerHTML = ''; $('.open', c).textContent = 'Начать'; });
      if (wasOpen) return;
      card.classList.add('open'); $('.open', card).textContent = 'Свернуть';
      openClean = mountExercise(e, body, () => complete(e, card));
    };
  });
  onLeave(() => openClean && openClean());
}

function mountExercise(e, body, onDone) {
  switch (e.type) {
    case 'quiz': return Quiz(body, { ...e, onDone });
    case 'timer': return TimerWidget(body, { seconds: e.seconds, metronome: e.metronome, onDone });
    case 'tuner': return Tuner(body, { onAllTuned: onDone });
    case 'notes': return NoteChecker(body, { targets: e.targets, onDone });
    case 'chord': return ChordChecker(body, { chord: e.chord, need: e.need, onDone });
    case 'changes': return ChangesCounter(body, { chords: e.chords, goal: e.goal, onDone, bestKey: `changes:${e.chords.join('-')}` });
    case 'strum':
    case 'rhythm':
      return StrumTrainer(body, { ...e, mode: e.type === 'strum' ? 'tap' : 'mic', onResult: r => r.pass && onDone() });
  }
}

function renderBlock(b) {
  switch (b.type) {
    case 'text': return `<div class="txt">${b.html}</div>`;
    case 'tip': return `<div class="tip">💡 ${b.html}</div>`;
    case 'svg': return illustration(b.id);
    case 'chord': {
      const ch = CHORDS[b.chord];
      return `<div class="card chord-block"><div class="diagram">${chordSVG(b.chord)}</div><div><b>${ch.name}</b> — ${ch.ru}<br><button class="btn ghost sm play" data-c="${b.chord}">▶ Послушать</button></div></div>`;
    }
    case 'fretboard': return `<figure class="figure scroll-x">${fretboardSVG(b.marks.map(m => ({ ...m, cls: 'done' })), 5)}<figcaption>Номера струн слева, ладов снизу</figcaption></figure>`;
  }
  return '';
}

function viewChords(sel) {
  main.innerHTML = `<h2 class="page-t">Аккорды</h2>
    <p class="muted">Нажмите на аккорд, чтобы послушать его и проверить себя через микрофон.</p>
    <div class="check-area"></div>
    <div class="chord-grid">${Object.values(CHORDS).map(c => `<button class="card chord-card ${c.name === sel ? 'on' : ''}" data-c="${c.name}">${chordSVG(c.name)}<span>${c.ru}</span></button>`).join('')}</div>
    <section class="card"><h3>Как читать схему</h3><ul class="list">
      <li>Вертикальные линии — струны: слева 6-я (толстая), справа 1-я.</li>
      <li>Горизонтальные — ладовые порожки, толстая линия сверху — верхний порожек у головы.</li>
      <li>Цифра в кружке — палец: 1 указательный, 2 средний, 3 безымянный, 4 мизинец.</li>
      <li>○ — открытая струна, ✕ — не играть.</li></ul></section>`;
  let clean = null;
  const area = $('.check-area', main);
  const choose = name => {
    clean && clean();
    main.querySelectorAll('.chord-card').forEach(c => c.classList.toggle('on', c.dataset.c === name));
    area.innerHTML = `<div class="card"></div>`;
    clean = ChordChecker(area.firstElementChild, { chord: name, need: Infinity });
    strum(name, 'D');
    area.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
  main.querySelectorAll('.chord-card').forEach(b => b.onclick = () => choose(b.dataset.c));
  if (sel && CHORDS[sel]) choose(sel);
  onLeave(() => clean && clean());
}

function viewTrainer(tab = 'strum') {
  main.innerHTML = `<h2 class="page-t">Тренажёр</h2>
    <div class="seg"><a href="#/trainer" class="${tab === 'strum' ? 'on' : ''}">Бой</a><a href="#/trainer/metro" class="${tab === 'metro' ? 'on' : ''}">Метроном</a></div>
    <div class="card body"></div>
    ${tab === 'strum' ? `<section class="card"><h3>Как пользоваться</h3><ul class="list">
      <li><b>Демо</b> — послушать бой и посмотреть, как движется рука (кружок на полосе).</li>
      <li><b>Проверить меня</b> — после отсчёта «1-2-3-4» свайпайте по полосе вниз/вверх или жмите ↓ ↑. Ячейки покрасятся: зелёные — точно, красные — промах.</li>
      <li><b>Проверить на гитаре</b> — играйте настоящей гитарой, микрофон слушает попадание в доли. Направление удара микрофон не различает, следите за ним сами.</li>
      <li>Точность 90% и выше — поднимайте темп на 5.</li></ul></section>` : ''}`;
  const body = $('.body', main);
  onLeave(tab === 'metro' ? Metronome(body) : StrumTrainer(body, { mode: 'free', pattern: 'down4', bpm: 70, chord: 'Am' }));
}

function viewTuner() {
  main.innerHTML = `<h2 class="page-t">Тюнер</h2><div class="card body"></div>
    <section class="card"><h3>Стандартный строй</h3><p>От толстой к тонкой: <b>E A D G B E</b> (ми, ля, ре, соль, си, ми). Настраивайтесь перед каждым занятием: струны, особенно новые, быстро расстраиваются.</p>
    <p class="muted">Если стрелка прыгает, приглушите остальные струны ладонью и дёргайте одну, не слишком сильно.</p></section>`;
  onLeave(Tuner($('.body', main)));
}

function viewProgress() {
  const days = [...Array(14)].map((_, i) => { const d = new Date(); d.setDate(d.getDate() - 13 + i); return d; });
  const mins = days.map(d => Math.round((S.seconds[dayKey(d)] || 0) / 60));
  const max = Math.max(S.settings.goal, ...mins);
  const total = Math.round(Object.values(S.seconds).reduce((a, b) => a + b, 0) / 60);
  const exDone = Object.keys(S.done).length, exAll = LESSONS.reduce((a, l) => a + l.exercises.length, 0);
  const bests = Object.entries(S.bests).filter(([k]) => k.startsWith('changes:'));
  const strumBest = Object.entries(S.bests).filter(([k]) => k.startsWith('strum:')).sort((a, b) => b[1] - a[1]).slice(0, 5);
  const wd = ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'];
  main.innerHTML = `<h2 class="page-t">Прогресс</h2>
    <div class="stats">
      <div class="card stat"><b>${todayMinutes()}</b><span>мин сегодня</span></div>
      <div class="card stat"><b>${streak()}</b><span>дней подряд</span></div>
      <div class="card stat"><b>${total >= 60 ? (total / 60).toFixed(1) + ' ч' : total + ' мин'}</b><span>всего</span></div>
      <div class="card stat"><b>${exDone}/${exAll}</b><span>упражнений</span></div>
    </div>
    <section class="card"><h3>Последние 14 дней</h3>
      <div class="chart">${mins.map((m, i) => `<div class="bar ${m >= S.settings.goal ? 'met' : ''}" title="${m} мин"><i style="height:${(m / max) * 100}%"></i><span>${wd[days[i].getDay()]}</span></div>`).join('')}
        <div class="goal-line" style="bottom:calc(${(S.settings.goal / max) * 100}% * .8 + 20px)"></div></div>
      <p class="muted">Время засчитывается, пока работает микрофон, метроном, таймер или занятие.</p></section>
    <section class="card"><h3>Уроки</h3>${LESSONS.map(l => `<a class="prow" href="#/lesson/${l.id}"><span>${l.id}. ${l.title}</span><span class="pbar"><i style="width:${lessonProgress(l) * 100}%"></i></span></a>`).join('')}</section>
    <section class="card"><h3>Рекорды</h3>
      ${bests.length ? bests.map(([k, v]) => `<div class="prow"><span>Смены ${k.slice(8).replace('-', ' ↔ ')}</span><b>${v}/мин</b></div>`).join('') : '<p class="muted">Пока нет. Попробуйте упражнение «Смены за минуту» в уроке 8.</p>'}
      ${strumBest.map(([k, v]) => { const [, p, b] = k.split(':'); return `<div class="prow"><span>Бой «${p}», ${b} уд/мин</span><b>${v}%</b></div>`; }).join('')}
    </section>
    <section class="card settings"><h3>Настройки</h3>
      <label>Цель на день
        <select class="goal">${[10, 15, 20, 30, 45, 60].map(v => `<option ${v === S.settings.goal ? 'selected' : ''} value="${v}">${v} мин</option>`).join('')}</select></label>
      <label>Чувствительность микрофона к ударам <input type="range" class="sens" min="0.4" max="3" step="0.1" value="${S.settings.sens}"></label>
      <div class="row between"><span>Задержка микрофона: <b class="lat">${S.settings.latency != null ? Math.round(S.settings.latency * 1000) + ' мс' : 'по умолчанию 60 мс'}</b></span>
        <button class="btn sm ghost calib">Калибровать</button></div>
      <p class="muted">Калибровка: положите телефон на стол в тишине. Приложение сыграет 8 щелчков и измерит, с какой задержкой их слышит микрофон. Так проверка ритма будет точнее.</p>
      <div class="status"></div>
      <button class="btn ghost danger reset">Сбросить весь прогресс</button>
    </section>`;
  $('.goal', main).onchange = e => { S.settings.goal = +e.target.value; save(); renderBadge(); };
  $('.sens', main).onchange = e => { S.settings.sens = +e.target.value; save(); };
  $('.calib', main).onclick = async () => {
    $('.lat', main).textContent = 'слушаю…';
    const lat = await calibrateLatency($('.status', main));
    $('.lat', main).textContent = lat == null ? 'не получилось, попробуйте громче' : `${Math.round(lat * 1000)} мс`;
  };
  $('.reset', main).onclick = () => confirm('Удалить весь прогресс и время занятий?') && resetAll();
}

// ---------- роутер ----------
function route() {
  cleanup.forEach(fn => { try { fn(); } catch (e) { console.error(e); } });
  cleanup = [];
  const [, view, arg] = (location.hash || '#/').split('/');
  document.querySelectorAll('.nav a').forEach(a => a.classList.toggle('on', a.dataset.v === (view || 'home') || (view === 'lesson' && a.dataset.v === 'lessons')));
  switch (view) {
    case 'lessons': viewLessons(); break;
    case 'lesson': viewLesson(+arg); break;
    case 'chords': viewChords(arg && decodeURIComponent(arg)); break;
    case 'trainer': viewTrainer(arg); break;
    case 'tuner': viewTuner(); break;
    case 'progress': viewProgress(); break;
    default: viewHome();
  }
  window.scrollTo(0, 0);
}
window.addEventListener('hashchange', route);
route();
renderBadge();
renderSessionBar();

if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js');
