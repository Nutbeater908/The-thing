import re
from pathlib import Path
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

SRC = Path(r"D:/the-thing/docs/策划案.md")
DST = Path(r"D:/the-thing/docs/策划案.docx")

def set_cjk(doc):
    style = doc.styles["Normal"]
    style.font.name = "Microsoft YaHei"
    style.font.size = Pt(10.5)
    rpr = style.element.get_or_add_rPr()
    rfonts = rpr.find("{http://schemas.openxmlformats.org/wordprocessingml/2006/main}rFonts")
    if rfonts is None:
        from docx.oxml.ns import qn
        rfonts = rpr.makeelement(qn("w:rFonts"), {})
        rpr.append(rfonts)
    from docx.oxml.ns import qn
    rfonts.set(qn("w:eastAsia"), "Microsoft YaHei")

def add_table(doc, rows):
    cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
    if len(cells) >= 2 and re.fullmatch(r"[\s:\-|]+", rows[1]):
        cells.pop(1)
    if not cells:
        return
    width = max(len(r) for r in cells)
    table = doc.add_table(rows=0, cols=width)
    table.style = "Light Grid Accent 1"
    for row in cells:
        cells_out = table.add_row().cells
        for i, text in enumerate(row[:width]):
            cells_out[i].text = re.sub(r"[*`]", "", text)
    doc.add_paragraph()

doc = Document()
set_cjk(doc)
doc.add_heading("机器人组装肉鸽 · 策划案", level=0)

lines = SRC.read_text(encoding="utf-8").splitlines()
i = 0
while i < len(lines):
    line = lines[i].rstrip()
    if line.startswith("|") and i + 1 < len(lines) and lines[i + 1].lstrip().startswith("|"):
        block = []
        while i < len(lines) and lines[i].lstrip().startswith("|"):
            block.append(lines[i])
            i += 1
        add_table(doc, block)
        continue
    if line.startswith("#"):
        text = line.lstrip("#").strip()
        if text:
            doc.add_heading(text, level=min(line.count("#"), 4))
    elif line.strip() == "---":
        doc.add_paragraph()
    elif line.strip().startswith(">"):
        p = doc.add_paragraph(line.strip().lstrip(">").strip())
        p.runs[0].italic = True
    elif line.strip():
        doc.add_paragraph(re.sub(r"[*`]", "", line.strip()))
    i += 1

doc.save(DST)
print("saved", DST, DST.stat().st_size, "bytes")
