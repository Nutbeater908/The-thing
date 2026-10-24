"""清掉精灵周围残留的灰色阴影。

AI 生成的图常带一层中性灰投影，make_sprite_native.py 只按近白像素抠图，
灰色会残留成脏边。这里把「低饱和 + 中高亮度」的像素设为透明。

用法：
    uv run --with pillow python art/organs/cleanup_shadow.py <输入.png> <输出.png>
"""

import sys

from PIL import Image

# 灰阶判定：三通道最大差 <= 阈值，且亮度够高（避免误伤黑色轮廓）
SAT_TOLERANCE = 18
MIN_BRIGHTNESS = 85


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    img = Image.open(src).convert("RGBA")
    pixels = img.load()
    width, height = img.size

    cleared = 0
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            hi = max(r, g, b)
            lo = min(r, g, b)
            if hi - lo <= SAT_TOLERANCE and hi >= MIN_BRIGHTNESS:
                pixels[x, y] = (r, g, b, 0)
                cleared += 1

    img.save(dst)
    print(f"cleared {cleared} shadow pixels -> {dst}")


if __name__ == "__main__":
    main()
