## 背包自检：异形放置、容量、拖拽、快照往返。
##   godot --headless --path <项目> --script res://tests/backpack_check.gd
extends SceneTree

const STEP := BackpackPanel.CELL + BackpackPanel.GAP

var _failed := 0


func _initialize() -> void:
	var lib := OrganLibrary.catalog()
	var pack := BackpackPanel.new()
	root.add_child(pack)

	_expect("初始为空", pack.is_empty(), true)

	_expect("放入寄生虫", pack.add_organ(lib[&"parasite"]), true)   # 1 格
	_expect("放入大脑", pack.add_organ(lib[&"brain"]), true)        # 2 格
	_expect("放入爪", pack.add_organ(lib[&"claw"]), true)           # 3 格
	_expect("三件物品", pack.items().size(), 3)

	# 已占 6 格，剩 3 格；脂肪 2×2 放不下
	_expect("脂肪放不下", pack.add_organ(lib[&"fat"]), false)

	# 拖拽：把 (0,0) 的寄生虫拖到 (2,0)
	var from := Vector2(STEP * 0.5, STEP * 0.5)
	var to := Vector2(STEP * 2.5, STEP * 0.5)
	pack._gui_input(_button(from, true))
	pack._gui_input(_motion(to))
	pack._gui_input(_button(to, false))

	var parasite := pack.take_at(Vector2i(2, 0))
	_expect("拖到新位置", parasite.is_empty(), false)
	_expect("拖拽后剩余", pack.items().size(), 2)
	pack.add_organ(parasite["organ"], parasite["hp"])

	# 快照往返
	var snap := pack.snapshot()
	_expect("快照条目", snap.size(), 3)

	var pack2 := BackpackPanel.new()
	root.add_child(pack2)
	pack2.restore(snap)
	_expect("恢复条目", pack2.items().size(), 3)

	# 满格时无法再放
	var pack3 := BackpackPanel.new()
	root.add_child(pack3)
	for i in 9:
		pack3.add_organ(lib[&"parasite"])
	_expect("九格填满", pack3.items().size(), 9)
	_expect("满格拒绝", pack3.add_organ(lib[&"parasite"]), false)

	print("")
	print("全部通过" if _failed == 0 else "失败 %d 项" % _failed)
	quit(1 if _failed > 0 else 0)


func _button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	return e


func _motion(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	return e


func _expect(title: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s %-22s 实际=%s 期望=%s" % ["✓" if ok else "✗", title, actual, expected])
