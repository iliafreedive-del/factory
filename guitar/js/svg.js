// SVG-рисунки: схемы аккордов, гриф, постановка рук.
import { CHORDS, OPEN, noteName } from './data.js';

const ink = 'var(--ink)', soft = 'var(--soft)', acc = 'var(--acc)', wood = 'var(--wood)';

// Схема аккорда: вертикальный гриф, слева 6-я струна.
// opts.bad: индексы струн (0 = 6-я), которые подсветить красным
export function chordSVG(name, opts = {}) {
  const ch = CHORDS[name];
  const W = 170, H = 228, x0 = 38, y0 = 46, dx = 22, dy = 30, frets = 5;
  const bad = new Set(opts.bad || []);
  let s = `<svg viewBox="0 0 ${W} ${H}" class="chord-svg" role="img" aria-label="Аккорд ${ch.name}">`;
  s += `<text x="${x0 + dx * 2.5}" y="18" text-anchor="middle" class="t-title">${ch.name}</text>`;
  s += `<rect x="${x0}" y="${y0}" width="${dx * 5}" height="5" fill="${ink}"/>`;
  for (let f = 1; f <= frets; f++) s += `<line x1="${x0}" x2="${x0 + dx * 5}" y1="${y0 + f * dy}" y2="${y0 + f * dy}" stroke="${soft}" stroke-width="2"/>`;
  for (let i = 0; i < 6; i++) {
    const x = x0 + i * dx, col = bad.has(i) ? 'var(--bad)' : ink;
    s += `<line x1="${x}" x2="${x}" y1="${y0}" y2="${y0 + frets * dy}" stroke="${col}" stroke-width="${1 + (5 - i) * 0.35}"/>`;
    const f = ch.frets[i];
    if (f < 0) s += `<text x="${x}" y="${y0 - 10}" text-anchor="middle" class="t-mark" fill="var(--bad)">✕</text>`;
    else if (f === 0) s += `<circle cx="${x}" cy="${y0 - 15}" r="6" fill="none" stroke="${bad.has(i) ? 'var(--bad)' : ink}" stroke-width="2"/>`;
    else {
      const cy = y0 + (f - 0.5) * dy;
      s += `<circle cx="${x}" cy="${cy}" r="9.5" fill="${bad.has(i) ? 'var(--bad)' : acc}"/>`;
      s += `<text x="${x}" y="${cy + 4.5}" text-anchor="middle" class="t-finger">${ch.fingers[i]}</text>`;
    }
    if (f >= 0) s += `<text x="${x}" y="${y0 + frets * dy + 18}" text-anchor="middle" class="t-small">${noteName(OPEN[i] + f).lat}</text>`;
  }
  for (let f = 1; f <= frets; f++) s += `<text x="${x0 - 24}" y="${y0 + (f - 0.5) * dy + 4}" text-anchor="middle" class="t-small">${f}</text>`;
  return s + '</svg>';
}

// Горизонтальный гриф, 1-я струна сверху (так видит гитарист, глядя вниз на гриф).
// marks: [{s, f, t, cls}] cls: 'target' | 'done' | 'hit' | 'wrong'
export function fretboardSVG(marks = [], maxFret = 12) {
  const x0 = 46, y0 = 22, dy = 18, fw = maxFret <= 6 ? 64 : 48, W = x0 + 10 + fw * maxFret, H = y0 + dy * 5 + 34;
  let s = `<svg viewBox="0 0 ${W} ${H}" class="fret-svg" role="img" aria-label="Гриф">`;
  s += `<rect x="${x0}" y="${y0 - 8}" width="${fw * maxFret}" height="${dy * 5 + 16}" rx="3" fill="${wood}"/>`;
  [3, 5, 7, 9].forEach(f => f <= maxFret && (s += `<circle cx="${x0 + (f - 0.5) * fw}" cy="${y0 + dy * 2.5}" r="5" fill="var(--inlay)"/>`));
  if (maxFret >= 12) [1.5, 3.5].forEach(k => (s += `<circle cx="${x0 + 11.5 * fw}" cy="${y0 + dy * k}" r="5" fill="var(--inlay)"/>`));
  s += `<rect x="${x0 - 4}" y="${y0 - 8}" width="6" height="${dy * 5 + 16}" fill="var(--nut)"/>`;
  for (let f = 1; f <= maxFret; f++) {
    s += `<line x1="${x0 + f * fw}" x2="${x0 + f * fw}" y1="${y0 - 8}" y2="${y0 + dy * 5 + 8}" stroke="var(--fretwire)" stroke-width="2.5"/>`;
    s += `<text x="${x0 + (f - 0.5) * fw}" y="${H - 6}" text-anchor="middle" class="t-small">${f}</text>`;
  }
  for (let n = 1; n <= 6; n++) {
    const y = y0 + (n - 1) * dy;
    s += `<line x1="${x0}" x2="${W - 10}" y1="${y}" y2="${y}" stroke="var(--string)" stroke-width="${0.8 + (n - 1) * 0.4}"/>`;
    s += `<text x="8" y="${y + 4}" text-anchor="middle" class="t-small">${n}</text>`;
  }
  for (const m of marks) {
    const y = y0 + (m.s - 1) * dy;
    const x = m.f === 0 ? x0 - 22 : x0 + (m.f - 0.5) * fw;
    const r = m.f === 0 ? 7 : 8.5;
    s += `<circle cx="${x}" cy="${y}" r="${r}" class="fm ${m.cls || 'target'}"/>`;
    if (m.t) s += `<text x="${x}" y="${y - 11}" text-anchor="middle" class="t-label">${m.t}</text>`;
  }
  return s + '</svg>';
}

function guitarShape(tx, ty, rot, scale = 1) {
  return `<g transform="translate(${tx} ${ty}) rotate(${rot}) scale(${scale})">
    <rect x="58" y="-7" width="150" height="14" rx="2" fill="#6b4a2b"/>
    ${[78, 98, 116, 133, 149, 164, 178, 191].map(x => `<line x1="${x}" x2="${x}" y1="-7" y2="7" stroke="#cfc6b8" stroke-width="1.3"/>`).join('')}
    <path d="M206 -10 L238 -13 L238 13 L206 10 Z" fill="#4a3220"/>
    ${[214, 224, 234].map(x => `<circle cx="${x}" cy="-15" r="3" fill="#bbb"/><circle cx="${x}" cy="15" r="3" fill="#bbb"/>`).join('')}
    <path d="M-60 0 C-60 -48 -22 -50 -4 -34 C8 -24 18 -40 40 -40 C66 -40 70 -16 70 0 C70 16 66 40 40 40 C18 40 8 24 -4 34 C-22 50 -60 48 -60 0 Z" fill="#d9a35b" stroke="#8a5a2b" stroke-width="3"/>
    <circle cx="26" cy="0" r="14" fill="#2b1c10"/>
    <rect x="-40" y="-14" width="8" height="28" rx="2" fill="#5a3a20"/>
    ${[-5, -3, -1, 1, 3, 5].map(y => `<line x1="-36" x2="238" y1="${y}" y2="${y}" stroke="#eee" stroke-width="0.6"/>`).join('')}
  </g>`;
}

const label = (x, y, txt, anchor = 'start') => `<text x="${x}" y="${y}" text-anchor="${anchor}" class="t-label">${txt}</text>`;
const arrow = (x1, y1, x2, y2) => `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${acc}" stroke-width="1.5" marker-end="url(#ah)"/>`;
const defs = `<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="${acc}"/></marker></defs>`;

export const ILLUSTRATIONS = {
  parts: {
    caption: 'Устройство гитары',
    svg: `<svg viewBox="0 0 360 200" class="ill">${defs}
      ${guitarShape(70, 105, 0, 1.15)}
      ${label(250, 40, 'Голова и колки', 'middle')}${arrow(290, 46, 320, 82)}
      ${label(200, 175, 'Гриф с ладами', 'middle')}${arrow(200, 162, 200, 116)}
      ${label(60, 30, 'Корпус', 'middle')}${arrow(60, 36, 50, 62)}
      ${label(130, 30, 'Розетка', 'middle')}${arrow(120, 36, 100, 92)}
      ${label(20, 190, 'Подставка')}${arrow(40, 178, 30, 120)}
      ${label(305, 175, '1-й лад', 'middle')}${arrow(295, 162, 278, 114)}
    </svg>`,
  },
  posture: {
    caption: 'Посадка: вид спереди',
    svg: `<svg viewBox="0 0 360 260" class="ill">${defs}
      <rect x="110" y="168" width="110" height="10" rx="3" fill="${soft}"/>
      <rect x="118" y="178" width="8" height="70" fill="${soft}"/><rect x="204" y="178" width="8" height="70" fill="${soft}"/>
      <circle cx="165" cy="38" r="20" fill="none" stroke="${ink}" stroke-width="3"/>
      <path d="M140 66 L190 66 L186 160 L144 160 Z" fill="none" stroke="${ink}" stroke-width="3"/>
      <path d="M144 160 L130 170 L132 246 M186 160 L196 170 L194 246" fill="none" stroke="${ink}" stroke-width="3"/>
      <path d="M124 246 L142 246 M188 246 L206 246" stroke="${ink}" stroke-width="4"/>
      ${guitarShape(140, 140, -16, 0.72)}
      <path d="M142 72 L120 104 L140 128" fill="none" stroke="${ink}" stroke-width="3"/>
      <path d="M188 72 L230 104 L262 86" fill="none" stroke="${ink}" stroke-width="3"/>
      ${label(8, 70, 'Плечи опущены')}${arrow(60, 74, 138, 72)}
      ${label(8, 120, 'Предплечье')}${label(8, 134, 'на корпусе')}${arrow(70, 122, 118, 110)}
      ${label(250, 46, 'Гриф чуть вверх')}${arrow(290, 52, 280, 72)}
      ${label(250, 140, 'Спина прямая')}${arrow(248, 136, 192, 116)}
      ${label(240, 230, 'Ступни на полу')}${arrow(238, 234, 208, 244)}
    </svg>`,
  },
  fingers: {
    caption: 'Номера пальцев левой руки',
    svg: `<svg viewBox="0 0 380 190" class="ill">
      <path d="M90 180 L90 110 Q90 95 105 95 L215 95 Q230 95 230 110 L230 180" fill="var(--skin)" stroke="${ink}" stroke-width="2"/>
      ${[[105, 30, '1', 'указательный'], [140, 14, '2', 'средний'], [175, 22, '3', 'безымянный'], [208, 44, '4', 'мизинец']].map(([x, y, n, t]) =>
        `<rect x="${x - 13}" y="${y}" width="26" height="${100 - y}" rx="13" fill="var(--skin)" stroke="${ink}" stroke-width="2"/>
         <circle cx="${x}" cy="${y + 16}" r="11" fill="${acc}"/><text x="${x}" y="${y + 21}" text-anchor="middle" class="t-finger">${n}</text>`).join('')}
      <rect x="40" y="120" width="60" height="24" rx="12" transform="rotate(-25 70 132)" fill="var(--skin)" stroke="${ink}" stroke-width="2"/>
      <text x="6" y="170" class="t-label">большой (T)</text>
      ${label(250, 70, '1 — указательный')}${label(250, 92, '2 — средний')}${label(250, 114, '3 — безымянный')}${label(250, 136, '4 — мизинец')}
    </svg>`,
  },
  leftFront: {
    caption: 'Левая рука: куда ставить пальцы',
    svg: `<svg viewBox="0 0 360 200" class="ill">${defs}
      <rect x="20" y="40" width="320" height="100" fill="${wood}"/>
      <rect x="20" y="40" width="7" height="100" fill="var(--nut)"/>
      ${[95, 170, 245, 320].map(x => `<line x1="${x}" x2="${x}" y1="40" y2="140" stroke="var(--fretwire)" stroke-width="4"/>`).join('')}
      ${[0, 1, 2, 3, 4, 5].map(i => `<line x1="20" x2="340" y1="${50 + i * 16}" y2="${50 + i * 16}" stroke="var(--string)" stroke-width="${0.8 + i * 0.45}"/>`).join('')}
      ${[[82, 50, 1], [157, 66, 2], [232, 82, 3], [307, 98, 4]].map(([x, y, n]) =>
        `<path d="M${x} ${y} Q${x - 6} ${y + 60} ${x - 14} 200" stroke="var(--skin)" stroke-width="20" fill="none" stroke-linecap="round" opacity=".9"/>
         <circle cx="${x}" cy="${y}" r="9" fill="${acc}"/><text x="${x}" y="${y + 4}" text-anchor="middle" class="t-finger">${n}</text>`).join('')}
      <ellipse cx="150" cy="128" rx="20" ry="9" fill="none" stroke="${ink}" stroke-dasharray="4 3" stroke-width="2"/>
      ${label(20, 22, 'Кончик пальца — у самого порожка, со стороны корпуса')}
      ${arrow(110, 28, 92, 46)}
      ${label(178, 166, 'Большой палец за грифом')}${label(178, 182, '(пунктир), напротив 2-го')}${arrow(176, 160, 160, 134)}
    </svg>`,
  },
  leftSide: {
    caption: 'Левая рука: вид сбоку на гриф',
    svg: `<svg viewBox="0 0 360 210" class="ill">${defs}
      <path d="M130 70 L230 70 Q240 70 238 84 Q224 132 180 136 Q136 132 122 84 Q120 70 130 70 Z" fill="${wood}" stroke="${ink}" stroke-width="2"/>
      ${[140, 156, 172, 188, 204, 220].map((x, i) => `<circle cx="${x}" cy="64" r="${1.8 + (5 - i) * 0.35}" fill="var(--string)"/>`).join('')}
      <path d="M216 63 Q214 30 240 22 Q280 14 300 60 Q310 110 280 160" fill="none" stroke="var(--skin)" stroke-width="20" stroke-linecap="round"/>
      <path d="M216 63 Q214 30 240 22 Q280 14 300 60 Q310 110 280 160" fill="none" stroke="${ink}" stroke-width="1.5" stroke-dasharray="2 4"/>
      <path d="M150 150 Q170 175 200 170" fill="none" stroke="var(--skin)" stroke-width="18" stroke-linecap="round"/>
      <path d="M200 170 Q250 175 280 160" fill="none" stroke="var(--skin)" stroke-width="26" stroke-linecap="round"/>
      ${label(8, 30, 'Палец «домиком»,')}${label(8, 46, 'давим кончиком')}${arrow(110, 36, 212, 58)}
      ${label(8, 120, 'Большой палец')}${label(8, 136, 'на спинке грифа')}${arrow(104, 130, 148, 150)}
      ${label(250, 200, 'Ладонь не касается грифа', 'middle')}${arrow(260, 190, 238, 140)}
    </svg>`,
  },
  rightHand: {
    caption: 'Правая рука: бой',
    svg: `<svg viewBox="0 0 360 210" class="ill">${defs}
      <circle cx="120" cy="105" r="70" fill="#2b1c10"/>
      ${[0, 1, 2, 3, 4, 5].map(i => `<line x1="${60 + i * 24}" x2="${60 + i * 24}" y1="10" y2="200" stroke="var(--string)" stroke-width="${3 - i * 0.4}"/>`).join('')}
      <text x="60" y="206" text-anchor="middle" class="t-small">6</text><text x="180" y="206" text-anchor="middle" class="t-small">1</text>
      <ellipse cx="210" cy="96" rx="36" ry="26" fill="var(--skin)" stroke="${ink}" stroke-width="2"/>
      <path d="M190 112 L176 130" stroke="var(--skin)" stroke-width="14" stroke-linecap="round"/>
      <path d="M170 128 L180 140 L164 140 Z" fill="${acc}"/>
      <path d="M250 70 L250 140" stroke="${acc}" stroke-width="4" marker-end="url(#ah)"/>
      <path d="M268 140 L268 84" stroke="var(--soft)" stroke-width="4" marker-end="url(#ah)"/>
      ${label(282, 112, '↓ вниз:')}${label(282, 128, 'все струны')}
      ${label(282, 74, '↑ вверх:')}${label(282, 90, '1–3 струны')}
      ${label(200, 180, 'Медиатор: большой +', 'middle')}${label(200, 196, 'бок указательного', 'middle')}
      ${label(200, 30, 'Кисть свободная,', 'middle')}${label(200, 46, 'движение от запястья', 'middle')}
    </svg>`,
  },
};

export function illustration(id) {
  const it = ILLUSTRATIONS[id];
  return `<figure class="figure">${it.svg}<figcaption>${it.caption}</figcaption></figure>`;
}
