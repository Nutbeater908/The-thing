# The Thing 器官像素素材生成——转交说明

## 0. 接手窗口先读这里

目标：为 The Thing 制作血腥怪诞风格的器官像素 sprite。已跑通「Cherry 内置生图 → 硅基流动 Qwen-Image → 本地去背景 → 原生像素网格重采样 → 用户预览」链路。

- 历史成功验证：2026-10-18，用户认可 50×50 心脏版本；否定强制压成 32×32 的模糊版本。
- 本说明整理于 2026-11-12。历史成功不代表当前余额、模型配置、登录状态仍然有效，按实际返回判断。
- 这次交接只记录操作，不新增生图、不扣费、不修改游戏场景。
- 新美术先展示预览并取得用户确认，再接入 Godot；进入接入阶段前说明范围、产物、停止点并等确认。
- 项目路径：`D:/the-thing`。操作前读 `AGENTS.md`；当前游戏状态以实际项目及 `docs/AGENT_HANDOFF.md` 为准，不能按旧记录恢复旧场景结构。
- 本文不含 API Key、密码、登录令牌。不要搜索应用数据库、凭证目录或打印密钥来补齐配置。

## 1. 首选：Cherry Studio 内置生图工具

### 配置链路

```text
Agent 调用 mcp__cherry-tools__generate_image
    → Cherry 设置中的默认绘画模型
    → SiliconFlow（硅基流动）
    → Qwen/Qwen-Image
    → 返回生成结果及文件标识
```

首次配置或迁移环境：

1. 在 `https://cloud.siliconflow.cn` 注册/登录，确认账户有可用余额，并自行创建 API Key。
2. Cherry Studio → 设置 → 模型服务 → 硅基流动，用户在应用界面填写 Key 并启用服务商。
3. 在该服务商中添加/启用模型 ID：`Qwen/Qwen-Image`。大小写、斜杠必须一致。
4. 设置 → 默认模型 → 绘画模型 → 选择该模型。
5. 智能体 → 内置工具 → 启用「生成图片」。
6. 接手会话检查工具是否实际可用；若界面启用后工具仍未出现，可新开会话再检查。不要假装调用了不可用的工具。

### 最小调用

以下为工具参数，不是直接发给 SiliconFlow 的 HTTP 请求：

```json
{
  "prompt": "Pixel art game sprite for a 2D grid-based body-horror roguelike. A single living heart organ, front view, centered. Chunky visible square pixels, hard edges, strong dark outline. Dark maroon, crimson, raw pink highlights and deep purple veins. Single isolated object on a plain white background with generous empty margins."
}
```

历史工具名：`mcp__cherry-tools__generate_image`，实际执行时使用当前会话暴露的名称与参数 schema。当前工具能接收 `prompt`，以及可选的 `numImages`、`size`、`quality`、`background` 等；下游是否接受以服务商和模型为准。最低限度只传 `prompt`，先生成 1 张。

注意：

- 不必切换聊天模型；聊天模型与绘画模型是独立设置。
- 工具会使用应用保存的 Key，Agent 不需要读取 Key。
- 当前工具 schema 没有参考图输入，不要凭空传 `image_ids`、`images` 或 `mask`。需要参考图编辑时，先确认绘画界面或其他已授权接口是否真实支持。
- 当前工具 `background` 枚举是 `auto` / `opaque`，不能传 `transparent`。
- 提示词写 transparent 不保证输出带 alpha；本次 Qwen-Image 就生成了白底和假棋盘格。
- 除此次成功样本外，其他模型或编辑功能未在本链路中验证。

## 1A. 直接调用绘图 REST API（其他窗口不具备 Cherry 工具时）

历史成功调用的请求日志确认如下接口与模型。**此链路的成功是通过 Cherry 发出的；下面的独立 Python 示例本次未实跑，不等同于额外端到端测试。**

| 项目 | 值 |
|---|---|
| 服务商 | SiliconFlow / 硅基流动 |
| 控制台 | `https://cloud.siliconflow.cn` |
| API Base URL | `https://api.siliconflow.cn/v1` |
| 生图端点 | `POST https://api.siliconflow.cn/v1/images/generations` |
| 模型 ID | `Qwen/Qwen-Image` |
| 认证 | `Authorization: Bearer <SILICONFLOW_API_KEY>` |
| 内容类型 | `Content-Type: application/json` |
| 建议请求体 | `{"model":"Qwen/Qwen-Image","prompt":"<完整提示词>","image_size":"1328x1328","batch_size":1}` |
| 响应图片 | 读取 JSON 中 `images[].url` 并及时下载原图 |
| 本地 Key 约定 | 环境变量 `SILICONFLOW_API_KEY`，由用户在本地安全注入 |

官方 API 文档已由核对任务顺序读完缓存全文（107217/107217 字符，100%）。文档当前展示的请求域名是 `api.siliconflow.com`；本机历史成功日志使用 `api.siliconflow.cn`，下面复现本机国内通道，不自动改成国际域名，也不假定两边账号/余额/Key 通用。

官方 Qwen 分支参数核对结果：

- schema 必填列表仅列 `model`、`prompt`，但 `image_size` 的文字描述另标 required，文档存在不一致。因此独立 HTTP 请求显式填写 `image_size` 更稳妥。
- Qwen 推荐尺寸包括 `1328x1328`、`1664x928`、`928x1664`、`1472x1140`、`1140x1472`、`1584x1056`、`1056x1584`；推荐不等于仅允许这些尺寸，也不代表任意尺寸都有效。
- Qwen 的 `batch_size` 范围 1–4、默认 1；先使用 1。
- 返回的图片链接有效期为 1 小时，应立即下载，不能把临时 URL 当永久素材路径。
- 响应 schema 包含可选顶层 `seed`，若实际返回可和模型/提示词一起记录，但不保证每次都有，也不保证 seed 能跨模型版本完全复现。[cite:abf8bbb6-1]

不要把 API Key 贴进聊天、文档、Git、命令行字面量或源码；不要为了读取已保存的 Key 解密 Cherry 配置。拿不到 Key 就用内置工具或请用户自行配置环境变量。

下面代码仅用 Python 标准库，示例脚本可由接手窗口另存；使用完整原图，不从聊天截图提取 sprite。代码会请求付费服务，只有用户明确要求生成时才运行。

```python
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen

api_key = os.environ.get("SILICONFLOW_API_KEY")
if not api_key:
    raise SystemExit("请在本地设置 SILICONFLOW_API_KEY；不要把密钥发到聊天。")

output = Path("D:/the-thing/art/organs/organ_new_source.png")
if output.exists():
    raise SystemExit("输出文件已存在，请检查内容并改用新文件名。")

payload = {
    "model": "Qwen/Qwen-Image",
    "prompt": "A single living heart organ, chunky pixel art game sprite, front view, centered, dark maroon and crimson, pink highlights, purple veins, strong dark outline, plain solid white background, generous empty margins.",
    "image_size": "1328x1328",
    "batch_size": 1,
}
request = Request(
    "https://api.siliconflow.cn/v1/images/generations",
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    },
    method="POST",
)
with urlopen(request, timeout=300) as response:
    result = json.load(response)

images = result.get("images") or []
if not images or not images[0].get("url"):
    raise SystemExit("接口未返回图片 URL，请检查响应结构；不要回显认证信息。")

# 不向图片存储域名转发 API Authorization 头。
with urlopen(images[0]["url"], timeout=120) as response:
    image_bytes = response.read()

output.parent.mkdir(parents=True, exist_ok=True)
# 独占创建，避免检查之后发生的同名文件覆盖。
with output.open("xb") as file:
    file.write(image_bytes)
print(f"已下载原始图片：{output}")
```

说明：文件名以 `.png` 示意，接手窗口必须通过 Pillow 等检查实际格式与完整性，不要仅靠扩展名判断。模型可用尺寸、批量上限、额外字段以最新官方文档为准；不能直接照抄 OpenAI 的 `background`、`quality`、`size` 参数到这个 API。

API 文档：`https://docs.siliconflow.com/cn/api-reference/images/images-generations`。

## 2. 原图和历史样本

历史成功工具返回的图片文件 ID：

```text
01a14db2-92c0-742f-9bc0-d961195690b1
```

本机对应原图（整理交接时确认文件仍存在）：

```text
C:/Users/19453/AppData/Roaming/CherryStudio/Data/Files/01a14db2-92c0-742f-9bc0-d961195690b1.png
```

新图片应使用工具返回的文件标识/路径定位，不能复用上述 ID，也不要把它误认为 API Key。若工具只给 ID，当前机器可检查 `Data/Files/<ID>.png` 是否存在；该目录约定不是跨版本保证。不要为找图片扫描整个用户目录或读取应用数据库。

已验证结果：

| 文件 | 用途 |
|---|---|
| `art/organs/organ_heart_native.png` | 用户认可的 50×50、RGBA 心脏 sprite |
| `art/organs/organ_heart_native_preview.png` | 6 倍最近邻预览，深色背景，预览自身不是透明底 |
| `art/organs/make_sprite_native.py` | 推荐后处理脚本 |
| `art/organs/cleanup_shadow.py` | 可选灰色投影清理脚本 |
| `art/IMAGE_PIPELINE.md` | 较早的流程记录；其中网格/节点接入状态可能过时 |

旧的 `organ_heart_32.png` / `make_sprite.py` / `simplify_sprite.py` 不作为标准方案；不要自动删掉或覆盖。

## 3. 必须保留的后处理方法

### 为什么不能直接缩成 32×32

这次原图是 1328×1328，但它画出的「逻辑像素」不是单个图像像素：横向周期约 22px、纵向约 21px。脚本得到 51×54 的采样网格，去透明边后居中输出约 50×50。

先前强制 32×32 和限色使轮廓、血管、高光丢失，用户明确表示模糊且偏离原图。后来保留接近原生的网格才获得认可。

**22px、21px、50×50 都是该样本的测量结果，不是其他素材必须照抄的规格。**

### 脚本实际步骤

1. RGB 三通道都 >200 的亮像素占比大于 5% 时，取其包围盒裁掉外部假棋盘格。
2. 从四边 flood fill RGB 三通道都 ≥235 的近白区域，设为透明，避免直接删除所有内部高光。
3. 将 RGB 转为灰度均值，计算横纵梯度总量，自相关后在 8–59px 范围选峰值估计像素周期。
4. 根据周期估算网格数量，采样每个单元中心；**不做平滑插值缩图**。
5. alpha 二值化、清少邻接的孤立点及部分浅灰边缘，按 alpha 包围盒裁切，居中放入正方形透明画布。
6. 输出 PNG 和 6 倍 nearest 放大预览。

### 可复制运行命令（Git Bash / Windows）

`uv` 临时提供 Pillow 和 NumPy，不修改项目依赖、不需要全局 pip 安装。输出使用新名称，存在同名文件时先查看，不能直接覆盖用户已有素材。

```bash
uv run --with pillow --with numpy python \
  "D:/the-thing/art/organs/make_sprite_native.py" \
  "C:/Users/19453/AppData/Roaming/CherryStudio/Data/Files/01a14db2-92c0-742f-9bc0-d961195690b1.png" \
  "D:/the-thing/art/organs/organ_heart_native_handoff_check.png"
```

这是复现命令示例，本次交接未重新执行，也未生成该示例输出。

可选手动指定横、纵周期（只有自动结果不对且已人工核对时使用）：

```bash
uv run --with pillow --with numpy python \
  "D:/the-thing/art/organs/make_sprite_native.py" \
  "D:/path/to/source.png" "D:/path/to/new_output.png" 22 21
```

### 方法限制——不是通用抠图器

- 当前脚本针对这张白底、暗色主体、带外框的样本。真正带透明背景、复杂背景、白色骨骼占比很高的素材不应不加检查直接使用。
- 亮像素 bbox 可能误裁主体；自动周期没有网格相位拟合，AI 画得不规整时会有采样误差。
- 现有透明度/孤立点/浅灰边缘清理可能误伤细触须、浅色骨刺，必须查看结果。
- 全黑、纯色或缺少像素周期的图片不适合该自动测量方法。
- 不要反复运行滤镜来「增强像素感」；先与原图对比轮廓、细节和色彩。

若仍有灰色投影，可在新输出副本上运行：

```bash
uv run --with pillow python \
  "D:/the-thing/art/organs/cleanup_shadow.py" \
  "D:/path/to/new_output.png" "D:/path/to/new_output_clean.png"
```

该脚本会删除全图中 RGB 最大差 ≤18 且最大值 ≥85 的像素，**不只处理边缘**。可能删除灰白骨骼/牙齿/高光，不要默认调用。

## 4. 提示词

### 曾成功的完整心脏提示词

```text
Pixel art game sprite for a 2D grid-based body-horror roguelike. A single grotesque living heart organ, front view, centered, isolated on a fully transparent background. Chunky 32x32 pixel-art style with large visible square pixels, hard edges, no anti-aliasing, limited palette of about 7 colors: dark maroon, crimson, raw pink, pale bone highlight, deep purple shadow. Plump asymmetric heart with exposed thick arteries and veins, small bone spurs, wet glossy highlights. Strong dark outline. Sprite occupies about 80 percent of the canvas with a transparent margin around it. Single object only. No text, no labels, no UI, no background, no drop shadow, no floor, no frame.
```

这是历史原文，不是说模型确实遵循了 32×32、7 色、真透明等要求。输出实际约 50×50 逻辑像素，而且白底不透明。

### 后续建议模板（尚未作为本次成功样本验证）

```text
A single [ORGAN] game sprite for a 2D body-horror roguelike.
Front view, centered, complete silhouette, generous empty margins.
Chunky pixel art, distinct square pixel clusters, strong dark outline.
Palette: dark maroon, crimson, raw pink, pale bone highlights, deep purple shadows.
[MAIN SHAPE AND FEW IMPORTANT DETAILS].
Plain solid white background, isolated object.
```

建议白底交给脚本处理，避免让模型画「透明棋盘格」；不要依赖模型精确输出原生像素尺寸、连接口数量或严格对称。接口点/名称/精确数量留给引擎或后期绘制。

## 5. 质量验收与 Godot 接入边界

1. 检查真 alpha：透明背景应是 PNG alpha=0，不是把棋盘格画进图里。
2. 对照原图看轮廓、血管、高光；不接受以明显丢细节换取统一 32×32。
3. 同时看原生尺寸、整数倍 nearest 预览、实际游戏显示尺寸。
4. 先让用户确认新素材，不自动改场景或覆盖当前贴图。
5. Godot 使用原生 `TextureRect` / `Sprite2D` 等合适节点，`texture_filter` 设 nearest，保持宽高比；具体节点和资源字段以当前项目为准。
6. nearest 避免插值发糊，但不能补回丢失细节；50px 放到 72px 属于非整数倍，像素块会宽窄不一；缩到小于原生尺寸仍会丢细节。严格像素呈现还需整数缩放与像素对齐。
7. 不因本次生图修改器官接口、名称、旋转、数值或玩法。旧文档中的 7×5 与 Panel 替换描述不是当前实施指令。

## 6. 故障排查

| 现象 | 处理 |
|---|---|
| `No painting model is configured` | 设置 → 默认模型 → 绘画模型；确认已选图片模型，不是只配置了聊天模型 |
| 工具列表没有生图工具 | 检查智能体内置工具；仍无则换新会话检查，不用不存在的工具名调用 |
| 泛化 `provider error` | 看当次服务商返回或日志，不能直接认定是提示词违规 |
| HTTP 402、code 30001、`account balance is insufficient` | 该历史案例是 SiliconFlow 余额不足；由用户到控制台确认充值后再试，不要重复耗请求 |
| HTTP 401/403 | 核对 Key 是否有效、模型权限及账户状态；不回显 Key |
| HTTP 429 | 查看限流信息、减少并发并按服务商提示等待 |
| 输出有白底/棋盘格 | 检查 alpha，按样本适配裁框/抠图流程，不当成真透明 |
| 变糊/偏色 | 撤回平滑缩放或强制低分辨率，重测原生周期，保留原始调色 |

日志位置：

```text
C:/Users/19453/AppData/Roaming/CherryStudio/logs/app-error.<当天日期>.log
```

历史故障日志是 `app-error.2026-10-18.log`，不是每次都读取这个日期。日志可能含私人数据，只筛当次请求的模型 ID、状态码和错误信息；不要将原始日志整段转发。

## 7. 备用通道状态

- inference.sh / belt：历史安装并登录过，工作区用户名 `nutbeater`；本次生图提交因余额不足失败，**没有通过它验证心脏生成成功**。
- `openai/gpt-image-2` 是当时查看过的 inference.sh 应用 ID，不是 SiliconFlow 模型名，不能填进上述请求。
- Router One 等其他通道不属于此次成功链路；不要为这份交接自动换服务商或上传素材。
- 余额、价格、付款方式会变化，用户确认后再查当前平台说明。

## 8. 接手 Agent 的执行清单

1. 读项目规则，说明本轮只生成什么素材、输出什么文件、在哪停止。
2. 确认生图工具及默认绘画模型可用。
3. 单张生成，保存原图/文件标识；记录实际模型和提示词，不记录 Key。
4. 针对实际背景和像素周期运行后处理，使用新文件名。
5. 验证尺寸、alpha、轮廓和清晰度，给用户看预览。
6. 停在用户确认；接入 Godot 另开经确认的阶段。
7. 最终仅报告成品文件，不把临时/失败结果当交付。需要转移到其他设备时一并复制原图、处理脚本和成品 PNG。
