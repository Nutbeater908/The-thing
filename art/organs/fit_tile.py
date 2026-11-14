"""把一张生成图处理成指定尺寸的格子贴图，等比缩放、不拉伸。

用法：python fit_tile.py 源图 输出图 目标宽 目标高 [像素周期]

流程：
  1. 从边缘泛洪去掉白底
  2. 按像素周期重采样（保留原生像素感）
  3. 裁到内容包围盒
  4. 等比缩放到目标框内（contain），居中，不拉伸
"""
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
SRC = Path(ARGS[0])
OUT = Path(ARGS[1])
TW = int(ARGS[2])
TH = int(ARGS[3])
PERIOD = float(ARGS[4]) if len(ARGS) > 4 else 8.0

a = np.array(Image.open(SRC).convert("RGBA"))
h, w = a.shape[:2]

# 1) 边缘泛洪去白底
rgb = a[..., :3].astype(np.int16)
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

# 2) 按周期重采样
nx = max(1, round(w / PERIOD))
ny = max(1, round(h / PERIOD))
xs = ((np.arange(nx) + 0.5) * w / nx).astype(int).clip(0, w - 1)
ys = ((np.arange(ny) + 0.5) * h / ny).astype(int).clip(0, h - 1)
native = a[np.ix_(ys, xs)].copy()

# alpha 二值化
native[..., 3] = np.where(native[..., 3] >= 110, 255, 0).astype(np.uint8)

img = Image.fromarray(native, "RGBA")

# 3) 裁到内容
bbox = img.getbbox()
if bbox:
    img = img.crop(bbox)

# 4) 等比缩放（contain），不拉伸
scale = min(TW / img.width, TH / img.height)
new_w = max(1, min(TW, round(img.width * scale)))
new_h = max(1, min(TH, round(img.height * scale)))
img = img.resize((new_w, new_h), Image.NEAREST)

canvas = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
canvas.paste(img, ((TW - new_w) // 2, (TH - new_h) // 2))
canvas.save(OUT)

# 预览：棋盘格 + 6 倍
pw, ph = TW * 6, TH * 6
yy, xx = np.mgrid[0:ph, 0:pw]
check = ((xx // 12) + (yy // 12)) % 2 == 0
base = np.empty((ph, pw, 4), dtype=np.uint8)
base[check] = (205, 205, 205, 255)
base[~check] = (125, 125, 125, 255)
prev = Image.fromarray(base, "RGBA")
prev.alpha_composite(canvas.resize((pw, ph), Image.NEAREST))
prev.convert("RGB").save(OUT.with_name(OUT.stem + "_preview.png"))

print(f"native={nx}x{ny} crop={img.size} -> {TW}x{TH} (scale {scale:.2f})")
