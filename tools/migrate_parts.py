import re, pathlib

CELL = 32.0
root = pathlib.Path(r"D:/the-thing/resources/parts")

def footprint(m):
    a, b = int(m.group(1)), int(m.group(2))
    return f"size = Vector2({a * CELL:g}, {b * CELL:g})"

def cell(m):
    x, y = int(m.group(1)), int(m.group(2))
    return f"offset = Vector2({(x + 0.5) * CELL:g}, {(y + 0.5) * CELL:g})"

for f in root.glob("*.tres"):
    t = f.read_text(encoding="utf-8")
    t = re.sub(r"footprint = Vector2i\((\d+), (\d+)\)", footprint, t)
    t = re.sub(r"cell = Vector2i\((-?\d+), (-?\d+)\)", cell, t)
    f.write_text(t, encoding="utf-8")
    print("updated", f.name)
