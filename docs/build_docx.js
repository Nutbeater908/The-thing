/**
 * 直接生成《The Thing · 设计大纲》Word 文档。
 *
 *     node docs/build_docx.js
 *
 * 内容以本脚本为正本，改完直接重新生成即可。
 */

const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  TableOfContents, HeadingLevel, AlignmentType, BorderStyle, WidthType,
  ShadingType, VerticalAlign, PageNumber, Header, Footer, PageBreak,
  LevelFormat,
} = require("docx");

const OUT = path.join(__dirname, "设计大纲.docx");

// ---------------------------------------------------------------- 视觉常量

const FONT = { ascii: "Arial", hAnsi: "Arial", eastAsia: "Microsoft YaHei", cs: "Arial" };
const MONO = { ascii: "Consolas", hAnsi: "Consolas", eastAsia: "Microsoft YaHei", cs: "Consolas" };

const ACCENT = "8C2F2F";   // 暗红：呼应血腥怪诞的美学基调
const INK = "1C1C1C";
const MUTED = "6E6E6E";
const RULE = "D8D2CA";
const TINT = "F4F1EC";     // 表头 / 代码块底色
const BAND = "FBFAF8";     // 表格斑马纹

const A4_WIDTH = 9360;     // A4 去掉 1 英寸边距后的可用宽度

// ---------------------------------------------------------------- 排版工具

/** 把 **粗体** 标记转成 TextRun 数组 */
function rich(text, base = {}) {
  const parts = String(text).split(/(\*\*[^*]+\*\*)/g).filter((s) => s !== "");
  return parts.map((seg) =>
    seg.startsWith("**") && seg.endsWith("**")
      ? new TextRun({ text: seg.slice(2, -2), bold: true, ...base })
      : new TextRun({ text: seg, ...base })
  );
}

/** 正文段落 */
function p(text, opts = {}) {
  return new Paragraph({
    children: rich(text),
    spacing: { after: 140, line: 340, ...(opts.spacing || {}) },
    ...opts.paragraph,
  });
}

/** 无文字的间隔段 */
function gap(after = 120) {
  return new Paragraph({ children: [], spacing: { after } });
}

/** 项目符号列表项 */
function bullet(text) {
  return new Paragraph({
    numbering: { reference: "bullets", level: 0 },
    children: rich(text),
    spacing: { after: 60, line: 320 },
  });
}

/** 有序列表项 */
function numItem(ref, text) {
  return new Paragraph({
    numbering: { reference: ref, level: 0 },
    children: rich(text),
    spacing: { after: 60, line: 320 },
  });
}

/** 等宽代码块（逐行加底色，形成整块效果） */
function code(lines) {
  return lines.map((line) =>
    new Paragraph({
      children: [new TextRun({ text: line === "" ? " " : line, font: MONO, size: 18, color: "33302C" })],
      shading: { fill: TINT, type: ShadingType.CLEAR },
      spacing: { before: 0, after: 0, line: 260 },
      indent: { left: 200, right: 200 },
    })
  );
}

/** 单元格内容：\n 拆成多个段落（docx 里不能靠换行符断行） */
function cellLines(text, base = { size: 19 }) {
  return String(text).split("\n").map(
    (line) =>
      new Paragraph({
        children: rich(line, base),
        spacing: { before: 40, after: 40, line: 290 },
      })
  );
}

/** 表格：表头 + 斑马纹 */
function table(headers, rows, widths) {
  const border = { style: BorderStyle.SINGLE, size: 1, color: RULE };
  const cellBorders = { top: border, bottom: border, left: border, right: border };

  const head = new TableRow({
    tableHeader: true,
    children: headers.map((text, i) =>
      new TableCell({
        borders: cellBorders,
        width: { size: widths[i], type: WidthType.DXA },
        shading: { fill: TINT, type: ShadingType.CLEAR },
        verticalAlign: VerticalAlign.CENTER,
        children: [
          new Paragraph({
            children: rich("**" + text + "**", { color: ACCENT, size: 19 }),
            spacing: { before: 40, after: 40, line: 280 },
          }),
        ],
      })
    ),
  });

  const body = rows.map((cells, r) =>
    new TableRow({
      children: cells.map((text, i) => {
        const opts = {
          borders: cellBorders,
          width: { size: widths[i], type: WidthType.DXA },
          children: cellLines(text),
        };
        if (r % 2 === 1) opts.shading = { fill: BAND, type: ShadingType.CLEAR };
        return new TableCell(opts);
      }),
    })
  );

  return new Table({
    columnWidths: widths,
    margins: { top: 80, bottom: 80, left: 140, right: 140 },
    rows: [head, ...body],
  });
}

function h1(text) {
  return new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(text)] });
}

function h2(text) {
  return new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(text)] });
}

function pageBreak() {
  return new Paragraph({ children: [new PageBreak()] });
}

// ---------------------------------------------------------------- 文档内容

const cover = [
  gap(2200),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "The Thing", font: FONT, size: 72, bold: true, color: INK })],
    spacing: { after: 160 },
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "生物建造肉鸽 · 设计大纲", font: FONT, size: 30, color: ACCENT })],
    spacing: { after: 900 },
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "版本 0.1 · 概念验证阶段", font: FONT, size: 21, color: MUTED })],
    spacing: { after: 80 },
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "2026-10-13", font: FONT, size: 21, color: MUTED })],
  }),
  pageBreak(),
];

const toc = [
  // TableOfContents 只写入域代码，不会生成可见标题，得自己加一个
  new Paragraph({
    children: [new TextRun({ text: "目录", font: FONT, size: 30, bold: true, color: ACCENT })],
    spacing: { before: 0, after: 240 },
  }),
  new TableOfContents("目录", { hyperlink: true, headingStyleRange: "1-2" }),
  pageBreak(),
];

const body = [
  // -------- 一
  h1("一、一句话概念"),
  p("你是一只会寄生的大脑寄生虫。在安全区把捡来的器官拼装成一具宿主生物，操控它闯进关卡；"),
  p("宿主会死，但你会活下来——换一具身体，继续。"),

  // -------- 二
  h1("二、核心体验"),
  table(
    ["支柱", "说明"],
    [
      ["搭积木式造物", "不限人形。躯干、器官、肢体任意组合，唯一的约束是「它能活」"],
      ["拟真生物逻辑", "神经控制、血液供给、骨骼支撑，三条链路决定生死"],
      ["肉鸽循环", "死亡不是终点。寄生虫逃回巢穴，换具身体再战"],
    ],
    [2400, 6960]
  ),
  gap(140),
  p("**参考坐标**：《死亡细胞》的节奏与元进度 × 《坎巴拉太空计划》的组装快感"),

  // -------- 三
  h1("三、美学基调"),
  p("血腥怪诞。器官是明晃晃的肉块，接口是裸露的血管和神经束。"),
  p("不追求恐怖，追求**缝合怪的荒诞感**——它歪歪扭扭，但它站起来了。"),

  // -------- 四
  h1("四、核心循环"),
  ...code([
    "   ┌──────────────────────────────────────────┐",
    "   │                                          │",
    "   ▼                                          │",
    "孵化池 ──▶ 拼装 ──▶ 进入区域 ──▶ 房间×N ──▶ Boss",
    "（安全区）  器官     （俯视2D）   战斗/事件/拾取    │",
    "            校验                        │         │",
    "            存活                        │         │",
    "                                        ▼         │",
    "                                  宿主死亡/逃脱 ──┘",
  ]),
  gap(160),
  bullet("**孵化池**：寄生虫的老巢，也是尸体库。每次 run 从这里开拼"),
  bullet("**拼装**：只在安全区进行，回合制、无时间压力"),
  bullet("**区域**：线性推进，每房间有敌人 / 事件 / 器官掉落"),
  bullet("**死亡**：宿主死亡 ≠ 游戏结束"),

  // -------- 五
  h1("五、拼装系统（核心玩法）"),

  h2("5.1 空间模型"),
  bullet("**2D 网格 7 × 5**，俯视单层平面"),
  bullet("格子尺寸随窗口自适应（34–84 px），盘面始终完整可见"),
  bullet("**预留 3D 扩展余地**：方向枚举含「前 / 后」，格子坐标将来可加 layer 维度；校验逻辑按「允许方向集」遍历，放开方向即升级为立体，不用重写核心"),

  h2("5.2 接口系统"),
  p("三类接口，用**位掩码**表示，同一方向可叠加多种："),
  table(
    ["接口", "颜色", "作用"],
    [
      ["⚡ 神经", "青", "传递控制信号"],
      ["🩸 血流", "红", "供给能量"],
      ["🦴 骨骼", "白", "物理支撑"],
    ],
    [2200, 1600, 5560]
  ),
  gap(140),
  p("方向按「**上、右、下、左**」顺时针索引（0..3）。"),

  h2("5.3 旋转"),
  p("器官只定义 **0° 一套接口**，可 **90° 增量旋转**，旋转时接口循环移位："),
  ...code(["joint_at(方向 d, 旋转 rot) = joints[(d - rot + 4) % 4]"]),
  gap(140),
  p("好处：定义简单；摆位自由——腿的接口定义在「上」，转 90° 就能挂到躯干侧面。"),

  h2("5.4 操作"),
  table(
    ["输入", "行为"],
    [
      ["左键", "在空格放置当前选中的器官"],
      ["右键", "旋转该格器官 90°"],
      ["中键", "移除该格器官"],
    ],
    [2200, 7160]
  ),

  // -------- 六
  h1("六、存活校验（三条链）"),
  p("拼装完成时自动校验，**三条全过才「可存活」**："),
  table(
    ["校验", "路径", "失败提示"],
    [
      ["⚡ 控制链", "寄生虫 → 大脑 → 所有受控器官（沿神经扩散）", "有 N 个器官失去控制"],
      ["🩸 血路", "心脏 → 所有耗血器官（沿血流扩散）", "有 N 个器官缺血"],
      ["🦴 结构", "全部器官连成一体（任意接口都算物理连接）", "有 N 个器官孤立"],
    ],
    [1800, 4900, 2660]
  ),
  gap(140),
  p("校验通过后「出发」按钮才可用。"),

  // -------- 七
  h1("七、器官表（6 种基础）"),
  p("接口记法：按「上 / 右 / 下 / 左」，⚡神经　🩸血流　🦴骨骼"),
  table(
    ["器官", "接口", "特性"],
    [
      ["寄生虫", "下：⚡", "你的本体。控制核心，可主动脱离"],
      ["大脑", "上：⚡\n右：⚡🩸\n下：⚡🩸🦴\n左：⚡🩸", "控制中枢 + 循环枢纽"],
      ["心脏", "上：🩸　下：🩸", "血源。自律搏动，不需要神经"],
      ["腿", "上：⚡🩸🦴", "移动。需神经控制 + 血流供给"],
      ["爪", "上：⚡🩸🦴", "攻击。血供越足伤害越高"],
      ["脂肪", "上：🩸　右：🦴\n下：🩸　左：🦴", "储能。不需神经"],
    ],
    [1500, 3400, 4460]
  ),
  gap(160),

  h2("最小可活生物"),
  ...code([
    "   [寄生虫]",
    "       ↓ ⚡",
    "   [ 大 脑 ]",
    "       ↓ 🩸",
    "   [ 心 脏 ]",
  ]),
  gap(140),
  p("寄生虫 + 大脑 + 心脏 = 能动能活的最小配置。"),

  h2("设计注记"),
  p("大脑左右两侧**必须带血流**（⚡🩸）：早期版本只有神经，导致挂在大脑侧面的腿全部缺血——这是接口表的设计漏洞，已修正。"),

  // -------- 八
  h1("八、寄生虫与死亡"),
  bullet("寄生虫**必须连上大脑**才能操控宿主"),
  bullet("宿主濒死时可主动**脱离**，变成独立的慢速单位"),
  bullet("脱离后可以：逃回孵化池（结束本轮）／ 寄生尸体（临时控制）"),
  bullet("**死亡代价分档**：逃脱成功 → 带回大部分收获；寄生虫也死 → 损失更多"),

  // -------- 九
  h1("九、肉鸽结构"),
  h2("一次 run"),
  p("孵化池 → 区域（N 房间）→ Boss → 深入下一层 / 死 / 逃"),
  h2("死亡后保留"),
  table(
    ["类别", "保留", "说明"],
    [
      ["器官图纸", "✅ 永久", "解锁新器官种类，肉鸽核心驱动"],
      ["寄生虫进化", "✅ 永久", "神经接口数、逃脱速度、脑容量"],
      ["器官库存", "部分", "按逃脱成功与否带回"],
      ["宿主躯体", "❌ 清空", "每次 run 重新拼装"],
    ],
    [1900, 1500, 5960]
  ),

  // -------- 十
  h1("十、待定项"),
  table(
    ["议题", "选项"],
    [
      ["战斗操作", "动作操作（移动+攻击+闪避）／ 简化操作（自动攻击，玩家只管走位）"],
      ["尸体来源", "无限基础款（随便拿）／ 有限独特款（稀缺资源）"],
      ["数值模型", "血流量分配、能量消耗的具体公式"],
      ["氧气系统", "暂合并进血流量，将来独立成「鳃 / 肺」器官"],
      ["视角", "俯视 2D（已倾向，可复用 Dungeon Scavenger 的地图经验）"],
    ],
    [1900, 7460]
  ),

  // -------- 十一
  h1("十一、技术架构"),

  h2("分层原则"),
  bullet("**拼装界面用 Control，战斗表现用 Node2D，两者共享同一份器官数据** —— 拼装逻辑与战斗表现解耦，改哪边都不影响另一边"),
  bullet("**界面 / 交互优先用引擎自带能力**：.tscn 搭节点树、Theme 资源做样式、ButtonGroup 管选中；只有算法和必要逻辑才写脚本"),

  h2("目录结构"),
  ...code([
    "res://",
    "├── data/organs/         器官数据（规划迁到 .tres，便于做图纸解锁）",
    "├── resources/ui/        主题与样式（main_theme.tres）",
    "├── scenes/build/        拼装界面（build_screen.tscn / organ_tile.tscn）",
    "├── scripts/data/        数据类（organ_data.gd / organ_library.gd）",
    "├── scripts/build/       拼装逻辑（assembly_grid.gd 等）",
    "└── tests/               回归测试（assembly_check.gd）",
  ]),
  gap(160),

  h2("已实现（原型 v0.1）"),
  bullet("OrganData：接口位掩码 + 旋转位移 + 方向工具函数"),
  bullet("OrganLibrary：6 种器官定义"),
  bullet("AssemblyGrid：自适应格子、放置 / 旋转 / 移除、三条链校验"),
  bullet("BuildScreen：完整拼装界面（引擎原生场景树 + 主题）"),
  bullet("assembly_check.gd：8 个用例的回归测试，全部通过"),

  h2("下一步"),
  ...[
    "把拼好的生物**导出成数据**，接一个简单的移动 / 战斗场景，跑通「拼装 → 行动」闭环",
    "器官数据迁到 .tres 资源，支撑「图纸解锁」的元进度",
    "血流量 / 能量的数值模型，让器官数量与体型产生取舍",
  ].map((t) => numItem("steps", t)),
];

// ---------------------------------------------------------------- 组装

const doc = new Document({
  styles: {
    default: {
      document: { run: { font: FONT, size: 21, color: INK } },
    },
    paragraphStyles: [
      {
        id: "Title", name: "Title", basedOn: "Normal",
        run: { size: 72, bold: true, color: INK, font: FONT },
        paragraph: { spacing: { before: 0, after: 160 }, alignment: AlignmentType.CENTER },
      },
      {
        id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 30, bold: true, color: ACCENT, font: FONT },
        paragraph: { spacing: { before: 400, after: 180 }, outlineLevel: 0 },
      },
      {
        id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 24, bold: true, color: INK, font: FONT },
        paragraph: { spacing: { before: 280, after: 140 }, outlineLevel: 1 },
      },
    ],
  },
  numbering: {
    config: [
      {
        reference: "bullets",
        levels: [
          {
            level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
            style: { paragraph: { indent: { left: 400, hanging: 240 } } },
          },
        ],
      },
      {
        reference: "steps",
        levels: [
          {
            level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
            style: { paragraph: { indent: { left: 400, hanging: 240 } } },
          },
        ],
      },
    ],
  },
  sections: [
    {
      properties: {
        titlePage: true, // 封面页不显示页眉页脚
        page: {
          margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
          size: { width: 11906, height: 16838 }, // A4
          pageNumbers: { start: 1 },
        },
      },
      headers: {
        first: new Header({ children: [] }),
        default: new Header({
          children: [
            new Paragraph({
              alignment: AlignmentType.RIGHT,
              children: [new TextRun({ text: "The Thing · 设计大纲", color: MUTED, size: 18, font: FONT })],
              border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: RULE, space: 6 } },
            }),
          ],
        }),
      },
      footers: {
        first: new Footer({ children: [] }),
        default: new Footer({
          children: [
            new Paragraph({
              alignment: AlignmentType.CENTER,
              children: [
                new TextRun({ text: "— ", color: MUTED, size: 18, font: FONT }),
                new TextRun({ children: [PageNumber.CURRENT], color: MUTED, size: 18, font: FONT }),
                new TextRun({ text: " —", color: MUTED, size: 18, font: FONT }),
              ],
            }),
          ],
        }),
      },
      children: [...cover, ...toc, ...body],
    },
  ],
});

Packer.toBuffer(doc).then((buffer) => {
  fs.writeFileSync(OUT, buffer);
  console.log("已生成:", OUT);
});
