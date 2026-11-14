class_name SliceBodyProfile
extends Resource
## 一次进入切片时锁定的身体能力快照。
##
## 由孵化池拼装算出来，重试时原样复用；不写存档、不改动原拼装。
## 运动包络（胶囊尺寸、碰撞层、坡度）仍由原生底座固定，这里只有能力数值。

const TABLE_PATH := "res://resources/arena/slice_capabilities.tres"
## 少于这么多条朝下的支撑腿就走不了路
const MIN_SUPPORT_LEGS := 1

static var _table: SliceCapabilityTable

## 从拼装盘直接构建
static func from_grid(grid) -> SliceBodyProfile:
	var profile := from_stats(CreatureStats.from_grid(grid))
	if grid != null and grid.has_method("organ_count"):
		profile.organ_count = grid.organ_count()
		var value := 0
		for placed in grid.organs():
			value += placed.data.cost
		profile.organ_value = value
	return profile


static func from_stats(stats: CreatureStats) -> SliceBodyProfile:
	var table := table()
	var profile := SliceBodyProfile.new()
	if stats != null:
		profile.support_legs = stats.support_legs().size()
		profile.claws = stats.claws().size()
		profile.mass = stats.mass
	profile.module_name = table.module_for(profile.support_legs)
	profile.walk_speed = table.walk_speed_for(profile.support_legs)
	profile.acceleration = table.acceleration_for(profile.support_legs)
	profile.jump_speed = table.jump_speed_for(profile.support_legs)
	profile.max_hp = table.hp_for_mass(profile.mass)
	profile.damage = table.damage_for(profile.claws)
	profile.attack_range = table.attack_range_for(profile.claws)
	profile.attack_cooldown = table.attack_cooldown_for(profile.claws)
	return profile


static func table() -> SliceCapabilityTable:
	if _table == null:
		_table = load(TABLE_PATH) as SliceCapabilityTable
	return _table


@export var support_legs := 0
@export var claws := 0
@export var mass := 0.0
@export var organ_count := 0
## 身上器官的原价合计，用于过关奖励结算
@export var organ_value := 0
@export var module_name := ""
@export var walk_speed := 0.0
@export var acceleration := 0.0
@export var jump_speed := 0.0
@export var max_hp := 0.0
@export var damage := 0.0
@export var attack_range := 0.0
@export var attack_cooldown := 0.0


## 这个身体能不能作为横版宿主行动
func supported() -> bool:
	return support_legs >= MIN_SUPPORT_LEGS


## HUD 常驻一行：实际生效的能力
func summary_line() -> String:
	return "身体 %s · 支撑腿 %d · 爪 %d · 质量 %.0f  |  移速 %.0f · 跳 %.0f · 生命 %.0f · 伤害 %.0f · 距离 %.0f" % [
		module_name,
		support_legs,
		claws,
		mass,
		walk_speed,
		jump_speed,
		max_hp,
		damage,
		attack_range,
	]


## 入场提示：说明能力来源与固定边界
func entry_notice() -> String:
	return "能力来自孵化池拼装：%s。碰撞与移动包络仍是固定胶囊，只有数值来自拼装；演示收益不写入存档。" % summary_line()
