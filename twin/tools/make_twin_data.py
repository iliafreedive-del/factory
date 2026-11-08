"""Данные двойника для Godot: twin/godot/data/twin.json.

Источники (всё уже сверено в старой игре):
- plan/plan.json — план в метрах (2ГИС + Excel + слова Ильи), точки съёмки фото;
- снимок сцены старой игры (meta.json из twin/tools/export_old_scene.js): карточки INFO, подписи, комнаты, зоны, люди.

Координаты двойника = метры плана, но восточнее проезда x −24,25 всё сдвинуто на 7,5 м
(проезд склад осей ↔ малярка 12 м по словам Ильи 29.10), ровно как в старой игре по умолчанию.

Запуск: python3 twin/tools/make_twin_data.py meta.json
"""
import json, sys, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
meta = json.load(open(sys.argv[1], encoding='utf-8'))
plan = json.load(open(os.path.join(ROOT, 'plan', 'plan.json'), encoding='utf-8'))

SPA, SPB, SPD = -27.95, -24.25, 7.5


def sx(m):
    if m <= SPA:
        return m
    if m >= SPB:
        return m + SPD
    return SPA + (m - SPA) * (SPB - SPA + SPD) / (SPB - SPA)


def r1(v):
    return round(v, 2)


vps = []
for v in plan['viewpoints']:
    dxs = sx(v['look'][0]) - v['look'][0]
    vps.append({
        'photo': v['photo'], 'title': v.get('title', ''), 'time': v.get('time', ''),
        'f35': v.get('f35', 0), 'vfov': v.get('vfov', 0), 'y': v.get('y', 1.6), 'pitch': v.get('pitch', 1.7),
        'pos': [r1(v['pos'][0] + dxs), r1(v['pos'][1])], 'look': [r1(v['look'][0] + dxs), r1(v['look'][1])]})

pb = plan['buildings']
blds = []
for b in meta['buildings']:
    p = pb.get(b['id'], {})
    blds.append({'id': b['id'], 'name': b['name'], 'locked': b['locked'], 'r': [r1(x) for x in b['r']],
                 'h': p.get('h'), 'owner': p.get('owner'), 'src': p.get('src'),
                 'rooms': [{'id': q['id'], 'name': q['name'], 'step': q['step'], 'fl': q['fl'],
                            'r': [r1(x) for x in q['r']]} for q in b['rooms']]})

# маршруты рамы из старой игры (метры плана) → координаты двойника
FLOWS = {
    'main': {'name': 'Рама: резка → сварка → песко → малярка → сборка → отгрузка', 'color': '#c9773a',
             'pts': [[-33, 19], [-55, 30], [-55, 44], [-33, 46], [-26.4, 46], [-26.4, 20], [-15, 14], [-6, 5], [-18, 30],
                     [-10, 45], [0, 58], [12, 44], [35, 58], [10, 74]]},
    'zinc': {'name': 'Ветка цинка: чёрные рамы → кран → цинк', 'color': '#f2c230',
             'pts': [[-55, 44], [-26.4, 46], [-26.4, 20], [-15, 14], [-15, -27], [110, -27], [134.4, -6.1], [128, 17.9],
                     [57.6, 25.1], [20, 30], [12, 44], [64, 45], [69, 45]]},
    'black': {'name': 'Из Чёрного цеха вдоль забора через КПП', 'color': '#f2c230',
              'pts': [[190, 100], [186, 192], [172, 194], [165, 150], [158, 100], [150, 82], [140, 72], [128, 65.9],
                      [125.6, 33.9], [134.4, -6.1], [110, -27]]},
}
for f in FLOWS.values():
    f['pts'] = [[r1(sx(x)), r1(z)] for x, z in f['pts']]

# Узлы потока рам (метры плана). Места — центры участков из плана и зон Excel; маршруты между ними —
# по линии «Путь рамы» старой игры. Всё это схема: в планировщике точки маршрута двигаются мышью.
STATIONS = [
    {'id': 'cut', 'name': 'Приёмка и резка', 'num': '1', 'kind': 'proc', 'pos': [-50, 31.5], 'next': 'weld'},
    {'id': 'weld', 'name': 'Сварка рамы', 'num': '2', 'kind': 'proc', 'pos': [-50, 46], 'next': 'waitSand'},
    {'id': 'waitSand', 'name': 'Рамы ждут пескоструй', 'num': '·', 'kind': 'buf', 'pos': [-6.5, 6]},
    {'id': 'sand', 'name': 'Пескоструй', 'num': '3', 'kind': 'proc', 'pos': [-16, 28.5], 'feed': 'waitSand', 'next': 'paint'},
    {'id': 'paint', 'name': 'Малярка', 'num': '4', 'kind': 'proc', 'pos': [-8, 41], 'next': 'distrib'},
    {'id': 'distrib', 'name': 'Ждут распределения', 'num': '·', 'kind': 'buf', 'pos': [2.5, 58]},
    {'id': 'asm1', 'name': 'Сборка 1', 'num': '5', 'kind': 'proc', 'pos': [-50, 60], 'feed': 'distrib', 'next': 'ship1'},
    {'id': 'asm2', 'name': 'Сборка 2', 'num': '5', 'kind': 'proc', 'pos': [11.5, 41], 'feed': 'distrib', 'next': 'ship1'},
    {'id': 'ship1', 'name': 'Отправка дилерам', 'num': '→', 'kind': 'sink', 'pos': [10.5, 74]},
]
ROUTES = {
    'weld>waitSand': [[-33, 46], [-26.4, 46], [-26.4, 20], [-15, 14]],
    'waitSand>sand': [[-15, 14], [-26.4, 20], [-26.4, 29], [-23, 29]],
    'paint>distrib': [[-19, 47], [-19, 52]],
    'distrib>asm1': [[-26.4, 58], [-36, 63.5]],
    'asm1>ship1': [[-36, 63.5], [-26.4, 74]],
    'asm2>ship1': [[12, 52]],
}
for st in STATIONS:
    st['pos'] = [r1(sx(st['pos'][0])), r1(st['pos'][1])]
ROUTES = {k: [[r1(sx(x)), r1(z)] for x, z in v] for k, v in ROUTES.items()}

# Камеры наблюдения, которые уже висят (фото Ильи 08.11, IMG_2320–2326). Места ПРИМЕРНЫЕ.
CAMS = [
    {'id': 'cam1', 'name': 'IP-кубик RVi в офисе', 'kind': 'ip', 'pos': [-50.5, 71.5], 'y': 2.6, 'yaw': 90, 'photo': 'IMG_2320',
     'note': 'Офис 1. IP-камера: поток RTSP можно брать напрямую'},
    {'id': 'cam2', 'name': 'Уличные bullet (iCam и малая с ИК)', 'kind': 'analog', 'pos': [-38.0, 64.5], 'y': 3.4, 'yaw': -60,
     'photo': 'IMG_2321–2324', 'note': 'На профлисте у кирпичного крыльца с козырьком (место примерное). Аналоговые, через регистратор'},
    {'id': 'cam3', 'name': 'Купольная на бетонной стене', 'kind': 'analog', 'pos': [-60.8, 58.0], 'y': 3.2, 'yaw': 90,
     'photo': 'IMG_2325', 'note': 'Сборка 1 (место примерное). Видит зону сборки: люди, прицепы на постах'},
    {'id': 'cam4', 'name': 'Две купольные и прожектор на колонне', 'kind': 'analog', 'pos': [-50.0, 62.5], 'y': 4.0, 'yaw': 0,
     'photo': 'IMG_2326', 'note': 'Колонна внутри Сборки 1 (место примерное). Две камеры смотрят в разные стороны'},
]
for c in CAMS:
    c['pos'] = [r1(sx(c['pos'][0])), r1(c['pos'][1])]

out = {
    'about': 'Завод прицепов «Аляска», Красноярск, ул. Айвазовского 6. Метры плана; восточнее x −24,25 плюс 7,5 м (проезд 12 м).',
    'frame': plan['frame'], 'shift': {'a': SPA, 'b': SPB, 'd': SPD},
    'buildings': blds,
    'info': meta['INFO'],
    # номер шага в старой игре был кружком перед подписью; в двойнике номер стоит на столбе участка
    'labels': [{'id': l['id'], 't': re.sub(r'^\d(?=[А-ЯЁA-Z])', '', l['t']), 'kind': l['kind'], 'x': r1(l['x']), 'y': r1(l['y']), 'z': r1(l['z']), 'b': l['b']}
               for l in meta['labels'] if l['x'] is not None],
    'zones': [{**z, 'x': r1(z['x']), 'z': r1(z['z']), 'w': r1(z['w']), 'd': r1(z['d'])} for z in meta['zones']],
    'steps': meta['STEPS'], 'zsteps': meta['ZSTEPS'],
    'flows': FLOWS,
    'workers': [{'x': r1(w['x']), 'z': r1(w['z']), 'ry': r1(w['ry']), **(w['w'] or {})} for w in meta['workers']],
    'viewpoints': vps,
    'stations': STATIONS, 'routes': ROUTES, 'cams': CAMS,
}
dst = os.path.join(ROOT, 'twin', 'godot', 'data', 'twin.json')
json.dump(out, open(dst, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print('ok', dst, os.path.getsize(dst), 'viewpoints', len(vps), 'info', len(out['info']), 'labels', len(out['labels']))
