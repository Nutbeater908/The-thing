## 数据层自检：异形格子、接点、旋转。
##   godot --headless --path <项目> --script res://tests/organ_data_check.gd
extends SceneTree

var _failed := 0


func _initialize() -> void:
	var lib := OrganLibrary.catalog()
	print("器官数：", lib.size())

	for id in lib:
		var d: OrganData = lib[id]
		print("  %-8s %d 格  %d 接点  质量 %.1f" % [
			d.display_name, d.cells.size(), d.ports.size(), d.mass(),
		])

	# 1. 六种器官齐全
	_expect("器官数量", lib.size(), 6)

	# 价格与 HP 字段
	print("")
	for id in lib:
		var d: OrganData = lib[id]
		print("  %-8s 价格 %2d  HP %d" % [d.display_name, d.cost, int(d.max_hp)])
	_expect("大脑价格", lib[&"brain"].cost, 25)
	_expect("寄生虫免费", lib[&"parasite"].cost, 0)
	_expect("心脏 HP", lib[&"heart"].max_hp, 30.0)
	print("")

	# 2. 形状各异的器官
	var leg: OrganData = lib[&"leg"]
	var fat: OrganData = lib[&"fat"]
	var brain: OrganData = lib[&"brain"]
	_expect("腿是 3 格直条", leg.cells.size(), 3)
	_expect("脂肪是 2×2", fat.bounds(0), Rect2i(0, 0, 2, 2))
	_expect("大脑是 1×2", brain.bounds(0), Rect2i(0, 0, 1, 2))

	# 3. 旋转：1×3 竖条转 90° 变 3×1 横条
	var rc := leg.rotated_cells(1)
	var bb := _bounds_of(rc)
	_expect("腿旋转后包围盒", bb, Rect2i(-2, 0, 3, 1))

	# 4. 转四次回到原位
	var rc4 := leg.rotated_cells(4)
	_expect("旋转 360° 回到原形", _sorted(rc4), _sorted(leg.cells))

	# 5. 接点跟着旋转：腿的接点在 (0,0)，转 90° 后应在 (0,0)
	var rp := leg.rotated_ports(1)
	_expect("接点数量不变", rp.size(), 3)
	_expect("接点随形旋转", rp[0].cell, Vector2i(0, 0))

	# 6. 接点类型
	var types := {}
	for p in leg.ports:
		types[p.type] = true
	_expect("腿同时有神经/血流/骨骼", types.size(), 3)

	print("")
	print("全部通过" if _failed == 0 else "失败 %d 项" % _failed)
	quit(1 if _failed > 0 else 0)


func _bounds_of(cells: Array[Vector2i]) -> Rect2i:
	var lo := cells[0]
	var hi := cells[0]
	for c in cells:
		lo.x = mini(lo.x, c.x)
		lo.y = mini(lo.y, c.y)
		hi.x = maxi(hi.x, c.x)
		hi.y = maxi(hi.y, c.y)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _sorted(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out := cells.duplicate()
	out.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


func _expect(title: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s %-22s 实际=%s 期望=%s" % ["✓" if ok else "✗", title, actual, expected])
