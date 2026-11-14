from PIL import Image
import numpy as np
from pathlib import Path

SRC = Path(r"C:\Users\19453\.dsh\attachments\v1\objects\e7\e7eed01e84ee434da5a82c90913d5e5cfbeec900a78888a1759c6df99c653466")
DST = Path(r"D:/the-thing/art/parts/chassis_scout.png")
DST.parent.mkdir(parents=True, exist_ok=True)

img = Image.open(SRC).convert("RGBA")
a = np.array(img)
rgb = a[:, :, :3].astype(np.int16)
# 白底：三通道都接近 255
mask = (rgb[:, :, 0] > 242) & (rgb[:, :, 1] > 242) & (rgb[:, :, 2] > 242)
a[:, :, 3] = np.where(mask, 0, a[:, :, 3])
img = Image.fromarray(a)
bbox = img.getbbox()
img = img.crop(bbox)
w, h = img.size
print("crop", w, h)

TW, TH = 128, 192
scale = min(TW / w, TH / h)
img = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)

canvas = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
canvas.paste(img, ((TW - img.size[0]) // 2, TH - img.size[1]), img)
canvas.save(DST)
print("saved", DST, canvas.size)
