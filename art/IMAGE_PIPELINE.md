# 图像生成链路 — The Thing

> 已验证日期：2026-10-18。游戏开发窗口可直接按本文档操作。

## 可用通道

**主通道：Cherry Studio 内置 `generate_image`**

- 服务商：SiliconFlow（硅基流动）
- 模型：`Qwen/Qwen-Image`
- 配置位置：设置 → 默认模型 → **绘画模型**
- 智能体 → 内置工具 → 确认 **生成图片** 已启用
- 需要 SiliconFlow 账户余额；`HTTP 402 / code 30001` = 余额不足

**备用通道：inference.sh / belt**

- 账号：`nutbeater`，本机已登录
- 当前余额为 0；充值需 Stripe 外卡
- 可用 `openai/gpt-image-2` 等模型

**排错日志**

```
%APPDATA%\CherryStudio\logs\app-error.2026-*.log
```

## 关键坑（务必记住）

1. **Qwen-Image 不支持真透明**。它会在白底画布外生成一圈**棋盘格图案**（棋盘格是图片内容，不是 UI）。必须后处理：先裁掉棋盘格，再把白底抠成透明。
2. **AI 像素画有逻辑像素网格**。本次原图每块约 22px，原生分辨率约 50×50。直接缩到 32×32 会明显变糊。
3. **不要为了“像素感”强行压小**。先测出真实网格，按网格重采样，保留原生尺寸。

## 标准处理流程

1. 用亮像素（RGB > 200）的包围盒裁掉棋盘格外框。
2. 从图像边缘 flood fill 近白像素（RGB ≥ 235），只把连通区域 alpha 设为 0，保留器官内部高光。
3. 对横向/纵向梯度做自相关，测出逻辑像素周期（在 8–60px 内找峰值）。
4. 按周期**采样每个块的中心**，得到原生网格（不要用 resize）。
5. alpha 二值化、去孤立点、清掉边缘浅色抗锯齿杂点。
6. 输出 PNG，同时生成最近邻放大预览。

## 脚本

| 脚本 | 用途 |
|---|---|
| `art/organs/make_sprite_native.py` | **推荐**：自动测周期，按原生网格重采样 |
| `art/organs/make_sprite.py` | 旧版：固定缩到 32×32 |
| `art/organs/simplify_sprite.py` | 旧版：限色降采样 |

用法：

```bash
uv run --with pillow --with numpy python art/organs/make_sprite_native.py <原图> <输出.png>
```

## Godot 接入约定

- 拼装盘：7×5，格子边长 34–84px（窗口自适应）
- 单格场景 `scenes/build/organ_tile.tscn`，最大显示约 72×72
- 用 `TextureRect` 替换现在的纯色 `Body` Panel
- 纹理过滤必须设为 **nearest**（最近邻）
- 接口点、器官名称、旋转逻辑保留

## 已验证产物

- `art/organs/organ_heart_native.png` — 50×50 心脏精灵，透明背景
- `art/organs/organ_heart_native_preview.png` — 6 倍预览

## 有效提示词模板

```
Pixel art game sprite for a 2D grid-based body-horror roguelike. A single
[器官], front view, centered, isolated on a fully transparent background.
Chunky pixel-art style with large visible square pixels, hard edges, no
anti-aliasing, limited palette of about 7 colors: [色板]. [细节描述].
Strong dark outline. Sprite occupies about 80 percent of the canvas with a
transparent margin around it. Single object only. No text, no labels, no UI,
no background, no drop shadow, no floor, no frame.
```

风格关键词：body-horror、gore、exposed arteries、bone spurs、wet highlights、dark maroon / crimson / raw pink / pale bone / deep purple。
