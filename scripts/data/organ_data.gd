## 器官数据：异形格子集合 + 接点列表。
##
## 器官由若干相对格坐标（cells）组成，形状不限于矩形；
## 接点（OrganPort）挂在某个具体的格子上，玩家用「链」把两个同类接点连起来。
## 旋转按 90° 增量作用于 cells 和 ports，缩放暂留接口。
##
## 所有字段都是 @export，因此每个器官可以存成独立的 .tres 资源，
## 调数值、改形状都不需要动代码。
class_name OrganData
extends Resource

## 链路类型位掩码
const NERVE := 1 << 0  ## ⚡ 控制信号
const BLOOD := 1 << 1  ## 🩸 物质输送
const BONE := 1 << 2   ## 🦴 物理支撑


@export_group("身份")
@export var id: StringName = &""
@export var display_name: String = ""
@export var color: Color = Color(0.70, 0.30, 0.35)

@export_group("形状与接点")
## 器官占据的相对格坐标
@export var cells: Array[Vector2i] = []
## 接点：每项挂在 cells 中的某一格上
@export var ports: Array[OrganPort] = []

## 肢体类型：决定它在关卡中承担什么作用
enum Limb { NONE, LEG, CLAW }

@export_group("肢体")
@export var limb: Limb = Limb.NONE
## 可选的固定腿族运动测试定义；不参与正常战斗或存活/经济计算。
@export var motion_test_spec: Resource

@export_group("生存")
## 该器官被摧毁所需的伤害
@export var max_hp := 30.0

@export_group("经济")
## 购买价格；拆除返还与修复费用都按它计算
@export var cost := 15

@export_group("玩法标记")
@export var is_parasite := false
@export var is_brain := false
@export var is_heart := false
@export var needs_nerve := false
@export var needs_blood := false
## 正值 = 消耗血流，负值 = 产生血流
@export var blood_rate := 0.0

@export_group("物理")
## 每格质量，留给将来的承重计算
@export var mass_per_cell := 1.0

@export_group("扩展")
## 预留：等比缩放（1.0 = 原始大小）。接入前恒为 1。
@export var scale_factor := 1.0


static func _rotate_cell(c: Vector2i, rotation: int) -> Vector2i:
	var p := c
	for i in rotation:
		p = Vector2i(-p.y, p.x)
	return p


func rotated_cells(rotation: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(_rotate_cell(c, rotation))
	return out


func rotated_ports(rotation: int) -> Array[OrganPort]:
	var out: Array[OrganPort] = []
	for port in ports:
		out.append(port.rotated(rotation))
	return out


## 旋转后的包围盒，用于计算显示尺寸
func bounds(rotation: int) -> Rect2i:
	var rc := rotated_cells(rotation)
	if rc.is_empty():
		return Rect2i()
	var lo := rc[0]
	var hi := rc[0]
	for c in rc:
		lo.x = mini(lo.x, c.x)
		lo.y = mini(lo.y, c.y)
		hi.x = maxi(hi.x, c.x)
		hi.y = maxi(hi.y, c.y)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func mass() -> float:
	return cells.size() * mass_per_cell


## 把 organ 从 hp 修满需要多少代币
static func repair_cost(organ: OrganData, hp: float) -> int:
	if organ.max_hp <= 0.0:
		return 0
	var missing := clampf(1.0 - hp / organ.max_hp, 0.0, 1.0)
	if missing <= 0.0:
		return 0
	return ceili(organ.cost * missing * EconomyTuning.get_tuning().repair_rate)


## 拆除 organ 时按剩余 HP 返还多少代币
static func refund_value(organ: OrganData, hp: float) -> int:
	if organ.max_hp <= 0.0:
		return 0
	return floori(organ.cost * clampf(hp / organ.max_hp, 0.0, 1.0))
