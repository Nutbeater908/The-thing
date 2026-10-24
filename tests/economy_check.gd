## 经济公式与蓝图传递自检。
##   godot --headless --path <项目> --script res://tests/economy_check.gd
extends SceneTree

var _failed := 0


func _initialize() -> void:
	var lib := OrganLibrary.catalog()
	var leg: OrganData = lib[&"leg"]   # cost 15, max_hp 25

	# 拆除返还：健康全价，损伤按比例
	_expect("满血返还", OrganData.refund_value(leg, 25.0), 15)
	_expect("半血返还", OrganData.refund_value(leg, 12.5), 7)

	# 修复费用
	_expect("满血修复免费", OrganData.repair_cost(leg, 25.0), 0)
	_expect("半血修复费用", OrganData.repair_cost(leg, 12.5), 5)

	# 修复必须比重造便宜
	var repair := OrganData.repair_cost(leg, 12.5)
	var rebuild := leg.cost - OrganData.refund_value(leg, 12.5)
	_expect("修复比重造便宜", repair < rebuild, true)

	# 蓝图往返：损伤要保留
	var grid := _make_grid()
	grid.place(Vector2i(0, 0), lib[&"parasite"], 0)
	grid.place(Vector2i(1, 0), lib[&"brain"], 0)
	grid.organ_at(Vector2i(1, 0)).hp = 20.0

	# 一条神经线
	var ep_a := AssemblyGrid.Endpoint.new()
	ep_a.organ = grid.organ_at(Vector2i(0, 0))
	ep_a.port_uid = &"nerve"
	ep_a.type = OrganData.NERVE
	var ep_b := AssemblyGrid.Endpoint.new()
	ep_b.organ = grid.organ_at(Vector2i(1, 0))
	ep_b.port_uid = &"nerve_in"
	ep_b.type = OrganData.NERVE
	grid._try_link(ep_a, ep_b)

	var rs = load("res://scripts/run/run_state.gd").new()
	rs.save_from_grid(grid)
	_expect("保存器官数", rs.organs.size(), 2)
	_expect("保存损伤", rs.organs[1]["hp"], 20.0)
	_expect("保存拉线数", rs.links.size(), 1)

	var grid2 := _make_grid()
	rs.restore_to_grid(grid2)
	_expect("恢复器官数", grid2.organ_count(), 2)
	_expect("恢复损伤", grid2.organ_at(Vector2i(1, 0)).hp, 20.0)
	_expect("恢复拉线数", grid2.links().size(), 1)

	root.remove_child(grid)
	root.remove_child(grid2)
	grid.free()
	grid2.free()
	rs.free()

	print("")
	print("全部通过" if _failed == 0 else "失败 %d 项" % _failed)
	quit(1 if _failed > 0 else 0)


func _make_grid() -> AssemblyGrid:
	var grid := AssemblyGrid.new()
	grid.size = Vector2(900, 700)
	root.add_child(grid)
	if grid.result().is_empty():
		grid._revalidate()
	return grid


func _expect(title: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s %-22s 实际=%s 期望=%s" % ["✓" if ok else "✗", title, actual, expected])
