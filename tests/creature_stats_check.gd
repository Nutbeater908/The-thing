## 作用向量与质心自检。
##   godot --headless --path <项目> --script res://tests/creature_stats_check.gd
extends SceneTree

var _failed := 0
var _lib: Dictionary


func _initialize() -> void:
	_lib = OrganLibrary.catalog()

	_case_basic()
	_case_rotated_leg()
	_case_two_legs()

	print("")
	print("全部通过" if _failed == 0 else "失败 %d 项" % _failed)
	quit(1 if _failed > 0 else 0)


func _case_basic() -> void:
	var grid := _make_grid()
	grid.place(Vector2i(0, 0), _lib[&"parasite"], 0)
	grid.place(Vector2i(1, 0), _lib[&"brain"], 0)
	grid.place(Vector2i(0, 1), _lib[&"heart"], 0)
	grid.place(Vector2i(2, 0), _lib[&"leg"], 0)

	var stats := CreatureStats.from_grid(grid)
	_near("总质量", stats.mass, 7.0)
	_near("质心 x", stats.centroid.x, 8.0 / 7.0)
	_near("质心 y", stats.centroid.y, 5.0 / 7.0)
	_expect("腿数量", stats.legs().size(), 1)
	_expect("支撑腿数量", stats.support_legs().size(), 1)
	_expect("横向腿数量", stats.side_legs().size(), 0)
	_near("支撑腿总长", stats.support_power(), 3.0)
	_expect("转动惯量大于零", stats.inertia() > 0.0, true)

	var leg: CreatureStats.Limb = stats.legs()[0]
	_near("腿根部 x", float(leg.anchor.x), 2.0)
	_near("腿伸展方向 x", leg.direction.x, 0.0)
	_near("腿伸展方向 y", leg.direction.y, 1.0)

	# 腿向下伸 → 向上蹬；按上才有速度，按右没有
	_near("按上速度", stats.speed_for(Vector2.UP), 3.0 / 7.0 * 150.0)
	_near("按右速度", stats.speed_for(Vector2.RIGHT), 0.0)

	# 单腿在质心右侧，向上推会产生负扭矩
	_expect("单侧腿产生扭矩", stats.torque_for(Vector2.UP) < 0.0, true)

	_free_grid(grid)


func _case_rotated_leg() -> void:
	var grid := _make_grid()
	grid.place(Vector2i(0, 0), _lib[&"parasite"], 0)
	grid.place(Vector2i(3, 0), _lib[&"leg"], 1)   # 顺时针 90°，腿向左伸

	var stats := CreatureStats.from_grid(grid)
	_near("旋转后腿方向 x", stats.legs()[0].direction.x, -1.0)
	_near("旋转后腿方向 y", stats.legs()[0].direction.y, 0.0)
	_expect("按右可以走", stats.speed_for(Vector2.RIGHT) > 0.0, true)
	_near("按上走不动", stats.speed_for(Vector2.UP), 0.0)
	_expect("旋转腿不算支撑腿", stats.support_legs().size(), 0)
	_expect("旋转腿算横向腿", stats.side_legs().size(), 1)

	_free_grid(grid)


func _case_two_legs() -> void:
	var grid := _make_grid()
	grid.place(Vector2i(0, 0), _lib[&"parasite"], 0)
	grid.place(Vector2i(1, 0), _lib[&"leg"], 0)
	grid.place(Vector2i(4, 0), _lib[&"leg"], 0)

	var stats := CreatureStats.from_grid(grid)
	_near("两条腿推力叠加", stats.push_for(Vector2.UP).length(), 6.0)
	_near("两条腿总质量", stats.mass, 7.0)
	_near("两条腿速度", stats.speed_for(Vector2.UP), 6.0 / 7.0 * 150.0)
	_near("两条支撑腿总长", stats.support_power(), 6.0)

	_free_grid(grid)


# ---------------------------------------------------------------- 工具

func _make_grid() -> AssemblyGrid:
	var grid := AssemblyGrid.new()
	grid.size = Vector2(900, 700)
	root.add_child(grid)
	if grid.result().is_empty():
		grid._revalidate()
	return grid


func _free_grid(grid: AssemblyGrid) -> void:
	root.remove_child(grid)
	grid.free()


func _expect(title: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s %-24s 实际=%s 期望=%s" % ["✓" if ok else "✗", title, actual, expected])


func _near(title: String, actual: float, expected: float) -> void:
	var ok := absf(actual - expected) < 0.01
	if not ok:
		_failed += 1
	print("%s %-24s 实际=%.3f 期望=%.3f" % ["✓" if ok else "✗", title, actual, expected])
