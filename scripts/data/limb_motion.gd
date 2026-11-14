## 动作模组：一条肢体链在每个时刻应该摆成什么角度。
##
## 两段结构（见 docs/肢体系统设计稿.md）：
##  - 打击阶段：角度**直接由曲线驱动**，速度可控，才有发力感
##  - 回位阶段：交给 LimbRig 的弹簧，松弛感留在这里
##
## angles 按「根节 → 末节」排列，长度不等于链节数时沿用最后一个。
class_name LimbMotion
extends Resource

enum Ease { LINEAR, EASE_IN, EASE_OUT, EASE_IN_OUT }

@export var id: StringName = &"swing"
@export var display_name: String = "下劈"
## 0 = 主攻击键，1 = 副攻击键，2 = 跳跃时触发
@export var trigger := 0
## 打击阶段的时长（秒）；回位另算
@export var duration := 0.20
## 从第几秒开始判定命中——抬手阶段速度也很快，不能算伤害
@export var hit_start := 0.10
## 每节相对上一节延迟多少秒——这个滞后就是"鞭子"的来源
@export var segment_delay := 0.025
## 回位弹簧的角频率：越小越松、恢复越慢
@export var recover_omega := 18.0
## 关键帧之间的插值方式；发力动作用 EASE_IN
@export var easing: Ease = Ease.EASE_IN
## 关键帧：[{ "t": float, "angles": Array[float] }]，必须按 t 升序
@export var keyframes: Array[Dictionary] = []


## 求打击阶段某个时刻的目标角度
func sample(t: float, count: int) -> Array[float]:
	var out: Array[float] = []
	if keyframes.is_empty():
		for i in count:
			out.append(0.0)
		return out

	var tt := clampf(t, 0.0, duration)
	var prev: Dictionary = keyframes[0]
	var next: Dictionary = keyframes[keyframes.size() - 1]

	if tt <= float(prev.get("t", 0.0)):
		next = prev
	else:
		var found := false
		for i in range(1, keyframes.size()):
			if float(keyframes[i].get("t", 0.0)) >= tt:
				prev = keyframes[i - 1]
				next = keyframes[i]
				found = true
				break
		if not found:
			prev = keyframes[keyframes.size() - 1]
			next = prev

	var t0 := float(prev.get("t", 0.0))
	var t1 := float(next.get("t", t0))
	var k := 0.0 if is_equal_approx(t1, t0) else (tt - t0) / (t1 - t0)
	k = _ease(k)

	var a0: Array = prev.get("angles", [])
	var a1: Array = next.get("angles", [])
	for i in count:
		out.append(lerpf(_pick(a0, i), _pick(a1, i), k))
	return out


func _ease(k: float) -> float:
	match easing:
		Ease.EASE_IN:
			return k * k
		Ease.EASE_OUT:
			return 1.0 - pow(1.0 - k, 2.0)
		Ease.EASE_IN_OUT:
			return 2.0 * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2.0) * 0.5
		_:
			return k


## 取第 i 个角度；越界时沿用最后一个，空数组返回 0
static func _pick(arr: Array, i: int) -> float:
	if arr.is_empty():
		return 0.0
	if i < arr.size():
		return float(arr[i])
	return float(arr[arr.size() - 1])
