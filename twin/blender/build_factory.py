"""Blender: собирает двойник завода из сверенной сцены старой игры.

Вход: old_scene.glb — снимок сцены index.html (twin/tools/export_old_scene.js), в метрах плана:
x — вдоль склада комплектующих (азимут 75°), z — на юг (165°), начало — СЗ угол склада.
Восточнее проезда x −24,25 всё сдвинуто на 7,5 м: проезд склад осей ↔ малярка 12 м по словам Ильи 29.10.

Что делает:
1. Цвет материала запекает в цвет вершин (всё дальше красится по цвету вершин, как в сверенной игре).
2. Каждой грани назначает класс материала по цвету, размеру и месту: профлист, кирпич, бетонные панели,
   плиты, асфальт, грунт, трава, оцинковка, ржавчина, дерево, окрашенный металл, стекло.
3. Склеивает по зданиям и частям (стены, крыша, потолок, внутри, 2 этаж), двор — плитками 60×60 м.
4. Запекает затенение углов (AO, Cycles) в цвет вершин.
5. Сохраняет отдельный проект factory.blend и factory.glb для Godot (повторная выгрузка — export_glb.py).

Машины и прицепы ставит vehicles.py по meta.json (рядом с old_scene.glb) и правкам по фото twin/tools/vehicles.json.

Запуск: blender -b -P twin/blender/build_factory.py -- old_scene.glb factory.glb factory.blend
"""
import bpy, sys, os, json, math
from mathutils import Vector
import numpy as np

argv = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT_GLB, OUT_BLEND = argv[0], argv[1], argv[2]
META = os.path.join(os.path.dirname(os.path.abspath(SRC)), 'meta.json')
HERE = os.path.dirname(os.path.abspath(__file__))
RULES = os.path.join(HERE, '..', 'tools', 'vehicles.json')
sys.path.insert(0, HERE)
import vehicles
OUT_STATS = OUT_GLB.replace('.glb', '_classes.json')

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scene = bpy.context.scene

# здания, где большие стены — бетонные панели (6 ст1, Чёрный цех и соседи)
PANEL_B = {'b2b', 'b2n', 'b2a', 'b7', 'k6', 'q1', 'q2'}
# кирпич только здесь: красный склад b3 и красный ангар b6 — профлист (фото 1561, 1604)
BRICK_B = {'b1o', 'b2k', 'b1', 'b2b', 'b2n', 'b2a'}
# здания, где крыша идёт вдоль z (длинная сторона по z): волна профлиста поворачивается
ROOF_Z = {'b1', 'b1o', 'b1a', 'b2t', 'b2tn', 'b2k'}
TILE = 60.0

CLASSES = ['corr', 'corr_z', 'brick', 'panel', 'slab', 'asphalt', 'dirt', 'grass', 'line', 'terrain',
           'floor', 'galv', 'rust', 'wood', 'metal', 'cloth', 'glass', 'keep', 'zone', 'zoneline',
           'paint', 'vglass', 'tyre']


def make_class_mat(name):
    m = bpy.data.materials.new('M_' + name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    ca = nt.nodes.new('ShaderNodeVertexColor')
    ca.layer_name = 'Color'
    nt.links.new(ca.outputs['Color'], bsdf.inputs['Base Color'])
    rough = {'galv': 0.35, 'metal': 0.55, 'glass': 0.05, 'line': 0.6, 'paint': 0.3, 'vglass': 0.05, 'tyre': 0.95}.get(name, 0.85)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = {'galv': 0.7, 'metal': 0.3, 'corr': 0.3, 'corr_z': 0.3}.get(name, 0.0)
    return m


CMAT = {c: make_class_mat(c) for c in CLASSES if c not in ('keep',)}

objs = [o for o in scene.objects if o.type == 'MESH']
print('imported', len(objs))

# 1. применить трансформации (каждый объект — свой меш)
for o in objs:
    if o.data.users > 1:
        o.data = o.data.copy()
bpy.ops.object.select_all(action='DESELECT')
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def mat_info(mat):
    """базовый цвет (как в игре, «сырые» sRGB-числа), прозрачность, есть ли текстура"""
    if mat is None or not mat.use_nodes:
        return (1, 1, 1), 1.0, False
    bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    tex = any(n.type == 'TEX_IMAGE' for n in mat.node_tree.nodes)
    if bsdf is None:
        return (1, 1, 1), 1.0, tex
    bc = tuple(bsdf.inputs['Base Color'].default_value)[:3]
    a = bsdf.inputs['Alpha'].default_value
    if mat.blend_method == 'BLEND' or getattr(mat, 'surface_render_method', '') == 'BLENDED':
        a = min(a, 0.99)
    return bc, a, tex


stats = {}


def classify(o):
    me = o.data
    name = o.name.split('.')[0]
    parts = name.split('|')
    bid, part = (parts + ['world', 'world'])[:2]
    nP = len(me.polygons)
    if nP == 0:
        return bid, part
    # цвет вершин -> по углам
    ca = me.color_attributes[0] if len(me.color_attributes) else None
    if ca is None:
        ca = me.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
        cols = np.ones((len(me.loops), 4), np.float32)
    else:
        if ca.domain == 'POINT':
            pc = np.zeros(len(ca.data) * 4, np.float32)
            ca.data.foreach_get('color', pc)
            pc = pc.reshape(-1, 4)
            lv = np.zeros(len(me.loops), np.int32)
            me.loops.foreach_get('vertex_index', lv)
            cols = pc[lv]
        else:
            cols = np.zeros(len(me.loops) * 4, np.float32)
            ca.data.foreach_get('color', cols)
            cols = cols.reshape(-1, 4)
    # множитель — базовый цвет материала слота
    mi = np.zeros(nP, np.int32)
    me.polygons.foreach_get('material_index', mi)
    ls = np.zeros(nP, np.int32)
    me.polygons.foreach_get('loop_start', ls)
    lt = np.zeros(nP, np.int32)
    me.polygons.foreach_get('loop_total', lt)
    loop_poly = np.repeat(np.arange(nP), lt)
    infos = [mat_info(s.material) for s in o.material_slots] or [((1, 1, 1), 1.0, False)]
    base = np.array([i[0] for i in infos], np.float32)
    alpha = np.array([i[1] for i in infos], np.float32)
    hastex = np.array([i[2] for i in infos], bool)
    lm = mi[loop_poly] if len(infos) > 1 else np.zeros(len(loop_poly), np.int32)
    cols[:, :3] *= base[lm]
    cols[:, 3] = alpha[lm]

    # цвет грани
    fc = np.zeros((nP, 3), np.float32)
    np.add.at(fc, loop_poly, cols[:, :3])
    fc /= lt[:, None]
    r, g, b = fc[:, 0], fc[:, 1], fc[:, 2]
    mx, mn = fc.max(1), fc.min(1)
    v = mx
    s = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
    h = np.zeros(nP)
    d = np.maximum(mx - mn, 1e-5)
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    h = np.where(mx - mn < 1e-4, 0, h)
    hexes = (np.clip(np.round(fc * 255), 0, 255).astype(int) @ np.array([65536, 256, 1]))

    # геометрия грани (Blender: z вверх)
    nrm = np.zeros(nP * 3, np.float32)
    me.polygons.foreach_get('normal', nrm)
    nrm = nrm.reshape(-1, 3)
    area = np.zeros(nP, np.float32)
    me.polygons.foreach_get('area', area)
    cen = np.zeros(nP * 3, np.float32)
    me.polygons.foreach_get('center', cen)
    cen = cen.reshape(-1, 3)
    co = np.zeros(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    lv = np.zeros(len(me.loops), np.int32)
    me.loops.foreach_get('vertex_index', lv)
    lz = co[lv, 2]
    zmin = np.full(nP, 1e9)
    zmax = np.full(nP, -1e9)
    np.minimum.at(zmin, loop_poly, lz)
    np.maximum.at(zmax, loop_poly, lz)
    zext = zmax - zmin
    nz = np.abs(nrm[:, 2])

    cls = np.full(nP, 'metal', dtype=object)
    face_alpha = alpha[mi] if len(infos) > 1 else np.full(nP, alpha[0])
    face_tex = hastex[mi] if len(infos) > 1 else np.full(nP, hastex[0])

    brickish = (((h <= 25) | (h >= 345)) & (s > 0.3) & (s < 0.8) & (v > 0.22) & (v < 0.75))
    zincish = (s < 0.09) & (v > 0.66) & (v < 0.86)
    rustish = (h >= 8) & (h <= 35) & (s > 0.35) & (s < 0.8) & (v > 0.22) & (v < 0.62)
    woodish = (h > 22) & (h <= 45) & (s > 0.28) & (s < 0.66) & (v > 0.45) & (v < 0.88)
    green = (h > 60) & (h < 170) & (s > 0.15)

    if part in ('worker',):
        cls[:] = 'cloth'
    else:
        cls[zincish] = 'galv'
        cls[rustish] = 'rust'
        cls[woodish] = 'wood'
        big_v = (nz < 0.35) & (area > 2.5) & (zext > 1.0)
        wall = big_v & ~brickish
        if bid in PANEL_B:
            cls[wall & (s < 0.25)] = 'panel'
            cls[wall & (s >= 0.25)] = 'corr'
        else:
            cls[wall] = 'corr'
        # кирпич только там, где он есть на фото: офис 1, кирпичный блок песко, низ цеха 1, вставки и белый кирпич 6 ст1.
        # Склад комплектующих и красный ангар — красный профлист (фото 1561, 1604), не кирпич.
        if bid in BRICK_B:
            cls[big_v & brickish] = 'brick'
            cls[big_v & (hexes == 0xd4d2cb)] = 'brick'
        else:
            cls[big_v & brickish] = 'corr'
        if part in ('roof', 'roofIn'):
            cls[:] = 'corr_z' if bid in ROOF_Z else 'corr'
        # пол внутри зданий
        floor = (nz > 0.9) & (cen[:, 2] < 0.25) & (area > 1.0) & (part in ('int', 'walls'))
        cls[floor] = 'floor'
        # земля двора: плоские пятна у самой земли
        if bid == 'world':
            gnd = (cen[:, 2] < 0.12) & (zmax < 0.2)
            cls[gnd & green] = 'grass'
            cls[gnd & ~green & (s < 0.14) & (v < 0.62)] = 'asphalt'
            cls[gnd & ~green & (s < 0.22) & (v >= 0.62)] = 'slab'
            cls[gnd & ~green & (s >= 0.14) & (h > 15) & (h < 65) & (v < 0.9)] = 'dirt'
            # белая и жёлтая разметка на земле — условность старой игры, на фото её нет: в слой «Зоны»
            cls[gnd & ((v > 0.9) & (s < 0.12) | ((h > 38) & (h < 60) & (s > 0.6)))] = 'zoneline'
    # земля вокруг завода: огромная плоскость старой игры (1600×1600 м) → поле с грунтом
    terrain = (area > 20000) & (nz > 0.5)
    cls[terrain] = 'terrain'
    if bid == 'yard':
        cls[:] = 'slab'
    # белые рамки зон на земле — это разметка игры, в двойнике она слой «Зоны»
    zl = (hexes == 0xf6efd6) & (zmax < 0.25)
    cls[zl] = 'zoneline'
    if bid == 'zone':
        cls[:] = 'zone'
    cls[face_alpha < 0.99] = 'glass'
    cls[face_tex] = 'keep'

    # цвета под реализм: пастель «Магната» → натуральные тона, остальное как в сверенной игре
    tgt = np.zeros((nP, 3), np.float32)
    kk = np.zeros(nP, np.float32)
    def mixto(sel, rgb, k):
        tgt[sel] = rgb
        kk[sel] = k
    # фото 26.10: пасмурно, мокрые серые плиты и асфальт, сухая бурая трава, пятна снега
    mixto(cls == 'terrain', (0.40, 0.37, 0.29), 1.0)
    mixto(cls == 'grass', (0.40, 0.40, 0.28), 0.75)
    mixto((cls == 'slab') & (bid == 'yard'), (0.40, 0.39, 0.37), 1.0)
    mixto((cls == 'slab') & (bid != 'yard'), (0.43, 0.42, 0.40), 0.85)
    mixto(cls == 'dirt', (0.40, 0.37, 0.31), 0.7)
    mixto(cls == 'asphalt', (0.31, 0.31, 0.31), 0.7)
    mixto(cls == 'panel', (0.64, 0.62, 0.57), 0.45)
    lk = kk[loop_poly][:, None]
    cols[:, :3] = cols[:, :3] * (1 - lk) + tgt[loop_poly] * lk
    # записать в атрибут «Color» по углам
    if ca.domain != 'CORNER' or ca.data_type != 'FLOAT_COLOR' or ca.name != 'Color':
        for a in list(me.color_attributes):
            me.color_attributes.remove(a)
        ca = me.color_attributes.new('Color', 'FLOAT_COLOR', 'CORNER')
    ca.data.foreach_set('color', cols.ravel())
    me.color_attributes.active_color = ca

    # слоты: классы + исходные материалы для keep/glass
    old_slots = [s.material for s in o.material_slots]
    me.materials.clear()
    slot_of = {}
    new_mi = np.zeros(nP, np.int32)
    for c in np.unique(cls):
        sel = cls == c
        if c in ('keep', 'glass'):
            # сохранить исходный материал (текстура пола, прозрачность)
            for k in np.unique(mi[sel]):
                m = old_slots[k] if k < len(old_slots) else None
                if m is None:
                    continue
                if c == 'glass' and not m.name.startswith('K_glass'):
                    m.name = 'K_glass_' + m.name
                if c == 'keep' and not m.name.startswith('K_'):
                    m.name = 'K_tex_' + m.name
                key = m.name
                if key not in slot_of:
                    me.materials.append(m)
                    slot_of[key] = len(me.materials) - 1
                new_mi[sel & (mi == k)] = slot_of[key]
        else:
            key = 'M_' + c
            if key not in slot_of:
                me.materials.append(CMAT[c])
                slot_of[key] = len(me.materials) - 1
            new_mi[sel] = slot_of[key]
        stats[c] = stats.get(c, 0) + int(sel.sum())
    me.polygons.foreach_set('material_index', new_mi)
    me.update()
    return bid, part


groups = {}
for o in objs:
    bid, part = classify(o)
    if bid == 'world' and part == 'world':
        # двор плитками для отсечения камерой
        bb = np.array([o.matrix_world @ Vector(c) for c in o.bound_box])
        cx, cy = bb[:, 0].mean(), bb[:, 1].mean()
        w = max(np.ptp(bb[:, 0]), np.ptp(bb[:, 1]))
        if w > TILE * 1.5:
            key = 'world|big'
        else:
            key = 'world|t%d_%d' % (math.floor(cx / TILE), math.floor(-cy / TILE))
    elif part == 'worker':
        key = 'people|all'
    elif bid == 'zone':
        key = 'zone|%s' % part
    elif bid == 'yard':
        key = 'world|yard'
    else:
        key = '%s|%s' % (bid, part)
    groups.setdefault(key, []).append(o)

# машины и прицепы по фото (vehicles.py): один объект, затенение углов — вместе со всем заводом
veh, vrep = vehicles.build(META, RULES, CMAT)
print('vehicles', vrep)
groups['world|veh'] = [veh]
print('classes', stats)
for key, lst in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in lst:
        o.select_set(True)
    bpy.context.view_layer.objects.active = lst[0]
    if len(lst) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = key
    ob.data.name = key
    # пустые слоты убрать
    used = set()
    for p in ob.data.polygons:
        used.add(p.material_index)
print('objects after join', len([o for o in scene.objects if o.type == 'MESH']))

# ---------- запечённое затенение (AO) в цвет вершин ----------
# В Godot (веб, Compatibility) рассеянный свет неба не затеняется: внутри цехов было бы светло, как на улице.
# Запекаем в Cycles: крупные грани режем сеткой 3 м, чтобы тень у стен и под прицепами легла на пол и плиты.
import bmesh
AO_STEP = 3.0
NO_AO = {'zone', 'people'}
meshes = [o for o in scene.objects if o.type == 'MESH' and o.name.split('|')[0] not in NO_AO]
for o in meshes:
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    terr_idx = {i for i, m in enumerate(me.materials) if m and m.name in ('M_terrain',)}
    big = [f for f in bm.faces if f.calc_area() > AO_STEP * AO_STEP * 0.8 and f.material_index not in terr_idx]
    if big:
        co = np.array([v.co[:] for f in big for v in f.verts])
        lo, hi = co.min(0), co.max(0)
        for ax in range(3):
            if hi[ax] - lo[ax] < AO_STEP:
                continue
            k0 = math.ceil(lo[ax] / AO_STEP)
            k1 = math.floor(hi[ax] / AO_STEP)
            for k in range(k0, k1 + 1):
                faces = [f for f in bm.faces if f.is_valid and f.calc_area() > 0.5 and f.material_index not in terr_idx]
                geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
                no = [0, 0, 0]
                no[ax] = 1
                pc = [0, 0, 0]
                pc[ax] = k * AO_STEP
                bmesh.ops.bisect_plane(bm, geom=geom, plane_co=pc, plane_no=no, dist=0.01)
    bm.to_mesh(me)
    bm.free()
    me.update()
print('subdivided, polys', sum(len(o.data.polygons) for o in meshes))

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = int(os.environ.get('AO_SAMPLES', '24'))
if scene.world is None:
    scene.world = bpy.data.worlds.new('Мир')
scene.world.light_settings.distance = 7.0
for o in meshes:
    me = o.data
    if 'AO' in me.color_attributes:
        me.color_attributes.remove(me.color_attributes['AO'])
    a = me.color_attributes.new('AO', 'FLOAT_COLOR', 'CORNER')
    me.color_attributes.active_color = a
# плашки зон лежат на 3 см над землёй: при запекании они закрывали бы двор сверху и земля под ними выходила
# почти чёрной (сверка 08.11: южный двор у фасада 6 ст1 был темнее фото втрое). Люди тоже не затеняют.
skip = [o for o in scene.objects if o.type == 'MESH' and o.name.split('|')[0] in NO_AO]
for o in skip:
    o.hide_render = True
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
import time
t0 = time.time()
bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
print('AO baked in %.0fs' % (time.time() - t0))
for o in skip:
    o.hide_render = False
for o in meshes:
    me = o.data
    c = np.zeros(len(me.loops) * 4, np.float32)
    me.color_attributes['Color'].data.foreach_get('color', c)
    a = np.zeros(len(me.loops) * 4, np.float32)
    me.color_attributes['AO'].data.foreach_get('color', a)
    c = c.reshape(-1, 4)
    ao = a.reshape(-1, 4)[:, :1]
    c[:, :3] *= 0.32 + 0.68 * ao
    me.color_attributes['Color'].data.foreach_set('color', c.ravel())
    me.color_attributes.remove(me.color_attributes['AO'])
    me.color_attributes.active_color = me.color_attributes['Color']
    me.color_attributes.render_color_index = list(me.color_attributes).index(me.color_attributes['Color'])

# коллекции по смыслу — чтобы в Blender было удобно смотреть
cols = {}
for o in list(scene.objects):
    if o.type != 'MESH':
        continue
    b = o.name.split('|')[0]
    cname = {'world': 'Двор', 'people': 'Люди', 'zone': 'Зоны (слой)'}.get(b, 'Здание ' + b)
    if cname not in cols:
        cols[cname] = bpy.data.collections.new(cname)
        scene.collection.children.link(cols[cname])
    for c in o.users_collection:
        c.objects.unlink(o)
    cols[cname].objects.link(o)

# пустые объекты (узлы без меша) убрать
for o in list(scene.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o)

# солнце и камера для превью в Blender (на экспорт не влияют)
sun = bpy.data.lights.new('Солнце', 'SUN')
sun.energy = 3.0
so = bpy.data.objects.new('Солнце', sun)
so.rotation_euler = (math.radians(50), 0, math.radians(200))
scene.collection.objects.link(so)

os.makedirs(os.path.dirname(os.path.abspath(OUT_GLB)), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, compress=True)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', use_selection=False,
                          export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                          export_lights=False, export_cameras=False, export_extras=False,
                          export_yup=True, export_image_format='AUTO')
json.dump({'classes': stats, 'vehicles': vrep, 'objects': sorted(o.name for o in scene.objects if o.type == 'MESH')},
          open(OUT_STATS, 'w'), ensure_ascii=False, indent=1)
print('done', OUT_GLB, os.path.getsize(OUT_GLB))
