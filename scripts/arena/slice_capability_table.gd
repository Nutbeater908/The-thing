class_name SliceCapabilityTable
extends Resource
## 拼装统计 → 短关卡能力参数的数值表。
##
## 每个数组都按「数量」索引（0、1、2……），数量超出数组末尾时沿用最后一项。
## 调平衡只改 resources/arena/slice_capabilities.tres，不需要动代码。
## 这里只覆盖切片已有的字段，不引入新的玩法系统。

@export_group("质量 → 血量")
## 血量基准质量：该质量恰好对应 hp_base
@export var reference_mass: float = 10.0
@export var hp_base: float = 80.0
## 每偏离基准 1 点质量，血量变化多少
@export var hp_per_mass: float = 5.0
@export var hp_min: float = 45.0
@export var hp_max: float = 190.0

@export_group("支撑腿 → 动作模组与移动")
## 索引 = 朝下的支撑腿数量。0 号不使用：0 条支撑腿会被拒绝入场。
@export var walk_speed_by_legs: Array[float] = [0.0, 95.0, 150.0, 170.0, 182.0]
@export var acceleration_by_legs: Array[float] = [0.0, 520.0, 650.0, 700.0, 730.0]
@export var jump_speed_by_legs: Array[float] = [0.0, 300.0, 350.0, 378.0, 392.0]
## 仅用于 HUD 显示，不改变运动逻辑
@export var module_name_by_legs: Array[String] = [
	"无支撑腿",
	"独腿踮行",
	"双腿行走",
	"多腿行走",
	"多腿行走",
]

@export_group("爪 → 攻击")
## 索引 = 爪数量
@export var damage_by_claws: Array[float] = [4.0, 12.0, 18.0, 22.0]
@export var attack_range_by_claws: Array[float] = [90.0, 135.0, 160.0, 175.0]
@export var attack_cooldown_by_claws: Array[float] = [0.5, 0.35, 0.3, 0.27]


func _pick_float(values: Array, index: int) -> float:
	if values.is_empty():
		return 0.0
	return float(values[clampi(index, 0, values.size() - 1)])


func _pick_text(values: Array, index: int) -> String:
	if values.is_empty():
		return ""
	return String(values[clampi(index, 0, values.size() - 1)])


func hp_for_mass(value: float) -> float:
	return clampf(hp_base + (value - reference_mass) * hp_per_mass, hp_min, hp_max)


func walk_speed_for(legs: int) -> float:
	return _pick_float(walk_speed_by_legs, legs)


func acceleration_for(legs: int) -> float:
	return _pick_float(acceleration_by_legs, legs)


func jump_speed_for(legs: int) -> float:
	return _pick_float(jump_speed_by_legs, legs)


func module_for(legs: int) -> String:
	return _pick_text(module_name_by_legs, legs)


func damage_for(count: int) -> float:
	return _pick_float(damage_by_claws, count)


func attack_range_for(count: int) -> float:
	return _pick_float(attack_range_by_claws, count)


func attack_cooldown_for(count: int) -> float:
	return _pick_float(attack_cooldown_by_claws, count)
