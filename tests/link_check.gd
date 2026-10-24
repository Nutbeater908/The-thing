## 拉线自检：连接规则、类型校验、器官移除后的清理。
##   godot --headless --path <项目> --script res://tests/link_check.gd
extends SceneTree

var _failed := 0


func _initialize() -> void:
	var lib := OrganLibrary.catalog()
	var grid := AssemblyGrid.new()
	grid.size = Vector2(900, 700)
	root.add_child(grid)

	var ok_parasite := grid.place(Vector2i(2, 3), lib[&"parasite"], 0)
	var ok_brain := grid.place(Vector2i(5, 3), lib[&"brain"], 0)
	var ok_leg := grid.place(Vector2i(7, 3), lib[&"leg"], 0)
	_expect("放置寄生虫", ok_parasite, true)
	_expect("放置大脑", ok_brain, true)
	_expect("放置腿", ok_leg, true)

	if grid.organs().size() < 3:
		print("放置失败，终止测试")
		quit(1)
		return

	var organs := grid.organs()
	var parasite = organs[0]
	var brain = organs[1]
	var leg = organs[2]

	# 1. 神经 → 神经
	var p_nerve := _endpoint(parasite, &"nerve", OrganData.NERVE)
	var b_nerve := _endpoint(brain, &"nerve_in", OrganData.NERVE)
	_expect("神经连神经", grid._try_link(p_nerve, b_nerve), true)
	_expect("线数量", grid._links.size(), 1)

	# 2. 重复连接
	_expect("重复连接被拒绝", grid._try_link(p_nerve, b_nerve), false)
	_expect("反方向重复也被拒绝", grid._try_link(b_nerve, p_nerve), false)

	# 3. 类型不同
	var b_blood := _endpoint(brain, &"blood", OrganData.BLOOD)
	_expect("神经连血流被拒绝", grid._try_link(p_nerve, b_blood), false)

	# 4. 同一器官
	var b_out := _endpoint(brain, &"nerve_out", OrganData.NERVE)
	_expect("同器官内连被拒绝", grid._try_link(b_nerve, b_out), false)

	# 5. 端点位置：tile.position + 接点在 tile 内的坐标
	var pos := grid.endpoint_pos(p_nerve)
	var expected: Vector2 = parasite.node.position + parasite.node.port_center(&"nerve")
	_expect("端点像素位置", pos, expected)

	# 6. 旋转后接点位置会跟着变（用不在原点的 nerve_out）
	var before := grid.endpoint_pos(_endpoint(brain, &"nerve_out", OrganData.NERVE))
	grid.rotate_at(Vector2i(5, 3))
	var after := grid.endpoint_pos(_endpoint(brain, &"nerve_out", OrganData.NERVE))
	_expect("旋转后端点位置改变", before != after, true)

	# 7. 移除器官后，相关线被清理
	grid.remove_at(Vector2i(5, 3))
	_expect("移除器官后线被清理", grid._links.size(), 0)

	print("")
	print("全部通过" if _failed == 0 else "失败 %d 项" % _failed)
	quit(1 if _failed > 0 else 0)


func _endpoint(organ, uid: StringName, type: int) -> AssemblyGrid.Endpoint:
	var ep := AssemblyGrid.Endpoint.new()
	ep.organ = organ
	ep.port_uid = uid
	ep.type = type
	return ep


func _expect(title: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s %-24s 实际=%s 期望=%s" % ["✓" if ok else "✗", title, actual, expected])
