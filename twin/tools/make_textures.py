"""Бесшовные текстуры для двойника завода (numpy + PIL): детальная яркость (умножается на цвет вершин),
карты нормалей и шероховатости. Все в реальных размерах: в Godot накладываются трипланарно по мировым метрам.
Запуск: python3 twin/tools/make_textures.py twin/godot/textures"""
import sys, os, numpy as np
from PIL import Image
OUT = sys.argv[1] if len(sys.argv) > 1 else 'twin/godot/textures'
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(156944872)
N = 512

def fbm(n=N, octaves=6, base=4, seed=0, aniso=(1, 1)):
    """Бесшовный фрактальный шум через случайный спектр (FFT), 0..1."""
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(n)[:, None] * n / aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * n / aniso[0]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1
    amp = 1 / (f ** 1.15)
    amp[f < base * 0.5] *= 0.6
    amp[f > n / 2.2] = 0
    ph = r.uniform(0, 2 * np.pi, (n, n))
    z = np.real(np.fft.ifft2(amp * np.exp(1j * ph)))
    z = (z - z.min()) / (z.max() - z.min())
    return z

def norm_from_h(h, strength):
    gy, gx = np.gradient(h)
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(h)
    l = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    return np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5

def save(name, arr, mode='L'):
    a = np.clip(arr, 0, 1)
    if a.ndim == 2:
        img = Image.fromarray((a * 255).astype(np.uint8), 'L').convert('RGB')
    else:
        img = Image.fromarray((a * 255).astype(np.uint8), 'RGB')
    img.save(os.path.join(OUT, name + '.png'), optimize=True)

y, x = np.mgrid[0:N, 0:N] / N  # 0..1

# 1. Профлист: тайл 1×1 м, шаг волны 0,2 м (5 трапеций), трапеция с плоскими полками
def trapezoid(u, period=0.2, top=0.35):
    t = (u / period) % 1.0
    # 0..1: низ полки, скат, верх, скат
    s = np.clip((np.abs(t - 0.5) * 2 - top) / (1 - top) * 1.0, 0, 1)
    h = 1 - np.clip((np.abs(t - 0.5) * 2 - top * 0.5) / (1 - top), 0, 1)
    return h
h = trapezoid(x)
n_streak = fbm(seed=1, aniso=(1, 12))  # вертикальные потёки
grime = fbm(seed=2)
alb = 0.86 + 0.08 * (h - 0.5) - 0.10 * (n_streak - 0.5) - 0.06 * (grime - 0.5)
alb -= 0.08 * np.clip(1 - y * 3, 0, 1) * 0  # без затемнения низа (тайл)
save('corr_albedo', alb)
save('corr_normal', norm_from_h(h * 6.0, 1.0))
save('corr_rough', 0.45 + 0.25 * n_streak + 0.1 * grime)
# тот же профлист с волной вдоль z (крыши, где конёк идёт вдоль z): для плоскости XZ трипланара
hz = trapezoid(y)
save('corrz_albedo', 0.86 + 0.08 * (hz - 0.5) - 0.08 * (grime - 0.5))
save('corrz_normal', norm_from_h(hz * 6.0, 1.0))

# 2. Кирпич: тайл 1,04 (4 кирпича по 0,25 + шов 0,01) × 0,75 м (10 рядов по 0,065 + 0,01)
W, H = 1.04, 0.75
bx, by = x * W, y * H
row = np.floor(by / 0.075)
off = (row % 2) * 0.13
bu = ((bx + off) % 0.26)
bv = by % 0.075
mortar = (bu < 0.01) | (bv < 0.01)
brick_id = np.floor((bx + off) / 0.26) + row * 7
rb = np.random.default_rng(3).uniform(0.8, 1.06, 400)
tone = rb[(brick_id.astype(int)) % 400]
alb = np.where(mortar, 0.98, tone * (0.92 + 0.08 * fbm(seed=4)))
save('brick_albedo', alb)
hb = np.where(mortar, 0.0, 1.0) * 0.8 + 0.2 * fbm(seed=5)
save('brick_normal', norm_from_h(hb * 3.0, 1.0))
save('brick_rough', np.where(mortar, 0.95, 0.8))

# 3. Бетонные стеновые панели: тайл 6×1,2 м — горизонтальный шов внизу, вертикальный в начале, пятна
W, H = 6.0, 1.2
px, py = x * W, y * H
seam = (py < 0.025) | (px < 0.025)
st = fbm(seed=6, aniso=(1, 4))
alb = 0.9 - 0.18 * (st - 0.5) - 0.06 * (fbm(seed=7) - 0.5)
alb = np.where(seam, 0.55, alb)
save('panel_albedo', alb)
save('panel_normal', norm_from_h(np.where(seam, 0.0, 1.0) * 2 + fbm(seed=8) * 0.6, 1.0))
save('panel_rough', 0.88 + 0.08 * st)

# 4. Плиты ПАГ на земле: тайл 6×2 м, швы по краю, сколы
W, H = 6.0, 2.0
px, py = x * W, y * H
seam = (py < 0.03) | (px < 0.03)
c1, c2 = fbm(seed=9), fbm(seed=10, base=16)
alb = 0.9 - 0.14 * (c1 - 0.5) - 0.08 * (c2 - 0.5)
alb = np.where(seam, 0.45, alb)
save('slab_albedo', alb)
save('slab_normal', norm_from_h(np.where(seam, 0.0, 1.0) * 2 + c2 * 0.8, 1.0))
save('slab_rough', 0.85 + 0.1 * c1)

# 5. Асфальт: тайл 4×4 м — зерно, заплатки, трещины
g = fbm(seed=11, base=64)
pt = fbm(seed=12, base=2)
alb = 0.82 + 0.12 * (g - 0.5) - 0.14 * (pt > 0.62)
crack = np.abs(fbm(seed=13, base=6) - 0.5) < 0.006
alb = np.where(crack, 0.5, alb)
save('asphalt_albedo', alb)
save('asphalt_normal', norm_from_h(g * 1.5 - crack * 1.0, 1.0))
save('asphalt_rough', 0.9 - 0.05 * g)

# 6. Грунт/щебень: тайл 4×4 м
g1, g2 = fbm(seed=14, base=48), fbm(seed=15, base=3)
alb = 0.8 + 0.18 * (g1 - 0.5) + 0.14 * (g2 - 0.5)
save('dirt_albedo', alb)
save('dirt_normal', norm_from_h(g1 * 2.5, 1.0))
save('dirt_rough', np.full((N, N), 0.95))

# 7. Трава: тайл 4×4 м — пятнистая, с проплешинами
g1, g2 = fbm(seed=16, base=80), fbm(seed=17, base=3)
alb = 0.78 + 0.25 * (g1 - 0.5) + 0.18 * (g2 - 0.5)
save('grass_albedo', alb)
save('grass_normal', norm_from_h(g1 * 2.0, 1.0))

# 8. Металл (окрашенный): тайл 2×2 м — лёгкие пятна и царапины
g1, g2 = fbm(seed=18, base=6), fbm(seed=19, base=40)
scr = (np.abs(fbm(seed=20, base=20, aniso=(8, 1)) - 0.5) < 0.004)
alb = 0.92 - 0.08 * (g1 - 0.5) - 0.04 * (g2 - 0.5) + 0.06 * scr
save('metal_albedo', alb)
save('metal_rough', 0.45 + 0.25 * g1 - 0.15 * scr)
save('metal_normal', norm_from_h(g2 * 0.5, 1.0))

# 9. Оцинковка: тайл 1×1 м — «цветы» цинка
cells = fbm(seed=21, base=60)
alb = 0.9 + 0.1 * (np.floor(cells * 6) / 6 - 0.5)
save('galv_albedo', alb)
save('galv_rough', 0.3 + 0.25 * cells)

# 10. Ржавчина: тайл 2×2 м
g1, g2 = fbm(seed=22, base=5), fbm(seed=23, base=50)
alb = 0.8 + 0.25 * (g1 - 0.5) + 0.12 * (g2 - 0.5)
save('rust_albedo', alb)
save('rust_normal', norm_from_h(g2 * 1.5 + g1, 1.0))

# 11. Дерево/фанера: тайл 1×1 м, волокна вдоль x
g = fbm(seed=24, base=8, aniso=(16, 1))
alb = 0.85 + 0.2 * (np.sin((y * 40 + g * 6) * np.pi) * 0.5) * 0.5 + 0.08 * (g - 0.5)
save('wood_albedo', alb)

# 12. Ткань тента: тайл 1×1 м — плетение
wv = 0.5 + 0.25 * np.sin(x * N * np.pi / 2) * np.sin(y * N * np.pi / 2)
alb = 0.9 + 0.06 * (wv - 0.5) - 0.08 * (fbm(seed=25) - 0.5)
save('fabric_albedo', alb)
print('ok', sorted(os.listdir(OUT)))
