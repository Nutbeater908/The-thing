"""把裁好的透明大图降采样成干净的 32x32 像素精灵（限色 + 去边缘杂色）。"""
from collections import Counter
from pathlib import Path
import sys

import numpy as np
from PIL import Image

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2])
TARGET = int(sys.argv[3]) if len(sys.argv) > 3 else 32
COLORS = int(sys.argv[4]) if len(sys.argv) > 4 else 12

img = Image.open(SRC).convert("RGBA")
a = np.array(img)
h, w = a.shape[:2]
rgb = a[..., :3].astype(np.int16)

# 棋盘格边框裁剪
bright = (rgb[..., 0] > 200) & (rgb[..., 1] > 200) & (rgb[..., 2] > 200)
if bright.sum() > 0.05 * h * w:
    ys, xs = np.where(bright)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    if box != (0, 0, w, h):
        a = a[box[1]:box[3], box[0]:box[2]]
        h, w = a.shape[:2]
        rgb = a[..., :3].astype(np.int16)

# 从边缘泛洪去除白底
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

out = Image.fromarray(a, "RGBA").crop(Image.fromarray(a, "RGBA").getbbox())
alpha = out.getchannel("A").resize((TARGET, TARGET), Image.LANCZOS)

# 颜色降采样 + 限色
small = out.convert("RGB").resize((TARGET, TARGET), Image.LANCZOS)
small = small.quantize(colors=COLORS, method=Image.MEDIANCUT).convert("RGB")

result = np.array(small.convert("RGBA"))
result[..., 3] = np.array(alpha)
# 透明度二值化，并清掉孤立像素
result[..., 3] = np.where(result[..., 3] >= 96, 255, 0)

# 清掉缩小时混进来的浅色边缘杂点
opaque = result[..., 3] > 0
trans = ~opaque
near_trans = np.zeros_like(opaque)
near_trans[1:, :] |= trans[:-1, :]
near_trans[:-1, :] |= trans[1:, :]
near_trans[:, 1:] |= trans[:, :-1]
near_trans[:, :-1] |= trans[:, 1:]
rgbf = result[..., :3].astype(np.float32)
mx = rgbf.max(-1)
mn = rgbf.min(-1)
sat = (mx - mn) / np.maximum(mx, 1.0)
result[opaque & near_trans & (mx > 140) & (sat < 0.35), 3] = 0

opaque = result[..., 3] > 0
for _ in range(1):
    nb = np.zeros_like(opaque, dtype=np.uint8)
    nb[1:, :] += opaque[:-1, :]
    nb[:-1, :] += opaque[1:, :]
    nb[:, 1:] += opaque[:, :-1]
    nb[:, :-1] += opaque[:, 1:]
    result[(opaque) & (nb < 2), 3] = 0

Image.fromarray(result, "RGBA").save(OUT)

prev = Image.new("RGB", (TARGET * 8, TARGET * 8), (30, 30, 36))
prev.paste(Image.fromarray(result, "RGBA").resize((TARGET * 8, TARGET * 8), Image.NEAREST), (0, 0), Image.fromarray(result, "RGBA").resize((TARGET * 8, TARGET * 8), Image.NEAREST))
prev.save(OUT.with_name(OUT.stem + "_preview.png"))
colors = Counter(map(tuple, result[opaque][:, :3])).most_common(COLORS)
print(f"saved {OUT}, opaque={int(opaque.sum())}, colors={len(colors)}")
