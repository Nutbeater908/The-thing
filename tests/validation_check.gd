## 存活校验自检：控制链、血路、结构。
##   godot --headless --path <项目> --script res://tests/validation_check.gd
extends SceneTree

const N := OrganData.NERVE
const B := OrganData.BLOOD

var _failed := 0
var _lib: Dictionary


func _initialize() -> void:
	_lib = OrganLibrary.catalog()

	_case_empty()
	_case_only_parasite()
	_case_complete()
	_case_missing_nerve()
	_case_blood_shortage()

	print("")
	print("全部通过" if _failed == 0 else "失败 %d 项" % _failed)
	quit(1 if _failed > 0 else 0)


func _case_empty() -> void:
	var grid := _make_grid()
	var r := grid.result()
	_expect("空盘不存活", r["alive"], false)
	_expect("空盘没有检查项", r["checks"].size(), 0)
	_free_grid(grid)


func _case_only_parasite() -> void:
	var grid := _make_grid()
	grid.place(Vector2i(0, 0), _lib[&"parasite"], 0)
	var r := grid.result()
	_expect("只有寄生虫不存活", r["alive"], false)
	_expect("缺大脑", _check(r, "control")["ok"], false)
	_expect("缺心脏", _check(r, "blood")["ok"], false)
	_expect("单体结构成立", _check(r, "structure")["ok"], true)
	_free_grid(grid)


func _case_complete() -> void:
	var grid := _make_grid()
	_build_base(grid)
	_add_leg(grid, Vector2i(2, 0), true, true)
	var r := grid.result()
	_expect("完整构造存活", r["alive"], true)
	_expect("控制链通过", _check(r, "control")["ok"], true)
	_expect("血路通过", _check(r, "blood")["ok"], true)
	_expect("结构通过", _check(r, "structure")["ok"], true)
	_free_grid(grid)


func _case_missing_nerve() -> void:
	var grid := _make_grid()
	_build_base(grid)
	_add_leg(grid, Vector2i(2, 0), false, true)
	var r := grid.result()
	_expect("腿没神经不存活", r["alive"], false)
	_expect("控制链失败", _check(r, "control")["ok"], false)
	_free_grid(grid)


func _case_blood_shortage() -> void:
	var grid := _make_grid()
	_build_base(grid)
	for i in 5:
		_add_leg(grid, Vector2i(2 + i, 0), true, true)
	var r := grid.result()
	_expect("五条腿供血不足", r["alive"], false)
	_expect("血路失败", _check(r, "blood")["ok"], false)
	_expect("结构仍然成立", _check(r, "structure")["ok"], true)
	_free_grid(grid)


# ---------------------------------------------------------------- 构造辅助

## 寄生虫 (0,0) + 大脑 (1,0) + 心脏 (0,1)，并接好神经与血流
func _build_base(grid: AssemblyGrid) -> void:
	grid.place(Vector2i(0, 0), _lib[&"parasite"], 0)
	grid.place(Vector2i(1, 0), _lib[&"brain"], 0)
	grid.place(Vector2i(0, 1), _lib[&"heart"], 0)

	var organs := grid.organs()
	var parasite = organs[0]
	var brain = organs[1]
	var heart = organs[2]

	grid._try_link(_ep(parasite, &"nerve", N), _ep(brain, &"nerve_in", N))
	grid._try_link(_ep(heart, &"blood", B), _ep(brain, &"blood", B))


## 在 anchor 放一条腿；按需把神经/血流接到大脑
func _add_leg(grid: AssemblyGrid, anchor: Vector2i, nerve: bool, blood: bool) -> void:
	var before := grid.organ_count()
	grid.place(anchor, _lib[&"leg"], 0)
	if grid.organ_count() == before:
		return

	var organs := grid.organs()
	var leg = organs[organs.size() - 1]
	var brain = organs[1]

	if nerve:
		grid._try_link(_ep(brain, &"nerve_out", N), _ep(leg, &"nerve", N))
	if blood:
		grid._try_link(_ep(brain, &"blood", B), _ep(leg, &"blood", B))


func _ep(organ, uid: StringName, type: int) -> AssemblyGrid.Endpoint:
	var e := AssemblyGrid.Endpoint.new()
	e.organ = organ
	e.port_uid = uid
	e.type = type
	return e


func _make_grid() -> AssemblyGrid:
	var grid := AssemblyGrid.new()
	grid.size = Vector2(900, 700)
	root.add_child(grid)
	# SceneTree._initialize 阶段，首个节点入树时 _ready 可能尚未触发
	if grid.result().is_empty():
		grid._revalidate()
	return grid


func _free_grid(grid: AssemblyGrid) -> void:
	root.remove_child(grid)
	grid.free()


func _check(result: Dictionary, id: String) -> Dictionary:
	for c in result["checks"]:
		if c["id"] == id:
			return c
	return {}


func _expect(title: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s %-24s 实际=%s 期望=%s" % ["✓" if ok else "✗", title, actual, expected])
