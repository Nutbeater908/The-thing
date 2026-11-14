"""按原图真实像素网格重采样，保留 AI 像素画的原生分辨率。"""
from pathlib import Path
import sys

import numpy as np
from PIL import Image

## 位置参数：源图 输出图 [横向周期] [纵向周期]；可加 --clean 开启轮廓清理
ARGS = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
SRC = Path(ARGS[0])
OUT = Path(ARGS[1])
PX = float(ARGS[2]) if len(ARGS) > 2 else 0.0
PY = float(ARGS[3]) if len(ARGS) > 3 else 0.0

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
        if not peaks:
            return default
        # 谐波修正：整数倍周期同样会有高峰。取「足够强的最小周期」当作基频，
        # 否则会锁到 2 倍/4 倍，把精灵采得过粗。
        best = max(v for _, v in peaks)
        return min(i for i, v in peaks if v >= 0.80 * best)
    PX = PX or period(dx, w / 52)
    PY = PY or period(dy, h / 52)
    # 像素块必须近似正方形。自相关容易锁到整数倍谐波（例如纵向测成 4 倍），
    # 纵横相差过大时把大的一侧按整数倍折回最近的小的一侧。
    if PX > 0 and PY > 0:
        big = max(PX, PY)
        small = min(PX, PY)
        if big / small > 1.25:
            for k in (2, 3, 4):
                candidate = big / k
                if abs(candidate - small) / small <= 0.25:
                    big = candidate
                    break
            if PX > PY:
                PX = big
            else:
                PY = big

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

# 可选：清掉抠图残留的高亮轮廓（--clean）。默认关闭，保证已验证样本可逐字节复现。
# 只处理贴着透明区的轮廓像素，判据是「比邻居明显更亮且低饱和」，
# 但仍可能削掉浅色触须，所以必须人工看结果，不能默认开。
if "--clean" in sys.argv:
    for _pass in range(2):
        opaque = alpha > 0
        trans = ~opaque
        near_trans = np.zeros_like(opaque)
        near_trans[1:, :] |= trans[:-1, :]
        near_trans[:-1, :] |= trans[1:, :]
        near_trans[:, 1:] |= trans[:, :-1]
        near_trans[:, :-1] |= trans[:, 1:]
        lum = native[..., :3].astype(np.float32).mean(-1)
        rgbf = native[..., :3].astype(np.float32)
        mxf = rgbf.max(-1)
        mnf = rgbf.min(-1)
        satf = (mxf - mnf) / np.maximum(mxf, 1.0)
        cnt = np.zeros_like(lum)
        tot = np.zeros_like(lum)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            o = np.roll(np.roll(opaque, dy, 0), dx, 1)
            cnt += o
            tot += np.roll(np.roll(lum, dy, 0), dx, 1) * o
        has = cnt > 0
        neighbour_mean = np.where(has, tot / np.maximum(cnt, 1), 0.0)
        halo = opaque & near_trans & has & (satf < 0.35) & (lum > neighbour_mean + 35.0)
        if not halo.any():
            break
        alpha[halo] = 0
    native[..., 3] = alpha

# 可选：轮廓收缩 N 像素（--shrink=N，默认 0）。
# 对应 PS 的「选择 > 修改 > 收缩」，用来丢掉轮廓最外那圈抗锯齿浅色像素。
# 必须在描边之前做：否则外扩描边会绕过这些浅色像素，把它们包成一圈白点。
SHRINK = 0
for arg in sys.argv[1:]:
    if arg.startswith("--shrink="):
        SHRINK = int(arg.split("=", 1)[1])
if SHRINK > 0:
    for _step in range(SHRINK):
        op = native[..., 3] > 0
        cnt = np.zeros(op.shape, dtype=np.uint8)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            cnt += np.roll(np.roll(op, dy, 0), dx, 1).astype(np.uint8)
        keep = op & (cnt == 4)
        native[..., 3] = np.where(keep, 255, 0).astype(np.uint8)

# 可选：向外加粗轮廓（--outline N，默认 0 关闭）。
# 向透明区扩张 N 圈并填成深色，绝不侵占精灵本体。
# 画布先按 N 扩边再裁回，超出格子的部分直接切掉——所以本体要留够留白。
OUTLINE = 0
for arg in sys.argv[1:]:
    if arg.startswith("--outline="):
        OUTLINE = int(arg.split("=", 1)[1])
if OUTLINE > 0:
    hh, ww = native.shape[:2]
    pad = OUTLINE
    big = np.zeros((hh + pad * 2, ww + pad * 2, 4), dtype=np.uint8)
    big[pad:pad + hh, pad:pad + ww] = native
    opaque = big[..., 3] > 0
    grown = opaque.copy()
    for _step in range(OUTLINE):
        prev = grown.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            grown |= np.roll(np.roll(prev, dy, 0), dx, 1)
    ring = grown & ~opaque
    big[ring] = (24, 14, 16, 255)
    big[..., 3] = np.where(grown, 255, 0).astype(np.uint8)
    native = big[pad:pad + hh, pad:pad + ww]

# 可选：把中性灰过渡像素并进描边。
#   --degrey=all  全图生效（器官内部没有灰组织时用这个，最干净）
#   --degrey=N    只作用于离透明区 N 圈以内（内部有灰色组织时用，例如小脑）
# 模型的黑描边与白背景在降采样时会混出中性灰（rgb 三通道几乎相等），
# 它们既不满足"白≥235"也没被描边覆盖，在边缘上一眼就是灰点。
DEGREY = ""
DEGREY_ALL = False
for arg in sys.argv[1:]:
    if arg.startswith("--degrey="):
        DEGREY = arg.split("=", 1)[1]
        DEGREY_ALL = DEGREY == "all"
        if not DEGREY_ALL:
            DEGREY = int(DEGREY)
if DEGREY_ALL or DEGREY:
    rgbd = native[..., :3].astype(np.float32)
    mxd = rgbd.max(-1)
    mnd = rgbd.min(-1)
    satd = (mxd - mnd) / np.maximum(mxd, 1.0)
    lumn = rgbd.mean(-1)
    opd = native[..., 3] > 0
    near_rim = np.ones(opd.shape, dtype=bool)
    if not DEGREY_ALL:
        trd = ~opd
        distd = np.full(opd.shape, 99, dtype=np.int32)
        distd[trd] = 0
        for _step in range(DEGREY):
            prevd = distd.copy()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                distd = np.minimum(distd, np.roll(np.roll(prevd, dy, 0), dx, 1) + 1)
        near_rim = distd <= DEGREY
    grey = opd & near_rim & (satd < 0.14) & (lumn > 55.0) & (lumn < 235.0)
    native[grey] = (24, 14, 16, 255)

# 可选：补掉轮廓上的针孔（--close=N，默认 0）。
# 采样后描边常出现 1px 破洞，背景色从洞里透出来，看着就是边缘白灰点。
# 判据：透明像素若有 3 个以上不透明邻居，就用描边色填上。
CLOSE = 0
for arg in sys.argv[1:]:
    if arg.startswith("--close="):
        CLOSE = int(arg.split("=", 1)[1])
if CLOSE > 0:
    for _step in range(CLOSE):
        op = native[..., 3] > 0
        cnt = np.zeros(op.shape, dtype=np.uint8)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            cnt += np.roll(np.roll(op, dy, 0), dx, 1).astype(np.uint8)
        hole = (~op) & (cnt >= 3)
        if not hole.any():
            break
        native[hole] = (24, 14, 16, 255)

img = Image.fromarray(native, "RGBA")
if "--tile" in sys.argv:
    # 格子贴图：保持采样网格原封不动（固定 nx×ny），不裁切、不居中。
    # 平铺成多格器官时，边缘必须严格对齐。
    canvas = img
else:
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    # 居中放进正方形画布
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
side = max(canvas.size)
canvas.save(OUT)

# 预览用棋盘格底：一眼能看出这是"透明预览"，避免把它当成成品另存。
pw = side * 6
yy, xx = np.mgrid[0:pw, 0:pw]
check = (((xx // 16) + (yy // 16)) % 2 == 0)
base = np.empty((pw, pw, 4), dtype=np.uint8)
base[check] = (205, 205, 205, 255)
base[~check] = (125, 125, 125, 255)
prev = Image.fromarray(base, "RGBA")
up = canvas.resize((pw, pw), Image.NEAREST)
prev.alpha_composite(up)
prev.convert("RGB").save(OUT.with_name(OUT.stem + "_preview.png"))
print(f"period=({PX:.1f},{PY:.1f}) native={nx}x{ny} -> {side}x{side}")
