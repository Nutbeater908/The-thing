## 顶层叠绘：拉线 + 物理预览。
##
## 作为 AssemblyGrid 的高 z_index 子节点，盖在器官之上，
## 保证近距离器官之间的线、质心和推力箭头都看得清。
##
## grid 不做静态类型标注，避免与 assembly_grid.gd 形成循环依赖。
extends Control

var grid


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if grid == null:
		return

	_draw_links()
	if grid.show_physics:
		_draw_physics()


func _draw_links() -> void:
	for link in grid.links():
		var a: Vector2 = grid.endpoint_pos(link.a)
		var b: Vector2 = grid.endpoint_pos(link.b)
		var color: Color = grid.port_color(link.type)
		draw_line(a, b, Color(color, 0.9), 3.0)
		draw_circle(a, 3.5, color)
		draw_circle(b, 3.5, color)

	if grid.drag_from == null:
		return

	# 拖拽预览
	var from: Vector2 = grid.endpoint_pos(grid.drag_from)
	var drag_color: Color = grid.port_color(grid.drag_from.type)
	draw_line(from, grid.drag_pos, Color(drag_color, 0.55), 2.0)

	var target = grid.endpoint_at(grid.drag_pos)
	if target != null and grid.is_valid_target(grid.drag_from, target):
		draw_circle(grid.endpoint_pos(target), 7.0, Color(drag_color, 0.35))


## 质心 + 每条腿的蹬地方向
func _draw_physics() -> void:
	var stats = grid.stats
	if stats == null:
		return

	var cs: float = grid.cell_size()
	var origin: Vector2 = grid._grid_origin()

	# 质心：十字 + 光环
	var centroid: Vector2 = origin + stats.centroid * cs
	var c_color := Color(1.0, 0.85, 0.30, 0.95)
	draw_circle(centroid, 9.0, Color(c_color, 0.18))
	draw_line(centroid - Vector2(11, 0), centroid + Vector2(11, 0), c_color, 2.0)
	draw_line(centroid - Vector2(0, 11), centroid + Vector2(0, 11), c_color, 2.0)

	# 每条腿的蹬地方向（伸展方向的反方向）
	var leg_color := Color(0.35, 0.85, 0.95, 0.9)
	for limb in stats.legs():
		var root: Vector2 = origin + (Vector2(limb.anchor) + Vector2(0.5, 0.5)) * cs
		var dir: Vector2 = -limb.direction
		var tip := root + dir * cs * 1.15

		draw_line(root, tip, leg_color, 2.5)
		var side := dir.orthogonal() * 5.0
		draw_line(tip, tip - dir * 11.0 + side, leg_color, 2.0)
		draw_line(tip, tip - dir * 11.0 - side, leg_color, 2.0)
