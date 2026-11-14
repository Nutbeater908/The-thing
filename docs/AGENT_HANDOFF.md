# The Thing — Agent 交接

> 首版交接：2026-11-10。本次更新：2026-11-11（第二轮会话结束时实测）。
> 本文供接管同一台 Windows 电脑、同一个项目的 Agent 使用。
> 首要目标：接续已验收的可玩切片，**不要重新研究通用刚体腿或四腿坡道**。
> 本轮已实施：真实拼装能力接入切片、文件归位、实验场入口、本文档更新。**未提交、未推送。**

## 0. 接手先读

1. 工作目录是 **`D:/the-thing`**，不是旧对话的 `D:/chromedownload/GIT/Git/work`。
2. 本地文件比 GitHub 新得多。**禁止用 reset/clean/checkout 覆盖工作区，不要重新 clone 到现有目录。**
3. 短关卡切片（`playable_slice.tscn`）用户已试玩验收，并且**本轮已改成读取真实拼装**，不再用固定演示能力。
4. 用户认可放弃“肢体真实承重、任意拓扑靠物理站稳”。保留原生 CharacterBody2D 的流畅操作，不返回无限调刚体/IK 的路线。
5. 四腿真实身体坡道实验**仍失败**；不能因为有测试文件就说它已通过。
6. Godot MCP 已接通，目标 `D:/the-thing`。不要自行降级、回滚或重装插件。
7. 未提交改动里混着整包插件升级，**不要无脑 `git add -A`**。

## 1. 环境与路径

| 项目 | 当前信息 |
|---|---|
| 本地目录 | `D:/the-thing` |
| Godot | 4.7.1 stable，GL Compatibility |
| 控制台可执行文件 | `D:/Godot/Godot_v4.7.1-stable_win64_console.exe` |
| 编辑器可执行文件 | `D:/Godot/Godot_v4.7.1-stable_win64.exe` |
| 主场景 | `res://scenes/build/build_screen.tscn` |
| 可玩切片 | `res://scenes/arena/playable_slice.tscn` |
| 实验场 | `res://scenes/labs/lab_host.tscn` |
| 设计讨论稿 | `docs/游戏设计讨论稿.md` |
| 历史设计稿 | `docs/设计大纲.md`、`docs/设计大纲.docx`（过时，勿作当前规格） |
| Git 远端 | `https://github.com/Nutbeater908/The-thing.git` |
| 分支 / 最近提交 | `main` / `4f2df06` |

项目无 `AGENTS.md`。

### 用户数据（重要）

```text
%APPDATA%/Godot/app_userdata/The Thing/session.save
%APPDATA%/Godot/app_userdata/The Thing/presets.save
```

- 不读取、重写或重置它们来准备测试；确需覆盖先备份并征得用户同意。
- `.godot/` 是导入缓存，已被 Git 忽略；`.gd.uid`、`.import` 侧车文件不要批量删除。

## 2. 协作要求

- 简体中文交流；用户自称“人”，旧助手叫“虾”，新代理不必冒充。
- **用户懂一点技术但深层不懂**：先讲“这在游戏里是什么、玩家会感觉到什么”，再讲代码；少抽象名词，可用行业术语（动作模组、能力包络、数据表驱动）。
- **不要迎合**：有不同意见直接说，包括反对用户的方案；发现问题就点出来。
- 输出简洁、分阶段。开始前说明本轮范围、预期产物、停止点。
- 用户单发 `q` 或单个英文字母通常表示继续/确认。
- 引擎原生优先：固定节点用 `.tscn`，布局用容器，样式用 Theme；脚本承担业务与算法。
- 数值数据驱动，优先 Resource / `.tres`。
- 新美术必须先预览、用户确认。当前继续占位素材。
- **不使用鼠标/键盘注入替用户试玩**。测试可调方法、发信号，但不操控桌面。
- 场景操作有 MCP 就优先用 MCP；不能把“日志没报错”说成“亲眼看过画面”。
- 用户重视速度与完成度，避免无边界研究、长清单、过度架构。
- 不自动上传、提交或推送。
- 一处用户明确要求：**“横腿不能行走”是自然结果，不要在 HUD 里专门提示**。

## 3. 已确认的游戏设计（摘要）

详见 `docs/游戏设计讨论稿.md`。

- 脑寄生虫拼装宿主，横版 2D；拼装应真实改变能力与战斗。
- **不要求肢体真实承重或身体物理自行站稳**，稳定横版控制优先。
- 腿的组合先决定动作模组，再影响速度、跳跃、稳定性。
- 可自由转向；位置影响操作，但前后没有绝对优劣。
- 推进结构：初始拼装 → 关卡 → 沿途休息处完整拼装 → 下一关。
- 途中安全区允许受限简易拼装，首要目的是“新器官马上试”。
- 血压/氧含量、损伤/断肢、修复规则、简易拼装边界**均未定稿，不要自动实现**。
- 先用现有空间/接口/供血限制，发现“器官越多永远越好”再补规则。

## 4. 当前成果

### 4.1 拼装与旧玩法原型（可运行）

9×7 拼装盘、异形器官、旋转、神经/血流/骨骼三链校验、器官 HP、经济/修复、胃、方案/存档、旧敌人与尸体搜刮、多关卡链路。

```text
scripts/data/organ_data.gd          器官 Resource（身份/格形/接点/HP/质量/费用）
scripts/data/organ_port.gd          独立接点 Resource，不能改回内部类
scripts/data/organ_library.gd       扫描 resources/organs 加载定义
resources/organs/*.tres             parasite / brain / heart / leg / claw / fat
scripts/build/assembly_grid.gd      放置、拉线、校验、购买/修复
scripts/build/organ_tile.gd         器官格显示
scripts/build/build_screen.gd       孵化池 UI 接线与三个入口
scripts/backpack/backpack_panel.gd  3×3 异形胃
scripts/run/run_state.gd            自动加载，存档/方案
scripts/arena/arena.gd              旧正式关卡（别和新切片混淆）
scripts/arena/creature_body.gd      旧刚体玩家
scripts/arena/enemy.gd              复用敌人/尸体
scripts/arena/loot_window.gd        旧搜刮界面
```

### 4.2 原生角色底座（已测试，用户认可）

**本轮已从 `scripts/labs/` 移到 `scripts/character/`，因为它已是生产代码**（`slice_player.gd` 直接继承它）。

```text
scripts/character/character_terrain_walker.gd
scripts/character/character_terrain_tuning.gd
scripts/labs/character_terrain_lab.gd        实验台，仍留在 labs
scenes/labs/character_terrain_lab.tscn
tests/character_terrain_check.gd
```

- `CharacterBody2D` + 原生 `move_and_slide`、floor snap、floor constant speed。
- API：`set_walk_intent(value)`、`request_jump() -> bool`、`add_knockback(delta_velocity)`。
- 胶囊 36×100，中心相对脚底原点 `(0,-50)`；layer 512 / mask 256；snap 8；坡度 30°；safe_margin 0.2。
- 向上跳跃/击退抑制 snap；细小或抵消的向上击退不会卡死 snap 状态。
- 外部击退单独衰减，不被持续方向输入抹掉；撞墙清除被阻挡分量。
- 注意：`tuning` 是**每帧实时读取**的，所以运行中替换 tuning 资源会立刻生效。

### 4.3 短关卡切片（已验收，且已接入真实拼装）

```text
scenes/arena/playable_slice.tscn
scripts/arena/playable_slice.gd
scripts/arena/slice_player.gd
scripts/arena/slice_tuning.gd
scripts/arena/slice_body_profile.gd      本轮新增：能力快照
scripts/arena/slice_capability_table.gd  本轮新增：数值表类型
resources/arena/slice_capabilities.tres  本轮新增：数值表数据
tests/playable_slice_check.gd
```

流程：出生 → 缓坡 → 跳过矮障碍 → 两小怪 + 一精英 → 搜刮器官 → 绿色出口；失败可重试。
操作：A/D 或方向键移动，空格跳跃，J 面朝方向攻击，E 搜刮附近高亮尸体，Tab 局内胃。

**演示收益仍不带入真实存档**；回池会恢复同一个孵化池实例。

### 4.4 实验场（本轮新增）

```text
scenes/labs/lab_host.tscn
scripts/labs/lab_host.gd
```

主场景顶部工具行（和「物理预览」「全部修复」同排）的 **「实验场 · 运动成果」** 按钮进入。
宿主用与切片相同的挂起机制持有孵化池实例，Esc 或按钮返回**同一个实例**，不写存档、不读拼装。

收录 9 个实验（全部自带相机）：

```text
character_terrain_lab.tscn              原生底座：坡面 / 跳跃 / 击退
single_leg_lab.tscn                     独腿 HOP · 程序化
procedural_walk_lab.tscn                双腿交替 · 程序化
multi_leg_lab.tscn                      多腿波浪 · 程序化
terrain_walk_lab.tscn                   双腿坡面 · 程序化
terrain_smooth_lab.tscn                 双腿连续坡面 · 程序化
blueprint_walk_lab.tscn                 双腿坡面 · 蓝图 IK
terrain_smooth_blueprint_biped.tscn     双腿连续坡面 · 蓝图 IK
terrain_smooth_blueprint_quad.tscn      四腿坡道 · 蓝图 IK（已知失败）
```

最后一项是已知失败的四腿坡道，标签里写明了；留在实验场是为了能直接对比失败现象，不代表它已通过。

**踩过的坑**：`terrain_smooth_lab` / `terrain_smooth_blueprint_*` 是**继承场景**，它们的 Camera2D 和 Walker 来自 `terrain_walk_lab.tscn`，在派生 `.tscn` 文件里根本不会出现。**判断场景有没有某个节点，不能只 grep 场景文本**，要 `load().instantiate()` 后 `find_child()`。

### 4.5 运动测试房（旧，仍可用）

`build_screen._on_motion_test()` → `scripts/build/motion_test_bridge.gd`（纯预检）→ `scenes/build/motion_test_room.tscn`。
用**当前真实拼装**跑 `blueprint_walker`（IK 腿），但限制很硬：腿必须朝下、旋转 0、无爪、1–6 条、两髋间距 ≥4 格、下方不能有固定器官等。它只验运动，没有战斗和关卡。

## 5. 本轮实现：拼装 → 能力（数据流）

```
孵化池 AssemblyGrid
  → result()["alive"]                三链校验，不过就拒绝进关
  → CreatureStats.from_grid(grid)     质量 / 支撑腿 / 爪
  → SliceBodyProfile.from_grid(grid)  按数值表算出一组能力
  → playable_slice.enter_from(build, body)
  → slice_player.apply_profile(body)  复制 tuning 再灌值
```

**数值表**（`resources/arena/slice_capabilities.tres`，调平衡只改这里）：

| 输入 | 规则 |
|---|---|
| 支撑腿 0 条 | 拒绝进关：“身体没有朝下的支撑腿，横版里无法行走” |
| 支撑腿 1 / 2 / 3 / 4+ | 移速 95 / 150 / 170 / 182，加速度 520 / 650 / 700 / 730，跳跃 300 / 350 / 378 / 392 |
| 模组名（只用于 HUD） | 独腿踮行 / 双腿行走 / 多腿行走 |
| 爪 0 / 1 / 2 / 3+ | 伤害 4 / 12 / 18 / 22，距离 90 / 135 / 160 / 175，冷却 0.5 / 0.35 / 0.30 / 0.27 |
| 质量 | 血量 = 80 + (质量 − 10) × 5，夹在 45–190 |

实现要点，改之前先看：

- `apply_profile()` **必须先 `tuning.duplicate()` 再改**：场景里的 `Tuning` 是共享子资源，就地写会污染所有实例。
- 注入在 `playable_slice._ready()` 里做，此时子节点 `slice_player._ready()` 已经跑过（`hp = max_hp` 用的是旧值），所以 `apply_profile()` 里会**重新算一次 hp**。
- `retry()` 重建场景时把 `profile` 传给新实例，**不重新读拼装**（这是“进入时的能力快照”）。
- HUD 的 `HUD/Margin/Box/Body` 一行常驻显示实际生效能力，并注明碰撞/运动包络仍是固定胶囊。
- 未存活拼装、0 支撑腿都会拒绝并说明原因，**不偷偷替换身体或补器官**。

**已知副作用（不是 bug，是这版粗表的结果）**：多腿是纯赚——4 条腿 = 移速 182 + 血量 110，没有代价。目前只有供血链拦着（心脏 10，腿 2/条，脑 1，爪 3，所以 4 腿 + 脑 = 9 刚好卡住）。要变成取舍，改表里数组即可，但**这是平衡决定，没做**。

## 6. 暂停的运动实验：不要继续追

```text
scripts/labs/articulated_biped.gd   旧 RigidBody 骨段 + PinJoint2D + PD 扭矩
scripts/labs/two_leg_lab.gd         旧两腿实验
scripts/labs/lab_contact_body.gd
scripts/labs/procedural_walker.gd   单刚体托举 + 程序化腿
scripts/labs/leg_kinematics.gd      共享两骨 IK
scripts/labs/leg_rig.gd             N 腿几何 Resource
scripts/labs/terrain_walker.gd      连续地形目标（继承 procedural_walker）
scripts/labs/blueprint_walker.gd    几何/质量适配（现在继承 terrain_walker）
scripts/labs/blueprint_walk_spec.gd 蓝图编译
```

- 独腿 HOP、双腿交替、四腿平地实验曾通过；入口接受 1–6 条 ≠ 3/5/6 腿全数已测。
- 多腿波浪步态有序落脚、单腿摆动、72px/s 上限，曾修全速闪腿。
- **`terrain_smooth_blueprint_quad.tscn` / `tests/terrain_smooth_blueprint_check.gd` 真实四腿坡道未通过**（本次实测 failures=9）：停顿、扫掠擦碰、支撑异常、脚位跳变。
- `terrain_gentle.tscn` 已被早期实验改成圆弧过渡；不能说原始尖角地形已适配。
- `terrain_follow_quad.tres` 的 92 高度、缩小腿查询间隙属于未完成实验，不是成品方案。
- 保留文件供参考，**不要为绿测试改地形或删断言**。

## 7. 文件地图（本轮归位后）

**生产代码**

```text
scripts/character/    运动底座（切片在用）
scripts/arena/        旧关卡 + 可玩切片 + 切片能力层
scripts/build/        孵化池、拼装盘、运动测试桥/房
scripts/backpack/     胃
scripts/data/         器官/敌人/调参 Resource 与统计
scripts/run/          RunState 自动加载
resources/organs/     6 种器官定义
resources/enemies/    grunt / elite
resources/tuning/     creature.tres（旧俯视）、economy.tres
resources/arena/      slice_capabilities.tres（切片数值表）
```

**实验（主场景只能经实验场或运动测试房间接看）**

```text
scripts/labs/         19 个脚本
scenes/labs/          15 个场景（含 lab_host）
resources/labs/       12 份实验调参
tests/                23 个测试
```

**本轮删除**：`scenes/labs/leg_hitboxes.tscn`（全项目零引用）。

**注意**：`scripts/labs/character_terrain_lab.gd` 的 Reset 已从 `reload_current_scene()` 改成回出生点，因为嵌在实验场宿主里重载会把宿主一起冲掉。

## 8. 待办与已知问题

1. **IK 腿接进关卡（未做）**。用户已同意“先归位 → 再实验场 → 最后才考虑换移动底座”。不要主动做，需用户明确要求。风险：会把四腿坡道等未解决物理问题引进已验收闭环。
2. **`tests/hatchery_motion_check.gd` 断言过期**：第 133 行要求 `blueprint_walker.gd` 的直接基类是 `procedural_walker.gd`，但它现在继承 `terrain_walker.gd`（后者再继承 `procedural_walker.gd`）。这是别人改继承后没同步测试，**不是回归**。要么改断言为“继承链包含 procedural_walker”，要么回退继承——**需要用户决定，不要为了绿测试直接改**。
3. **四腿坡道**：已知失败，暂停。
4. **多腿纯赚**：见 §5 末尾，属平衡问题。
5. **存档/方案 .tres 的假 diff**：`resources/organs/*.tres`（5 个）和 `resources/labs/{procedural_walk,single_leg_walk,multi_leg_walk}.tres` 被 Godot 重写过（加 uid、抹掉等于默认值的字段、调属性顺序），这 8 个文件合计 **−230 / +35 行**。**语义没变**，但会污染提交 diff。
6. **提交拆分**：插件升级和游戏改动混在一起，见 §10。

## 9. 测试

**本次实测（2026-11-11，隔离副本）**：23 个测试中 20 通过。

| 测试 | 结果 |
|---|---|
| `playable_slice_check` | **PASS** frames=1035，演示期存档写入 0 |
| `character_terrain_check` | **PASS** frames=8018 |
| `blueprint_walk_check` | PASS |
| `hatchery_multi_leg_check` | PASS right≈219 reverse≈218 steps=19 |
| `hatchery_single_leg_check` | PASS right≈268 hops=4 |
| `leg_motion_refactor_check` | PASS cases=1440 |
| `multi_leg_check` | PASS frames=992 |
| `single_leg_check` | PASS frames=990 |
| `terrain_walk_check` | PASS |
| `terrain_smooth_check` | PASS |
| `procedural_walk_check` | PASS |
| `backpack_check` / `creature_stats_check` / `economy_check` / `link_check` / `link_input_check` / `organ_data_check` / `progress_check` / `repair_check` / `validation_check` | 全部 exit 0，输出“全部通过” |
| `terrain_smooth_blueprint_check` | **FAIL failures=9**（四腿坡道，已知，暂停） |
| `hatchery_motion_check` | **FAIL `no new movement implementation`**（过期断言，见 §8.2） |
| `articulated_leg_check` | 已知失败：`fallback_failures=19 native_hard_limit_failures=2`（旧刚体硬限位，暂停） |

### 隔离是硬要求

`project.godot` 含真实 `RunState` autoload，`_ready()` 会读存档。**不要直接在完整项目跑要求空 root 的 SceneTree 测试。**

做法：复制临时副本，排除 `.git/`、`.godot/`、`addons/`；删掉副本 `project.godot` 的 `[autoload]` 和 `[editor_plugins]`（`_mcp_game_helper` 也指向 addons，必须一起删），改独立项目名。原项目不改。

```text
Godot_v4.7.1-stable_win64_console.exe --headless --path <副本> --editor --import
Godot_v4.7.1-stable_win64_console.exe --headless --fixed-fps 60 --path <副本> --script res://tests/<name>.gd
```

- 默认物理频率 60Hz、time_scale 1。`--fixed-fps 60` 只保证确定性，确认 `Engine.physics_ticks_per_second == 60`。
- 先 import 生成全局类缓存，再跑测试；用**真实退出码 + 完整日志**判断，别只看最后一行。
- 静默类测试只打印“全部通过”，没有 PASS 关键字，要看退出码。

## 10. Git

- `main` 最近提交仍是 `4f2df06`；`01021e3` 是初始提交。
- **原生底座、短关卡切片、真实拼装接入、实验场、坡道实验、两份文档都还没进 GitHub。** 只 clone 远端拿不到。
- 非插件改动（本轮统计）：**14 改 / 1 删 / 47 个新文件**。
- 插件改动：**100 改 / 4 删 / 75 新增**（4.4.1 整包升级，删了旧的 `cherry_studio.gd`、`update_reload_runner.gd` 等）。
- 提交时按组拆，至少分：插件升级 / 已验收切片与能力层 / 原生底座与实验场 / 未完成坡道实验 / 文档 / 编辑器重写噪声。

## 11. Godot MCP

- 插件 `addons/godot_ai/`，`plugin.cfg` 版本 **4.4.1**；server 4.4.1。
- 客户端 `deepseek_harness` 已在插件里 `configured`。**认证通过插件自带的客户端配置功能完成，不要读取或打印密钥。**
- 用 `session_manage(op="list")` 确认会话；返回 `The Thing` / `D:/the-thing/` 才算接通。多项目时先 `session_activate`。
- **不要写死 PID 或端口**，重启就变。此前记录过 HTTP 8001 / WebSocket 8002，只能作线索。
- 编辑器开着时不要用 `git` 或脚本批量改编辑器正打开的场景文件。

## 12. 最短接手顺序

1. 读本文与 `docs/游戏设计讨论稿.md`；`git status --short` 看状态，**不清理工作区**。
2. `session_manage(op="list")` 确认 MCP 目标是 `D:/the-thing`。
3. 需要跑测试时按 §9 建隔离副本，先跑 `playable_slice_check` 和 `character_terrain_check` 当基线。
4. 认识四个入口：**出发**（旧 arena）、**运动测试**（真实拼装 + IK 腿，只验运动）、**短关卡切片**（可玩，读真实拼装）、**实验场**（运动实验展示）。
5. 有新的玩法任务再改代码；**不要主动重开刚体腿/四腿坡道**。

**当前不需要做：**新的剧情章节、血压/氧气系统、完整关卡生成、多腿坡道、沿途休息站、存档格式改造、插件降级、Git 发布、新美术。
