"""按原图真实像素网格重采样，保留 AI 像素画的原生分辨率。"""
from pathlib import Path
import sys

import numpy as np
from PIL import Image

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2])
PX = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
PY = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0

a = np.array(Image.open(SRC).convert("RGBA"))
h, w = a.shape[:2]

# 裁掉模型画出来的棋盘格外框
rgb = a[..., :3].astype(np.int16)
bright = (rgb[..., 0] > 200) & (rgb[..., 1] > 200) & (rgb[..., 2] > 200)
if bright.sum() > 0.05 * h * w:
    ys, xs = np.where(bright)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = a.shape[:2]
    rgb = a[..., :3].astype(np.int16)

# 从边缘泛洪去白底
white = (rgb[..., 0] >= 235) & (rgb[..., 1] >= 235) & (rgb[..., 2] >= 235)
seen = np.zeros((h, w), bool)
stack = [(y, x) for x in range(w) for y in (0, h - 1) if white[y, x]]
stack += [(y, x) for y in range(h) for x in (0, w - 1) if white[y, x]]
for y, x in stack:
    seen[y, x] = True
while stack:
    y, x = stack.pop()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w and white[ny, nx] and not seen[ny, nx]:
            seen[ny, nx] = True
            stack.append((ny, nx))
a[seen, 3] = 0

# 自动测周期
g = a[..., :3].mean(-1)
if PX <= 0 or PY <= 0:
    dx = np.abs(np.diff(g, axis=1)).sum(0)
    dy = np.abs(np.diff(g, axis=0)).sum(1)
    def period(p, default):
        p = p - p.mean()
        ac = np.correlate(p, p, "full")[len(p) - 1:]
        ac = ac / ac[0]
        peaks = [(i, ac[i]) for i in range(8, min(60, len(ac) - 1))
                 if ac[i] > ac[i - 1] and ac[i] > ac[i + 1]]
        return max(peaks, key=lambda t: t[1])[0] if peaks else default
    PX = PX or period(dx, w / 52)
    PY = PY or period(dy, h / 52)

nx = max(1, round(w / PX))
ny = max(1, round(h / PY))
xs = ((np.arange(nx) + 0.5) * w / nx).astype(int).clip(0, w - 1)
ys = ((np.arange(ny) + 0.5) * h / ny).astype(int).clip(0, h - 1)
native = a[np.ix_(ys, xs)].copy()

# 透明边缘二值化 + 清孤立点
alpha = native[..., 3]
alpha = np.where(alpha >= 110, 255, 0).astype(np.uint8)
opaque = alpha > 0
for _ in range(1):
    nb = np.zeros_like(opaque, dtype=np.uint8)
    nb[1:, :] += opaque[:-1, :]
    nb[:-1, :] += opaque[1:, :]
    nb[:, 1:] += opaque[:, :-1]
    nb[:, :-1] += opaque[:, 1:]
    alpha[opaque & (nb < 2)] = 0
native[..., 3] = alpha

# 清掉采样时带入的浅色抗锯齿边缘
opaque = alpha > 0
trans = ~opaque
near_trans = np.zeros_like(opaque)
near_trans[1:, :] |= trans[:-1, :]
near_trans[:-1, :] |= trans[1:, :]
near_trans[:, 1:] |= trans[:, :-1]
near_trans[:, :-1] |= trans[:, 1:]
rgbf = native[..., :3].astype(np.float32)
mx = rgbf.max(-1)
mn = rgbf.min(-1)
sat = (mx - mn) / np.maximum(mx, 1.0)
native[opaque & near_trans & (mx > 170) & (sat < 0.28), 3] = 0

img = Image.fromarray(native, "RGBA")
bbox = img.getbbox()
if bbox:
    img = img.crop(bbox)
# 居中放进正方形画布
side = max(img.size)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
canvas.save(OUT)

prev = Image.new("RGBA", (side * 6, side * 6), (30, 30, 36, 255))
up = canvas.resize((side * 6, side * 6), Image.NEAREST)
prev.alpha_composite(up)
prev.convert("RGB").save(OUT.with_name(OUT.stem + "_preview.png"))
print(f"period=({PX:.1f},{PY:.1f}) native={nx}x{ny} -> {side}x{side}")
