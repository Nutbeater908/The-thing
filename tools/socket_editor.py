"""部件接口标定工具（开发者工具，面向 mod 作者）。

    python tools/socket_editor.py [部件名]

左键=设定当前接口   方向键=微调1px（Shift=5px）   Tab=切换接口
1..9=切换贴图   F=参照叠加   G=网格   滚轮=缩放   S=保存   R=重置   Q=退出
"""
import re
import sys
import tkinter as tk
from pathlib import Path

from PIL import Image, ImageTk

MARGIN = 40  # 画布四周留白（世界像素）


def project_root(start: Path) -> Path:
    for p in [start, *start.parents]:
        if (p / "project.godot").exists():
            return p
    return start.parent


def resolve(res_path: str, root: Path) -> Path:
    return root / res_path.replace("res://", "")


def guess_image(uid: str, count: int) -> int:
    if count <= 1:
        return 0
    if uid.endswith("_l") or uid in ("pivot_foot", "pivot_ankle"):
        return 1
    return 0


def parse(tres: Path):
    text = tres.read_text(encoding="utf-8")

    images = []
    for line in re.finditer(r'\[ext_resource[^\]]*\]', text):
        raw = line.group(0)
        if 'type="Texture2D"' not in raw:
            continue
        mp = re.search(r'path="([^"]+)"', raw)
        if mp and mp.group(1) not in images:
            images.append(mp.group(1))

    tex_offset = (0.0, 0.0)
    m = re.search(r"texture_offset = Vector2\((-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?)\)", text)
    if m:
        tex_offset = (float(m.group(1)), float(m.group(2)))

    entries = []
    for blk in re.finditer(r'\[sub_resource type="Resource" id="[^"]+"\](.*?)(?=\n\[|\Z)', text, re.S):
        body = blk.group(1)
        uid = re.search(r'uid = &"([^"]+)"', body)
        off = re.search(r"offset = Vector2\((-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?)\)", body)
        if uid and off:
            entries.append({
                "span": blk.span(1),
                "uid": uid.group(1),
                "pos": (float(off.group(1)), float(off.group(2))),
                "new": None,
                "img": guess_image(uid.group(1), len(images)),
            })
    return text, images, tex_offset, entries


class Editor:
    def __init__(self, root: tk.Tk, part: str):
        self.root = root
        self.proj = project_root(Path.cwd())
        self.parts = sorted((self.proj / "resources" / "parts").glob("*.tres"))
        self.zoom = 3.0
        self.show_grid = True
        self.show_ref = True
        self.index = 0
        self.img_index = 0
        self.img_cache = {}

        frame = tk.Frame(root)
        frame.pack(fill="both", expand=True)
        self.canvas = tk.Canvas(frame, bg="white", highlightthickness=0)
        self.canvas.pack(side="left", padx=6, pady=6)
        side = tk.Frame(frame)
        side.pack(side="right", fill="y", padx=8, pady=8)

        tk.Label(side, text="部件", anchor="w").pack(fill="x")
        names = [p.stem for p in self.parts]
        self.part_var = tk.StringVar(value=part if part in names else (names[0] if names else ""))
        om = tk.OptionMenu(side, self.part_var, *names, command=self.open_part)
        om.config(anchor="w")
        om.pack(fill="x", pady=(0, 8))

        self.img_label = tk.Label(side, anchor="w", justify="left", fg="#333")
        self.img_label.pack(fill="x")
        self.info = tk.Label(side, justify="left", anchor="n", font=("Consolas", 10), width=36)
        self.info.pack(fill="both", expand=True)

        self.canvas.bind("<Button-1>", self.on_click)
        self.canvas.bind("<MouseWheel>", self.on_wheel)
        root.bind("<Tab>", lambda e: self.cycle(1))
        root.bind("<Shift-Tab>", lambda e: self.cycle(-1))
        for i in range(1, 10):
            root.bind(str(i), lambda e, n=i - 1: self.select_image(n))
        root.bind("<Left>", lambda e: self.nudge(-1, 0, e))
        root.bind("<Right>", lambda e: self.nudge(1, 0, e))
        root.bind("<Up>", lambda e: self.nudge(0, -1, e))
        root.bind("<Down>", lambda e: self.nudge(0, 1, e))
        root.bind("g", lambda e: self.toggle("show_grid"))
        root.bind("f", lambda e: self.toggle("show_ref"))
        root.bind("s", lambda e: self.save())
        root.bind("r", lambda e: self.reset())
        root.bind("q", lambda e: root.destroy())

        self.open_part(self.part_var.get())
        self.render()

    # ---------------------------------------------------------------- 载入
    def open_part(self, name: str):
        target = next((p for p in self.parts if p.stem == name), None)
        if target is None:
            return
        self.tres = target
        self.text, self.images, self.tex_offset, self.entries = parse(target)
        self.index = 0
        self.img_index = min(guess_image(self.entries[0]["uid"], len(self.images)), max(0, len(self.images) - 1))
        self.img_cache = {}
        if self.entries:
            self.part_var.set(name)
            self.show_image(self.img_index)
        self.render()

    def image(self, i: int):
        if i not in self.img_cache:
            im = Image.open(resolve(self.images[i], self.proj)).convert("RGBA")
            self.img_cache[i] = im
        return self.img_cache[i]

    def show_image(self, i: int):
        if not self.images:
            return
        self.img_index = max(0, min(i, len(self.images) - 1))
        self.img_label.config(text="\n".join(
            "%d. %s%s" % (k + 1, Path(p).name, "  ←" if k == self.img_index else "")
            for k, p in enumerate(self.images)))

    # ---------------------------------------------------------------- 数据
    def cur(self):
        return self.entries[self.index]

    def value(self, e):
        return e["new"] if e["new"] is not None else e["pos"]

    def tex_xy(self, e):
        x, y = self.value(e)
        return (x - self.tex_offset[0], y - self.tex_offset[1])

    def cycle(self, step):
        if not self.entries:
            return
        self.index = (self.index + step) % len(self.entries)
        self.show_image(self.cur()["img"])
        self.render()

    def select_image(self, n):
        self.show_image(n)
        self.render()

    def on_click(self, event):
        tx = event.x / self.zoom + self.view_x0
        ty = event.y / self.zoom + self.view_y0
        self.cur()["new"] = (round(tx + self.tex_offset[0], 1), round(ty + self.tex_offset[1], 1))
        self.cur()["img"] = self.img_index
        self.render()

    def nudge(self, dx, dy, event):
        step = 5.0 if (event.state & 0x1) else 1.0
        x, y = self.value(self.cur())
        self.cur()["new"] = (round(x + dx * step, 1), round(y + dy * step, 1))
        self.render()

    def toggle(self, attr):
        setattr(self, attr, not getattr(self, attr))
        self.render()

    def reset(self):
        for e in self.entries:
            e["new"] = None
        self.render()

    def on_wheel(self, event):
        self.zoom = max(1.0, min(8.0, self.zoom * (1.2 if event.delta > 0 else 1 / 1.2)))
        self.render()

    def save(self):
        text = self.text
        edits = [(e["span"], e["new"]) for e in self.entries if e["new"] is not None]
        edits.sort(key=lambda x: x[0][0], reverse=True)
        for span, pos in edits:
            body = text[span[0]:span[1]]
            body = re.sub(r"offset = Vector2\([^)]*\)",
                          "offset = Vector2(%g, %g)" % (pos[0], pos[1]), body, count=1)
            text = text[:span[0]] + body + text[span[1]:]
        self.tres.write_text(text, encoding="utf-8")
        for e in self.entries:
            if e["new"] is not None:
                e["pos"] = e["new"]
                e["new"] = None
        self.render(saved=True)

    # ---------------------------------------------------------------- 绘制
    def render(self, saved=False):
        if not self.entries or not self.images:
            self.canvas.delete("all")
            self.info.config(text="这个部件还没有贴图或接口")
            return

        base = self.image(self.img_index)
        cur = self.cur()
        cx, cy = self.tex_xy(cur)

        # 参照图：另一段的枢轴对准当前十字
        ghost = None
        gx = gy = 0.0
        if self.show_ref and len(self.images) > 1 and cur["uid"] in ("pivot_knee_u", "pivot_knee_l"):
            other = 0 if self.img_index == 1 else 1
            partner = "pivot_knee_u" if other == 0 else "pivot_knee_l"
            pe = next((e for e in self.entries if e["uid"] == partner), None)
            if pe is not None:
                ghost = self.image(other)
                px, py = self.tex_xy(pe)
                gx, gy = cx - px, cy - py

        x0 = min(0.0, gx) - MARGIN
        y0 = min(0.0, gy) - MARGIN
        x1 = max(base.width, gx + (ghost.width if ghost else 0)) + MARGIN
        y1 = max(base.height, gy + (ghost.height if ghost else 0)) + MARGIN
        self.view_x0, self.view_y0 = x0, y0

        w, h = int((x1 - x0) * self.zoom), int((y1 - y0) * self.zoom)
        sheet = Image.new("RGBA", (w, h), (255, 255, 255, 255))
        scaled_base = base.resize((int(base.width * self.zoom), int(base.height * self.zoom)), Image.NEAREST)
        sheet.alpha_composite(scaled_base, (int((0 - x0) * self.zoom), int((0 - y0) * self.zoom)))
        if ghost is not None:
            g = ghost.copy()
            g.putalpha(g.getchannel("A").point(lambda v: int(v * 0.45)))
            g = g.resize((int(g.width * self.zoom), int(g.height * self.zoom)), Image.NEAREST)
            sheet.alpha_composite(g, (int((gx - x0) * self.zoom), int((gy - y0) * self.zoom)))

        self.tk_img = ImageTk.PhotoImage(sheet)
        self.canvas.config(width=w, height=h)
        self.canvas.delete("all")
        self.canvas.create_image(0, 0, anchor="nw", image=self.tk_img)

        if self.show_grid:
            step = max(4, int(self.zoom * 8))
            px = (-x0) * self.zoom
            while px < w:
                self.canvas.create_line(px, 0, px, h, fill="#ffdddd")
                px += step
            py = (-y0) * self.zoom
            while py < h:
                self.canvas.create_line(0, py, w, py, fill="#ddddff")
                py += step

        for i, e in enumerate(self.entries):
            if e["img"] != self.img_index:
                continue
            tx, ty = self.tex_xy(e)
            sx = (tx - x0) * self.zoom
            sy = (ty - y0) * self.zoom
            color = "#00c000" if i == self.index else "#0088ff"
            r = 10
            self.canvas.create_line(sx - r, sy, sx + r, sy, fill=color, width=2)
            self.canvas.create_line(sx, sy - r, sx, sy + r, fill=color, width=2)
            self.canvas.create_oval(sx - 3, sy - 3, sx + 3, sy + 3, outline=color)

        lines = []
        if saved:
            lines.append("✔ 已保存")
        lines += ["当前：%s（图 %d）" % (cur["uid"], cur["img"] + 1),
                  "缩放 %.1fx" % self.zoom, ""]
        for i, e in enumerate(self.entries):
            x, y = self.value(e)
            mark = "▶" if i == self.index else " "
            lines.append("%s %-13s 图%d %6.1f,%6.1f" % (mark, e["uid"], e["img"] + 1, x, y))
        lines += ["", "左键=设定  方向键=微调", "Shift+方向键=5px",
                  "Tab=下一个  1-9=换图", "F=参照 G=网格 滚轮=缩放", "S=保存 R=重置 Q=退出"]
        self.info.config(text="\n".join(lines))


if __name__ == "__main__":
    root = tk.Tk()
    root.title("接口标定 · 开发者工具")
    Editor(root, sys.argv[1] if len(sys.argv) > 1 else "")
    root.mainloop()
