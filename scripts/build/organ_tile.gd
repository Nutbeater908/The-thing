## 单个器官在拼装盘上的视觉：按格子集合画出异形轮廓，并在接点位置标出类型色。
class_name OrganTile
extends Control

const C_NERVE := Color(0.35, 0.85, 0.95)
const C_BLOOD := Color(0.92, 0.26, 0.32)
const C_BONE := Color(0.88, 0.86, 0.78)

const PORT_RADIUS := 5.0

var data: OrganData
## 注意：不能叫 rotation，会和 Control 内置属性冲突
var organ_rotation := 0
var cell_px := 64.0

## 接点在控件内的像素坐标：uid -> Vector2
var _port_centers: Dictionary = {}


func setup(p_data: OrganData, p_rotation: int, p_cell_px: float) -> void:
	data = p_data
	organ_rotation = p_rotation
	cell_px = p_cell_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bb := data.bounds(organ_rotation)
	size = Vector2(bb.size) * cell_px
	_layout_ports()
	queue_redraw()


## 接点在控件内的像素坐标；uid 不存在时返回 Vector2.ZERO
func port_center(uid: StringName) -> Vector2:
	return _port_centers.get(uid, Vector2.ZERO)


## 按当前旋转重算接点位置；同一格里多个接点时横向错开
func _layout_ports() -> void:
	_port_centers.clear()
	var bb := data.bounds(organ_rotation)
	var shift := Vector2(-bb.position) * cell_px

	var by_cell: Dictionary = {}
	for port in data.rotated_ports(organ_rotation):
		if not by_cell.has(port.cell):
			by_cell[port.cell] = []
		by_cell[port.cell].append(port)

	for cell in by_cell:
		var ports: Array = by_cell[cell]
		var n := ports.size()
		# 同格多个接点时横向铺开：间距跟随格子尺寸，避免挤在一起点错
		var spacing := clampf(cell_px * 0.36, 12.0, 30.0)
		for i in n:
			var port: OrganPort = ports[i]
			var center := shift + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_px
			center.x += (i - (n - 1) * 0.5) * spacing
			_port_centers[port.uid] = center


func _draw() -> void:
	if data == null:
		return

	var bb := data.bounds(organ_rotation)
	# 把包围盒左上角对齐到控件原点
	var shift := Vector2(-bb.position) * cell_px

	# 器官本体：每格独立绘制，留出细缝形成形体质感
	for c in data.rotated_cells(organ_rotation):
		var r := Rect2(shift + Vector2(c) * cell_px, Vector2(cell_px, cell_px)).grow(-2.0)
		draw_rect(r, data.color)
		draw_rect(r, Color(0, 0, 0, 0.45), false, 2.0)

	# 接点
	for port in data.rotated_ports(organ_rotation):
		var center: Vector2 = _port_centers.get(port.uid, Vector2.ZERO)
		draw_circle(center, PORT_RADIUS, _port_color(port.type))
		draw_circle(center, PORT_RADIUS, Color(0, 0, 0, 0.65), false, 1.5)


func _port_color(type: int) -> Color:
	match type:
		OrganData.NERVE:
			return C_NERVE
		OrganData.BLOOD:
			return C_BLOOD
		_:
			return C_BONE
