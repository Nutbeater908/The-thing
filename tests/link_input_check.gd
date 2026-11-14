## 交互自检：模拟鼠标事件，走完整的「选中 → 点击放置 → 拖拽连线」流程。
##   godot --headless --path <项目> --script res://tests/link_input_check.gd
extends SceneTree

var _failed := 0


func _initialize() -> void:
	var lib := OrganLibrary.catalog()
	var grid := AssemblyGrid.new()
	grid.size = Vector2(758, 580)
	root.add_child(grid)

	# 1. 选中寄生虫，点击 (2,3) 放置
	grid.set_selected(lib[&"parasite"])
	_click(grid, _cell_center(grid, Vector2i(2, 3)))
	_expect("点击放置寄生虫", grid.organ_count(), 1)

	# 2. 选中大脑，点击 (4,3) 放置
	grid.set_selected(lib[&"brain"])
	_click(grid, _cell_center(grid, Vector2i(4, 3)))
	_expect("点击放置大脑", grid.organ_count(), 2)

	if grid.organ_count() < 2:
		print("放置失败，终止测试")
		quit(1)
		return

	var organs := grid.organs()
	var parasite = organs[0]
	var brain = organs[1]

	# 3. 从寄生虫的神经接点拖到大脑的 nerve_in
	var p_nerve: Vector2 = parasite.node.position + parasite.node.port_center(&"nerve")
	var b_nerve: Vector2 = brain.node.position + brain.node.port_center(&"nerve_in")
	_drag(grid, p_nerve, b_nerve)
	_expect("拖拽建立神经线", grid._links.size(), 1)

	# 4. 再拖一次同样的连接 → 不应重复
	_drag(grid, p_nerve, b_nerve)
	_expect("重复拖拽不新增", grid._links.size(), 1)

	# 5. 拖到不同类型的接点 → 不建立
	var b_bone: Vector2 = brain.node.position + brain.node.port_center(&"bone")
	_drag(grid, p_nerve, b_bone)
	_expect("类型不符不连线", grid._links.size(), 1)

	# 6. Shift + 左键移除大脑 → 线被清理（中键已改为拖动平移）
	grid._gui_input(_shift_button(_cell_center(grid, Vector2i(4, 3)), true))
	grid._gui_input(_shift_button(_cell_center(grid, Vector2i(4, 3)), false))
	_expect("Shift+左键移除器官", grid.organ_count(), 1)
	_expect("移除后线被清理", grid._links.size(), 0)

	print("")
	print("全部通过" if _failed == 0 else "失败 %d 项" % _failed)
	quit(1 if _failed > 0 else 0)


func _cell_center(grid: AssemblyGrid, cell: Vector2i) -> Vector2:
	return grid._cell_rect(cell).get_center()


func _click(grid: AssemblyGrid, pos: Vector2) -> void:
	grid._gui_input(_motion(pos))
	grid._gui_input(_button(pos, true))
	grid._gui_input(_button(pos, false))


func _drag(grid: AssemblyGrid, from: Vector2, to: Vector2) -> void:
	grid._gui_input(_motion(from))
	grid._gui_input(_button(from, true))
	grid._gui_input(_motion(to))
	grid._gui_input(_button(to, false))


func _motion(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	return e


func _shift_button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := _button(pos, pressed, MOUSE_BUTTON_LEFT)
	e.shift_pressed = true
	return e


func _button(pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.button_index = button
	e.pressed = pressed
	return e


func _expect(title: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s %-24s 实际=%s 期望=%s" % ["✓" if ok else "✗", title, actual, expected])
