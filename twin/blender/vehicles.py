"""Машины и прицепы двойника: ставятся по фото, строятся подробнее, чем в старой игре.

Откуда места: export_old_scene.js записывает каждый готовый прицеп, платформу, лодочный прицеп и легковую старой игры
(место, поворот, вид) в meta.json → vehicles. Правки по фото — twin/tools/vehicles.json: убрать ряд, оставить часть,
поставить ряд поперёк проезда. Всё строится одним объектом «world|veh» с классами материалов, затенение углов
запекается вместе с заводом (build_factory.py).

Оси модели как в старой игре: x — вдоль прицепа (дышло на −x), y — вверх, z — вбок; у легковой нос на +x.
Перевод в Blender (z вверх): (x, y, z) → (x, −z, y).
"""
import json, math
import bmesh
from mathutils import Matrix, Vector

ZINC = 0xb9c2c9
TIRE = 0x1e1f21
BLACK = 0x222326


def rgb(h):
    return ((h >> 16 & 255) / 255.0, (h >> 8 & 255) / 255.0, (h & 255) / 255.0)


def cls_of(h):
    """класс материала по цвету: серебристое — оцинковка, остальное — окрашенный металл"""
    r, g, b = rgb(h)
    mx, mn = max(r, g, b), min(r, g, b)
    s = (mx - mn) / mx if mx > 0 else 0
    return 'galv' if (s < 0.12 and mx > 0.55) else 'metal'


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def S(x, y, z):
    m = Matrix.Identity(4)
    m[0][0], m[1][1], m[2][2] = x, y, z
    return m


def RX(a):
    return Matrix.Rotation(a, 4, 'X')


def RY(a):
    return Matrix.Rotation(a, 4, 'Y')


def RZ(a):
    return Matrix.Rotation(a, 4, 'Z')


class VB:
    """сборщик: всё в осях старой игры, в конце переводится в Blender"""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new('Color')
        self.cls = []
        self.M = Matrix.Identity(4)

    def _paint(self, verts, h, c, smooth=False):
        if c not in self.cls:
            self.cls.append(c)
        mi = self.cls.index(c)
        col = (*rgb(h), 1.0)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = mi
            f.smooth = smooth
            for lp in f.loops:
                lp[self.col] = col

    def box(self, sx, sy, sz, h, x, y, z, c=None, ry=0.0, rz=0.0, rx=0.0):
        """коробка sx×sy×sz, y — низ (как b.box старой игры), поворот ry, затем rz, rx вокруг центра"""
        m = self.M @ T(x, y + sy / 2, z) @ RY(ry) @ RZ(rz) @ RX(rx) @ S(sx, sy, sz)
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._paint(r['verts'], h, c or cls_of(h))

    def beam(self, p, q, w, t, h, c=None):
        """брус от p до q (x, y, z) сечением w×t"""
        p, q = Vector(p), Vector(q)
        d = q - p
        L = d.length
        ry = math.atan2(-d.z, d.x)
        rz = math.atan2(d.y, math.hypot(d.x, d.z))
        mid = (p + q) / 2
        m = self.M @ T(*mid) @ RY(ry) @ RZ(rz) @ S(L, t, w)
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._paint(r['verts'], h, c or cls_of(h))

    def cyl(self, r, w, h, x, y, z, c=None, seg=16, axis='z', r2=None, smooth=True):
        """цилиндр радиуса r длиной w, ось по z (колёса), 'y' — стоймя, 'x' — вдоль"""
        rot = {'z': Matrix.Identity(4), 'y': RX(math.pi / 2), 'x': RY(math.pi / 2)}[axis]
        m = self.M @ T(x, y, z) @ rot
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                                    radius2=r if r2 is None else r2, depth=w, matrix=m)
        self._paint(res['verts'], h, c or cls_of(h), smooth)

    def ball(self, rx, ry, rz, h, x, y, z, c=None, seg=12):
        m = self.M @ T(x, y, z) @ S(rx, ry, rz)
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=max(4, seg // 2), radius=1.0, matrix=m)
        self._paint(res['verts'], h, c or cls_of(h), True)

    def hull(self, pts, h, c, glass_sides=None):
        """выпуклая оболочка точек; glass_sides=(цвет, класс) — боковые грани (не верх и не низ) этим цветом"""
        vs = [self.bm.verts.new(self.M @ Vector(p)) for p in pts]
        res = bmesh.ops.convex_hull(self.bm, input=vs)
        bad = list({v for v in res.get('geom_interior', []) + res.get('geom_unused', []) if isinstance(v, bmesh.types.BMVert)})
        if bad:
            bmesh.ops.delete(self.bm, geom=bad, context='VERTS')
        verts = [v for v in vs if v.is_valid]
        self._paint(verts, h, c)
        if glass_sides:
            up = (self.M.to_3x3() @ Vector((0, 1, 0))).normalized()
            gh, gc = glass_sides
            if gc not in self.cls:
                self.cls.append(gc)
            gi = self.cls.index(gc)
            col = (*rgb(gh), 1.0)
            for f in {f for v in verts for f in v.link_faces}:
                f.normal_update()
                if abs(f.normal.dot(up)) < 0.75:
                    f.material_index = gi
                    for lp in f.loops:
                        lp[self.col] = col

    # ---------- общие детали ----------
    def wheel(self, x, y, z, r, w, rim=0xc9ced2, hub=0x8e959b):
        s = 1 if z > 0 else -1
        self.cyl(r, w, TIRE, x, y, z, 'tyre', seg=18)
        self.cyl(r * 0.62, w + 0.012, rim, x, y, z, 'galv' if rim != BLACK else 'metal', seg=14, smooth=False)
        self.cyl(r * 0.2, w + 0.04, hub, x, y, z, 'galv', seg=8, smooth=False)
        # протектор: тёмные ламели по окружности не нужны, шина гладкая

    def lights(self, x, y, W, side_z=None):
        """задние фонари, катафоты и номер прицепа (x — задний край)"""
        for s in (-1, 1):
            zz = s * (W / 2 - 0.2) if side_z is None else s * side_z
            self.box(0.06, 0.09, 0.22, 0x2a2b2d, x + 0.02, y, zz, 'metal')
            self.box(0.02, 0.07, 0.08, 0xd63a2c, x + 0.055, y + 0.01, zz - 0.06, 'paint')
            self.box(0.02, 0.07, 0.05, 0xe7a23a, x + 0.055, y + 0.01, zz + 0.03, 'paint')
            self.box(0.02, 0.07, 0.04, 0xf2f2ee, x + 0.055, y + 0.01, zz + 0.08, 'paint')
            self.box(0.015, 0.06, 0.06, 0xc8281e, x + 0.05, y + 0.12, zz, 'paint')   # катафот
        self.box(0.02, 0.11, 0.5, 0xf4f4f2, x + 0.04, y - 0.02, 0, 'paint')           # номер
        self.box(0.01, 0.06, 0.4, 0x2a2b2d, x + 0.052, y + 0.005, 0, 'metal')

    def drawbar(self, L, fr, y=0.42, spread=0.45, reach=1.2, jockey=True):
        """V-дышло к сцепной голове на −x, опорное колесо"""
        tip = -L / 2 - reach
        c = cls_of(fr)
        for s in (-1, 1):
            self.beam((-L / 2 + 0.05, y, s * spread), (tip + 0.18, y, s * 0.06), 0.07, 0.1, fr, c)
        self.box(0.36, 0.1, 0.12, fr, tip + 0.15, y - 0.05, 0, c)
        self.box(0.24, 0.12, 0.14, 0x9aa3ab, tip - 0.02, y - 0.02, 0, 'galv')          # сцепная голова
        self.ball(0.08, 0.06, 0.07, 0x9aa3ab, tip - 0.12, y + 0.06, 0, 'galv', seg=8)
        self.box(0.18, 0.03, 0.03, 0x2a2b2d, tip + 0.08, y + 0.1, 0, 'metal')           # рукоять
        if jockey:
            jx, jz = tip + 0.55, 0.13
            self.cyl(0.03, 0.75, 0x9aa3ab, jx, 0.45, jz, 'galv', seg=8, axis='y', smooth=False)
            self.cyl(0.1, 0.06, TIRE, jx, 0.1, jz, 'tyre', seg=12)
            self.box(0.03, 0.03, 0.14, 0x2a2b2d, jx, 0.83, jz, 'metal')


# ---------- прицепы ----------
def trailer(vb, o):
    L = o.get('L', 3.6)
    W = o.get('W', 1.8)
    fr = o.get('fr', ZINC)
    body = o.get('color', 0x9aa3ab)
    t2 = o.get('axles') == 2
    sh = o.get('sides', 0.35)
    fc = cls_of(fr)
    # рама: лонжероны, поперечины
    for s in (-1, 1):
        vb.box(L, 0.12, 0.06, fr, 0, 0.36, s * (W / 2 - 0.15), fc)
    for px in (-L / 2 + 0.05, -L / 6, L / 6, L / 2 - 0.05):
        vb.box(0.06, 0.1, W - 0.3, fr, px, 0.37, 0, fc)
    vb.drawbar(L, fr)
    # оси и колёса, крылья
    wr = 0.29 if t2 else 0.31
    axes = (-0.4, 0.4) if t2 else (0.0,)
    for px in axes:
        vb.box(0.08, 0.08, W + 0.22, 0x55595e, px, wr - 0.04, 0, 'metal')
        for s in (-1, 1):
            vb.wheel(px, wr, s * (W / 2 + 0.12), wr, 0.19)
    fx0, fx1 = (min(axes) - wr - 0.05, max(axes) + wr + 0.05)
    for s in (-1, 1):
        zf = s * (W / 2 + 0.12)
        top = 2 * wr + 0.05
        vb.box(fx1 - fx0 - 0.3, 0.025, 0.26, 0x9aa3ab, (fx0 + fx1) / 2, top, zf, 'galv')
        for q in (-1, 1):
            xe = (fx1 if q > 0 else fx0) - q * 0.12
            vb.box(0.3, 0.025, 0.26, 0x9aa3ab, xe, top - 0.12, zf, 'galv', rz=-q * 0.75)
    # пол
    if o.get('ply'):
        vb.box(L, 0.02, W - 0.04, o['ply'], 0, 0.48, 0, 'wood')
    else:
        vb.box(L, 0.04, W, 0x8b9197, 0, 0.46, 0, 'galv')
    vb.box(L + 0.02, 0.05, 0.05, fr, 0, 0.45, W / 2, fc)
    vb.box(L + 0.02, 0.05, 0.05, fr, 0, 0.45, -W / 2, fc)
    if o.get('boat'):
        return
    # борта: панели, верхняя кромка, стойки по углам и посередине
    bc = cls_of(body)
    y0 = 0.5
    for s in (-1, 1):
        vb.box(L, sh, 0.035, body, 0, y0, s * W / 2, bc)
        vb.box(L + 0.02, 0.035, 0.05, 0x9aa3ab, 0, y0 + sh - 0.01, s * W / 2, 'galv')
        vb.box(L - 0.1, 0.04, 0.045, 0x9aa3ab, 0, y0 + 0.06, s * W / 2, 'galv')       # нижняя ребро-полоса
        for px in (-L / 2 + 0.02, 0.0, L / 2 - 0.02):
            vb.box(0.05, sh + 0.02, 0.05, 0x8e959b, px, y0, s * (W / 2 + 0.005), 'galv')
    vb.box(0.035, sh, W, body, -L / 2, y0, 0, bc)
    vb.box(0.05, 0.035, W + 0.02, 0x9aa3ab, -L / 2, y0 + sh - 0.01, 0, 'galv')
    if o.get('tailDown'):
        a = -1.05
        vb.box(sh, 0.035, W, body, L / 2 + math.cos(a) * sh / 2, y0 + math.sin(a) * sh / 2 - 0.02, 0, bc, rz=a)
    else:
        vb.box(0.035, sh, W, body, L / 2, y0, 0, bc)
        vb.box(0.05, 0.035, W + 0.02, 0x9aa3ab, L / 2, y0 + sh - 0.01, 0, 'galv')
        for s in (-1, 1):
            vb.box(0.05, 0.05, 0.08, 0x2a2b2d, L / 2 + 0.03, y0 + sh - 0.12, s * (W / 2 - 0.12), 'metal')  # замки борта
    vb.lights(L / 2, 0.34, W)
    yt = y0 + sh
    if o.get('hoops'):
        K = 0x2b2d30
        H = 1.4
        for px in (-L / 2 + 0.03, 0, L / 2 - 0.03):
            for s in (-1, 1):
                vb.box(0.035, H, 0.035, K, px, yt - 0.05, s * (W / 2 - 0.03), 'metal')
            vb.box(0.035, 0.035, W, K, px, yt + H - 0.08, 0, 'metal')
        for s in (-1, 1):
            vb.box(L, 0.035, 0.035, K, 0, yt + H - 0.08, s * (W / 2 - 0.03), 'metal')
    tent = o.get('tent')
    if tent:
        H = 1.15 if L >= 3.8 else 1.05
        x0, x1, w2, ch = -L / 2 - 0.01, L / 2 + 0.01, W / 2 + 0.01, 0.07
        ya, yb = yt - 0.1, yt + H
        pts = []
        for x in (x0, x1):
            for s in (-1, 1):
                pts += [(x, ya, s * w2), (x, yb - ch, s * w2), (x, yb, s * (w2 - ch))]
        vb.hull(pts, tent, 'cloth')
        dk = max(0, tent - 0x202020) if tent > 0x303030 else tent
        # ремни по бокам и снизу шнуровка
        for s in (-1, 1):
            for px in [x0 + (x1 - x0) * k / 4 for k in (1, 2, 3)]:
                vb.box(0.03, H - 0.12, 0.006, dk, px, ya + 0.02, s * (w2 + 0.003), 'cloth')
            vb.box(L, 0.025, 0.006, 0x3a3c3f, 0, ya + 0.04, s * (w2 + 0.004), 'cloth')
        vb.box(0.006, 0.025, W, 0x3a3c3f, x1 + 0.003, ya + 0.04, 0, 'cloth')
    elif o.get('lid'):
        vb.ball(L * 0.5, 0.42, W * 0.5, o['lid'], 0, yt - 0.05, 0, 'paint', seg=16)


def plat(vb, o):
    """платформа-автовоз 4,5×2,0 (фото 1591, 1592): фанерный пол, чёрная рама, бортик-труба на стойках, трапы сзади"""
    K = BLACK
    L, W = 4.5, 2.0
    for s in (-1, 1):
        vb.box(L, 0.14, 0.08, K, 0, 0.46, s * 0.55, 'metal')
        vb.box(L, 0.05, 0.05, K, 0, 0.95, s * W / 2, 'metal')
        for px in (-L / 2 + 0.06, -L / 4, 0, L / 4, L / 2 - 0.06):
            vb.box(0.05, 0.32, 0.05, K, px, 0.64, s * W / 2, 'metal')
        vb.box(L + 0.04, 0.1, 0.06, K, 0, 0.56, s * W / 2, 'metal')
    vb.box(L, 0.025, W - 0.04, 0x4a3328, 0, 0.6, 0, 'wood')
    for i in range(1, 4):
        vb.box(0.012, 0.006, W - 0.06, 0x2e2018, -L / 2 + i * L / 4, 0.625, 0, 'wood')
    for ax in (-0.45, 0.45):
        vb.box(0.07, 0.07, 1.8, 0x55595e, ax, 0.27, 0, 'metal')
        for s in (-1, 1):
            vb.wheel(ax, 0.3, s * 0.85, 0.3, 0.2, rim=0x1d1f21, hub=0x55595e)
    vb.drawbar(L, K, y=0.42, spread=0.5, reach=1.25)
    for s in (-1, 1):
        vb.box(0.07, 1.0, 0.07, K, L / 2 - 0.05, 0.64, s * 0.6, 'metal')
        vb.box(0.04, 1.1, 0.36, 0x9aa3ab, L / 2 + 0.04, 0.64, s * 0.6, 'galv')
        for k in range(5):
            vb.box(0.05, 0.02, 0.34, 0x7c858d, L / 2 + 0.065, 0.72 + k * 0.2, s * 0.6, 'galv')
    vb.box(0.25, 0.04, 0.7, 0xc8ccd0, L / 2 + 0.13, 0.36, 0, 'galv')
    vb.lights(L / 2, 0.42, W)


def boat(vb, o):
    """лодочный прицеп без лодки (фото 1597, 1598): оцинкованный хребет 6 м, ложементы, зелёная стойка лебёдки"""
    Z, ZD, GN = ZINC, 0x9aa3ab, 0x3e9a4a
    vb.box(6.0, 0.12, 0.12, Z, 0.6, 0.34, 0, 'galv')
    for s in (-1, 1):
        vb.beam((-2.2, 0.4, s * 0.55), (-3.55, 0.4, s * 0.06), 0.08, 0.1, Z, 'galv')
    vb.box(0.24, 0.12, 0.14, ZD, -3.7, 0.36, 0, 'galv')
    vb.box(0.1, 0.1, 1.8, Z, 0.9, 0.36, 0, 'galv')
    vb.box(0.07, 0.07, 1.9, 0x55595e, 0.9, 0.25, 0, 'metal')
    for s in (-1, 1):
        vb.wheel(0.9, 0.28, s * 0.95, 0.275, 0.18)
        vb.box(0.9, 0.025, 0.3, Z, 0.9, 0.6, s * 0.95, 'galv')
    for px in (0.2, 2.4):
        vb.box(0.1, 0.08, 1.3, Z, px, 0.46, 0, 'galv')
    for s in (-1, 1):
        vb.box(1.6, 0.06, 0.16, 0x3a3d40, 1.3, 0.56, s * 0.45, 'cloth', rx=s * 0.3)
        vb.box(0.1, 0.2, 0.1, Z, -1.4, 0.44, s * 0.25, 'galv')
    vb.box(0.08, 0.9, 0.08, GN, -2.0, 0.4, 0, 'paint')
    vb.box(0.22, 0.16, 0.24, GN, -1.92, 1.2, 0, 'paint')
    vb.cyl(0.07, 0.2, 0x2a2b2d, -1.92, 1.1, 0, 'metal', seg=10)
    vb.box(0.06, 0.06, 0.9, ZD, 3.55, 0.36, 0, 'galv')
    vb.lights(3.58, 0.3, 0.9, side_z=0.4)


# ---------- легковая ----------
def car(vb, o):
    """легковая, нос на +x: кузов с капотом и багажником, салон со стёклами, колёса с дисками, фары, бамперы, номера"""
    L = o.get('L', 4.2)
    W = o.get('W', 1.65)
    H = o.get('H', 0.72)
    box = bool(o.get('box'))
    cab = o.get('cab', 2.0 if box else 2.2)
    ch = o.get('ch', 0.56)
    cx = o.get('cx', -0.15)
    col = o.get('c', 0xc0c0c0)
    y0 = 0.3
    suv = H > 0.85
    xr, xf = -L / 2, L / 2
    w1, w2 = W / 2, W / 2 - 0.07
    yt = y0 + H
    hood = yt - (0.02 if box else 0.06)
    nose = 0.16 if box else 0.28
    pts = []
    for s in (-1, 1):
        pts += [(xr + 0.06, y0, s * (w1 - 0.04)), (xf - 0.08, y0, s * (w1 - 0.04)),
                (xr, y0 + 0.12, s * w1), (xf, y0 + 0.12, s * w1),
                (xr, yt - 0.14, s * w2), (xr + 0.12, yt, s * w2),
                (cx - cab / 2, yt, s * w2), (cx + cab / 2, yt, s * w2),
                (xf - nose, hood, s * w2), (xf, hood - (0.1 if box else 0.2), s * (w2 - 0.03))]
    vb.hull(pts, col, 'paint')
    # салон: стёкла по бокам, крыша окрашена
    rb = 0.14 if (box or suv) else 0.38
    fb = 0.42 if box else (0.5 if suv else 0.62)
    gw0, gw1 = W / 2 - 0.08, W / 2 - 0.2
    yc = yt + ch
    pts = []
    for s in (-1, 1):
        pts += [(cx - cab / 2, yt - 0.005, s * gw0), (cx + cab / 2, yt - 0.005, s * gw0),
                (cx - cab / 2 + rb, yc, s * gw1), (cx + cab / 2 - fb, yc, s * gw1)]
    vb.hull(pts, col, 'paint', glass_sides=(0x262c33, 'vglass'))
    # стойки: средняя и рамки
    for s in (-1, 1):
        zz = s * (gw0 + gw1) / 2 + s * 0.012
        xm = cx + (rb - fb) / 4
        vb.box(0.09, ch - 0.02, 0.02, col, xm, yt, zz, 'paint', rx=-s * math.atan2(gw0 - gw1, ch))
    vb.box(cab - rb - fb + 0.04, 0.03, 2 * gw1 + 0.03, col, cx + (rb - fb) / 2, yc - 0.01, 0, 'paint')
    # колёса
    for px in (L * 0.31, -L * 0.31):
        for s in (-1, 1):
            vb.wheel(px, 0.31, s * (W / 2 - 0.1), 0.31, 0.2, rim=0x9aa1a7, hub=0x6e757b)
    # бамперы, фары, фонари, номера, зеркала
    for x, d in ((xf, 1), (xr, -1)):
        vb.box(0.1, 0.16, W - 0.02, 0x2b2d30 if not box else 0x9aa1a7, x + d * 0.01, y0 + 0.03, 0, 'metal')
        vb.box(0.02, 0.11, 0.52, 0xf4f4f2, x + d * 0.07, y0 + 0.05, 0, 'paint')
        vb.box(0.01, 0.06, 0.42, 0x2a2b2d, x + d * 0.081, y0 + 0.075, 0, 'metal')
    for s in (-1, 1):
        zz = s * (W / 2 - 0.25)
        vb.box(0.03, 0.12 if not box else 0.14, 0.34 if not box else 0.26, 0xf2f0e0, xf + 0.005, hood - 0.22, zz, 'paint')
        vb.box(0.03, 0.14, 0.34 if not box else 0.42, 0xb8322a, xr - 0.005, yt - 0.3, zz, 'paint')
        vb.box(0.12, 0.08, 0.1, col, cx + cab / 2 - fb * 0.4, yt + 0.12, s * (W / 2 + 0.03), 'paint')
    if not box:
        vb.box(0.02, 0.1, W * 0.55, 0x2a2d31, xf + 0.005, y0 + 0.24, 0, 'metal')   # решётка


BUILD = {'trailer': trailer, 'plat': plat, 'boat': boat, 'car': car}


def apply_rules(vehicles, rules):
    """правки по фото из twin/tools/vehicles.json"""
    out = [dict(v, rule=None) for v in vehicles]
    for r in rules['rules']:
        if r['do'] == 'add':
            # прицеп или машина, которых в старой игре не было, а на фото есть
            out.append({'kind': r['kind'], 'x': r['x'], 'y': 0.0, 'z': r['z'], 'ry': r['ry'], 'o': r.get('o', {}),
                        'lines': [], 'rule': r['why']})
            continue
        lines = set(r['lines'])
        sel = [v for v in out if v['lines'] and v['lines'][0] in lines and v.get('rule') is None
               and (not r.get('kind') or v['kind'] == r['kind'])]
        if 'second' in r:
            sel = [v for v in sel if len(v['lines']) > 1 and v['lines'][1] in set(r['second'])]
        if not sel:
            raise SystemExit('vehicles.json: правило «%s» ничего не нашло — index.html изменился?' % r['why'])
        do = r['do']
        for v in sel:
            v['rule'] = r['why']
        if do == 'drop':
            for v in sel:
                v['drop'] = True
        elif do == 'keep':
            sel.sort(key=lambda v: (v['x'], v['z']))
            for k, v in enumerate(sel):
                if k not in r['keep']:
                    v['drop'] = True
        elif do == 'row':
            # один ряд поперёк проезда: по x от x0 с шагом step, центр по z, поворот ry
            sel.sort(key=lambda v: (v['x'], v['z']))
            for k, v in enumerate(sel):
                v['x'] = r['x0'] + k * r['step']
                v['z'] = r['z']
                v['ry'] = r['ry']
        elif do == 'turn':
            for v in sel:
                v['ry'] = r['ry']
        else:
            raise SystemExit('vehicles.json: неизвестное действие ' + do)
    return [v for v in out if not v.get('drop')], len([v for v in out if v.get('drop')])


def build(meta_path, rules_path, mats):
    """mats: класс → материал Blender. Возвращает (объект, отчёт)"""
    import bpy
    meta = json.load(open(meta_path))
    rules = json.load(open(rules_path))
    keep, dropped = apply_rules(meta['vehicles'], rules)
    vb = VB()
    kinds = {}
    for v in keep:
        vb.M = T(v['x'], v.get('y', 0.0), v['z']) @ RY(v['ry'])
        BUILD[v['kind']](vb, v['o'])
        kinds[v['kind']] = kinds.get(v['kind'], 0) + 1
    # оси старой игры → Blender
    C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    bmesh.ops.transform(vb.bm, matrix=C, verts=vb.bm.verts)
    bmesh.ops.recalc_face_normals(vb.bm, faces=vb.bm.faces)
    me = bpy.data.meshes.new('world|veh')
    vb.bm.to_mesh(me)
    vb.bm.free()
    for c in vb.cls:
        me.materials.append(mats[c])
    # цвет вершин — активный и для рендера, иначе glTF выгружается без COLOR_0 (машины выходят белыми)
    ca = me.color_attributes['Color']
    me.color_attributes.active_color = ca
    me.color_attributes.render_color_index = list(me.color_attributes).index(ca)
    ob = bpy.data.objects.new('world|veh', me)
    bpy.context.scene.collection.objects.link(ob)
    rep = {'kept': kinds, 'dropped': dropped, 'polys': len(me.polygons)}
    return ob, rep
