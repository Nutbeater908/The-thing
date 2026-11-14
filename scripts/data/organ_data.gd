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
## 每格贴图；留空则退化成按 color 画的色块。必须是 64×64 的格子图。
@export var texture: Texture2D
## 剖/开状态贴图：例如颅骨里装了脑时显示剖面
@export var texture_open: Texture2D
## 贴图按原始像素尺寸居中绘制，不拉伸到包围盒（小贴图放大贴在格子里时用）
@export var texture_native := false
## 贴图在格子包围盒内的像素偏移（配合 texture_native 微调对位）
@export var texture_offset := Vector2.ZERO

@export_group("形状与接点")
## 器官占据的相对格坐标
@export var cells: Array[Vector2i] = []
## 接点：每项挂在 cells 中的某一格上
@export var ports: Array[OrganPort] = []

## 肢体类型：决定它在关卡中承担什么作用
## ARM 追加在末尾，保证旧资源的整数取值不变
enum Limb { NONE, LEG, CLAW, ARM }

## 末端的种类；只有 TipKind != NONE 的器官能当肢体链的终点
enum TipKind { NONE, CLAW, SPIKE, HAND, HAMMER }

@export_group("肢体")
@export var limb: Limb = Limb.NONE
## 可选的固定腿族运动测试定义；不参与正常战斗或存活/经济计算。
@export var motion_test_spec: Resource

@export_group("肢体段")
## 这一节的视觉长度（像素），与占用格子数解耦
@export var segment_length := 80.0
## 相对父节的转动范围（度）；正负号决定默认弯曲方向
@export var joint_min_deg := -120.0
@export var joint_max_deg := 120.0
## 末端参数：只有末节有效
@export var tip_kind: TipKind = TipKind.NONE
@export var tip_damage := 0.0
@export var tip_radius := 10.0
## 这条链触发用的输入动作名；同名的链会被同一个按键触发
@export var bind_action: StringName = &"attack"

@export_group("肢体单元")
## 整体式肢体单元的内部分段：[{length, joint_min, joint_max}]
## 非空表示这个器官是一个「大单元」，整条肢体由它自己描述，不再由网格链拼出
@export var unit_segments: Array[Dictionary] = []
## 单元唯一的挂点（相对格）
@export var attach_cell := Vector2i.ZERO
## 挂点朝向：0=上 1=右 2=下 3=左
@export var attach_dir := 2
## 单元自带的动作模组
@export var motion: Resource

@export_group("工具")
## 这个部件是不是「末端工具」（爪/锤/钻/枪）：不进网格，绑定在臂的工具口上
@export var is_tool := false
## 工具的口径（世界像素），作为链的最后一节长度
@export var tool_length := 22.0
## 工具质量（工具不占格，所以质量单独给）
@export var tool_mass := 4.0
## 这个部件是否带工具口（机械臂）
@export var tool_socket := false

@export_group("骨骼")
## 这个器官是不是骨骼（骨骼与器官共用一张网格，但骨骼之间不能重叠）
@export var is_bone := false
## 是否是骨架的根（第一期只有脊柱）
@export var is_bone_root := false
## 骨骼接受的器官 id 白名单；空 = 接受所有非骨骼器官
@export var bone_accepts: Array[StringName] = []
## true = 被接受的器官必须完全落在骨骼格内（容纳式，例如颅骨与脑）
@export var bone_containment := false
## 骨骼撑开的容积格（例如肋骨），被接受的器官必须完全落在其中
@export var bone_volume: Array[Vector2i] = []
## 骨骼提供给肢体单元的挂点：[{cell: Vector2i, dir: int}]
@export var bone_attach_points: Array[Dictionary] = []

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
	return cells.size() * mass_per_cell + (tool_mass if is_tool else 0.0)


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
