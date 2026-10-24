## 修复工具自检。
##   godot --headless --path <项目> --script res://tests/repair_check.gd
extends SceneTree

var _failed := 0


func _initialize() -> void:
	var lib := OrganLibrary.catalog()
	var grid := _make_grid()
	var rs = load("res://scripts/run/run_state.gd").new()
	rs.credits = 100
	grid.economy = rs

	grid.place(Vector2i(0, 0), lib[&"leg"], 0)   # cost 15, max_hp 25
	var p = grid.organ_at(Vector2i(0, 0))
	p.hp = 12.5

	# 单件修复
	var before: int = rs.credits
	var ok := grid.repair_at(Vector2i(0, 0))
	_expect("修复成功", ok, true)
	_expect("修复后满血", p.hp, 25.0)
	_expect("修复扣费", before - rs.credits, 5)

	# 满血时修复不花钱
	before = rs.credits
	_expect("满血无需修复", grid.repair_at(Vector2i(0, 0)), false)
	_expect("满血不扣费", rs.credits, before)

	# 全部修复
	p.hp = 5.0
	var expected := OrganData.repair_cost(p.data, 5.0)
	_expect("全部修复预览", grid.repair_all_cost(), expected)

	before = rs.credits
	_expect("全部修复成功", grid.repair_all(), true)
	_expect("全部修复后满血", p.hp, 25.0)
	_expect("全部修复扣费", before - rs.credits, expected)

	# 余额不足
	rs.credits = 0
	p.hp = 10.0
	_expect("余额不足修复失败", grid.repair_at(Vector2i(0, 0)), false)
	_expect("余额不足不改变 HP", p.hp, 10.0)

	root.remove_child(grid)
	grid.free()
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
