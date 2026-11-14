extends SceneTree
## 骨骼层：脊柱 / 颅骨 / 整体式肢体单元的校验与解析。

var errors: Array[String] = []
var lib: Dictionary = {}

func check(value: bool, label: String) -> void:
	if not value:
		errors.append(label)
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _new_grid() -> AssemblyGrid:
	var g := AssemblyGrid.new()
	root.add_child(g)
	g.size = Vector2(1000, 800)
	return g

func _run() -> void:
	lib = OrganLibrary.catalog()
	check(lib.has(&"spine"), "spine exists")
	check(lib.has(&"skull"), "skull exists")
	check(lib.has(&"arm_standard"), "standard arm exists")
	check(lib.has(&"leg_standard"), "standard leg exists")
	if not lib.has(&"spine"):
		print("BONE_CHECK FAIL failures=", errors)
		quit(1)
		return

	check(lib[&"spine"].is_bone_root, "spine is the bone root")
	check(lib[&"skull"].bone_containment, "skull is a containment bone")
	check(lib[&"arm_standard"].unit_segments.size() == 2, "arm unit has 2 segments")

	# --- 合法骨架：脊柱 + 颅骨(含脑) + 臂挂在脊柱挂点上 ---
	var g := _new_grid()
	await process_frame
	g.place(Vector2i(0, 0), lib[&"spine"], 0, true)      # 脊柱 (0,0)-(0,3)
	g.place(Vector2i(0, -3), lib[&"skull"], 0, true)     # 颅骨 3x3，底边贴脊柱顶
	g.place(Vector2i(0, -3), lib[&"brain"], 0, true)     # 脑与颅骨同格（两层可重叠）
	g.place(Vector2i(1, 1), lib[&"arm_standard"], 0, true)  # 臂挂点 = 脊柱 (1,1) 挂点
	await process_frame

	var sk: Dictionary = g._check_skeleton()
	check(bool(sk.get("ok", false)), "skeleton check passes: %s" % str(sk.get("detail", "")))

	var units: Array = LimbChainBuilder.build_units(g)
	check(units.size() == 1, "one limb unit parsed (got %d)" % units.size())
	if units.size() == 1:
		var c = units[0]
		check(c.valid, "limb unit chain valid")
		check(c.segments.size() == 2, "chain has 2 segments")
		check(c.bind_action == &"attack", "chain binds attack")
		check(c.motion != null, "chain carries its own motion")
		check(c.body_anchor_cell == Vector2i(1, 1), "anchor cell is the spine attach point")

	# --- 脑跑出颅骨 ---
	var g2 := _new_grid()
	await process_frame
	g2.place(Vector2i(0, 0), lib[&"spine"], 0, true)
	g2.place(Vector2i(0, -3), lib[&"skull"], 0, true)
	g2.place(Vector2i(1, -3), lib[&"brain"], 0, true)     # 偏一格，超出颅骨
	await process_frame
	var sk2: Dictionary = g2._check_skeleton()
	check(not bool(sk2.get("ok", true)), "brain outside skull is rejected")
	# --- 没有脊柱 ---
	var g3 := _new_grid()
	await process_frame
	g3.place(Vector2i(0, -3), lib[&"skull"], 0, true)
	g3.place(Vector2i(0, -3), lib[&"brain"], 0, true)
	await process_frame
	var sk3: Dictionary = g3._check_skeleton()
	check(not bool(sk3.get("ok", true)), "missing spine is rejected")

	# --- 臂没挂在挂点上 ---
	var g4 := _new_grid()
	await process_frame
	g4.place(Vector2i(0, 0), lib[&"spine"], 0, true)
	g4.place(Vector2i(0, -3), lib[&"skull"], 0, true)
	g4.place(Vector2i(0, -3), lib[&"brain"], 0, true)
	g4.place(Vector2i(4, 1), lib[&"arm_standard"], 0, true)  # 离脊柱很远
	await process_frame
	var sk4: Dictionary = g4._check_skeleton()
	check(not bool(sk4.get("ok", true)), "arm off the attach points is rejected")

	print("BONE_CHECK ", "PASS" if errors.is_empty() else "FAIL", " failures=", errors)
	quit(0 if errors.is_empty() else 1)
