// Прогресс и настройки в localStorage.
const KEY = 'guitar-app-v1';
const DEFAULTS = {
  done: {},          // "урок:упражнение" -> дата выполнения
  read: {},          // уроки без упражнений, отмеченные прочитанными
  seconds: {},       // "YYYY-MM-DD" -> секунд практики
  bests: {},         // рекорды: смены за минуту, точность боя
  settings: { goal: 20, latency: null, sens: 1, a4: 440 },
};

function load() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) || '{}');
    return { ...structuredClone(DEFAULTS), ...raw, settings: { ...DEFAULTS.settings, ...(raw.settings || {}) } };
  } catch {
    return structuredClone(DEFAULTS);
  }
}

export const S = load();
export function save() {
  try { localStorage.setItem(KEY, JSON.stringify(S)); } catch { /* приватный режим */ }
}

export const dayKey = (d = new Date()) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

export function addSeconds(n) {
  const k = dayKey();
  S.seconds[k] = (S.seconds[k] || 0) + n;
}

export const todayMinutes = () => Math.floor((S.seconds[dayKey()] || 0) / 60);

// Дни подряд с занятием от 5 минут; сегодняшний день не обрывает серию, пока он не закончился.
export function streak() {
  let n = 0;
  const d = new Date();
  if ((S.seconds[dayKey(d)] || 0) < 300) d.setDate(d.getDate() - 1);
  while ((S.seconds[dayKey(d)] || 0) >= 300) { n++; d.setDate(d.getDate() - 1); }
  return n;
}

export function markDone(lessonId, exId) {
  const k = `${lessonId}:${exId}`;
  if (!S.done[k]) { S.done[k] = dayKey(); save(); return true; }
  return false;
}
export const isDone = (lessonId, exId) => !!S.done[`${lessonId}:${exId}`];

export function lessonProgress(lesson) {
  if (!lesson.exercises.length) return S.read[lesson.id] ? 1 : 0;
  return lesson.exercises.filter(e => isDone(lesson.id, e.id)).length / lesson.exercises.length;
}

export function setBest(key, value) {
  if (!(S.bests[key] >= value)) { S.bests[key] = value; save(); return true; }
  return false;
}

export function resetAll() {
  localStorage.removeItem(KEY);
  location.reload();
}
