"""把 AI 生成的像素图裁成透明背景的 32x32 游戏精灵。"""
from collections import Counter, deque
from pathlib import Path
import sys

import numpy as np
from PIL import Image

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2])
TARGET = int(sys.argv[3]) if len(sys.argv) > 3 else 32

img = Image.open(SRC).convert("RGBA")
a = np.array(img)
h, w = a.shape[:2]

# 0. 有些模型会把“透明”画成棋盘格外框，先把真正的白色画布裁出来
bright = (a[..., 0] > 200) & (a[..., 1] > 200) & (a[..., 2] > 200)
ys, xs = np.where(bright)
if len(xs) and bright.sum() > 0.05 * h * w:
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    if box != (0, 0, w, h):
        print(f"cropped checkerboard frame -> {box}")
        a = a[box[1]:box[3], box[0]:box[2]]
        h, w = a.shape[:2]

rgb = a[..., :3].astype(np.int16)

# 1. 只去掉与画布边缘连通的近白像素，保留器官内部的高光
white = (rgb[..., 0] >= 235) & (rgb[..., 1] >= 235) & (rgb[..., 2] >= 235)
visited = np.zeros((h, w), bool)
q = deque()
for x in range(w):
    for y in (0, h - 1):
        if white[y, x] and not visited[y, x]:
            visited[y, x] = True
            q.append((y, x))
for y in range(h):
    for x in (0, w - 1):
        if white[y, x] and not visited[y, x]:
            visited[y, x] = True
            q.append((y, x))
while q:
    y, x = q.popleft()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w and white[ny, nx] and not visited[ny, nx]:
            visited[ny, nx] = True
            q.append((ny, nx))
a[visited, 3] = 0

out = Image.fromarray(a, "RGBA")
bbox = out.getbbox()
out = out.crop(bbox)

# 2. 估一下原图的“逻辑像素块”大小
runs = Counter()
arr = np.array(out)
hh, ww = arr.shape[:2]
for y in range(hh):
    row = arr[y, :, :3]
    start = 0
    for x in range(1, ww + 1):
        if x == ww or not np.array_equal(row[x], row[start]):
            n = x - start
            if 0 < n <= 40:
                runs[n] += 1
            start = x
block = runs.most_common(1)[0][0] if runs else 1
print(f"cropped={ww}x{hh} estimated_block={block} top_runs={runs.most_common(5)}")

# 3. 先按逻辑像素还原，再最近邻缩放到目标尺寸并居中
logical = out.resize((max(1, round(ww / block)), max(1, round(hh / block))), Image.NEAREST)
scale = (TARGET - 2) / max(logical.size)
size = (max(1, round(logical.width * scale)), max(1, round(logical.height * scale)))
small = logical.resize(size, Image.NEAREST)

canvas = Image.new("RGBA", (TARGET, TARGET), (0, 0, 0, 0))
canvas.paste(small, ((TARGET - size[0]) // 2, (TARGET - size[1]) // 2))
canvas.save(OUT)

# 4. 棋盘格预览
prev = Image.new("RGBA", (TARGET * 8, TARGET * 8), (40, 40, 46, 255))
for yy in range(TARGET * 8):
    for xx in range(TARGET * 8):
        if ((xx // 8) + (yy // 8)) % 2:
            prev.putpixel((xx, yy), (58, 58, 66, 255))
prev.alpha_composite(canvas.resize((TARGET * 8, TARGET * 8), Image.NEAREST))
prev.save(OUT.with_name(OUT.stem + "_preview.png"))
print(f"saved {OUT} and preview")
