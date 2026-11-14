## 部件定义。纯数据，不含任何场景依赖。坐标一律用世界像素。
class_name PartData
extends Resource

## WORK = 作业件（机械臂这类占格部件）；TOOL = 末端工具（不占格，绑在工具口上）
enum Category { FRAME, CORE, LOCOMOTION, WORK, UTILITY, TOOL }

@export var id: StringName
@export var display_name := ""
@export var category := Category.FRAME
## 尺寸（世界像素），左上角为原点
@export var size := Vector2(32, 32)
## 只有根部件（机身）为 true，且全机唯一
@export var is_root := false
## 控制源（主控芯片），全机唯一
@export var is_control_source := false

## 挂到父件上的接口；根部件留空
@export var anchor: SocketData
## 子件能接的位置
@export var sockets: Array[SocketData] = []

@export_group("数值")
@export var mass := 1.0
@export var max_hp := 10.0
## 正数供能，负数耗能
@export var power := 0.0
@export var cost := 10
## 末端工具的伤害（非工具部件为 0）
@export var damage := 0.0
## 末端工具的长度（链尾那一节，世界像素）
@export var reach := 0.0

@export_group("表现")
@export var texture: Texture2D
@export var color := Color(0.55, 0.58, 0.63)


func socket(uid: StringName) -> SocketData:
	for s in sockets:
		if s.uid == uid:
			return s
	return null


## 接口在本件本地坐标里的位置（含旋转）
func socket_offset(uid: StringName, rotation := 0) -> Vector2:
	var s := socket(uid)
	if s == null:
		return Vector2.ZERO
	return SocketData.rotate_vec(s.offset, rotation)


## 唯一的"是不是末端工具"判断，全工程只此一处
func is_tool_part() -> bool:
	return category == Category.TOOL


func is_placeable() -> bool:
	return not is_tool_part()


## 数据自检：返回问题描述，空数组表示合法
func audit() -> Array[String]:
	var issues: Array[String] = []
	if id == &"":
		issues.append("缺少 id")
	if size.x <= 0.0 or size.y <= 0.0:
		issues.append("尺寸无效")
	if is_tool_part() and anchor != null:
		issues.append("工具不该有挂点")
	if is_placeable() and not is_root and anchor == null:
		issues.append("非根部件必须有挂点")
	if is_root and anchor != null:
		issues.append("根部件不该有挂点")
	return issues
