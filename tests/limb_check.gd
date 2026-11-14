extends SceneTree
## 当前模型：机身（根）+ 头壳 + 处理器 + 电源 + 主控 + 整体式机械臂/腿。

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
	g.size = Vector2(1200, 900)
	return g

func _ep(organ, uid: StringName, type: int) -> AssemblyGrid.Endpoint:
	var e := AssemblyGrid.Endpoint.new()
	e.organ = organ
	e.port_uid = uid
	e.type = type
	return e

func _run() -> void:
	lib = OrganLibrary.catalog()
	check(lib.has(&"torso"), "torso exists")
	check(lib[&"torso"].is_bone_root, "torso is the bone root")
	check(lib[&"arm_standard"].unit_segments.size() == 2, "arm unit has 2 segments")
	check(lib[&"leg_standard"].bind_action == &"", "leg unit has no attack binding")

	var g := _new_grid()
	await process_frame
	g.place(Vector2i(0, 0), lib[&"torso"], 0, true)
	g.place(Vector2i(0, -3), lib[&"skull"], 0, true)
	g.place(Vector2i(0, -3), lib[&"brain"], 0, true)
	g.place(Vector2i(0, 1), lib[&"heart"], 0, true)
	g.place(Vector2i(2, 1), lib[&"parasite"], 0, true)
	g.place(Vector2i(3, 1), lib[&"arm_standard"], 0, true)
	g.place(Vector2i(3, 4), lib[&"leg_standard"], 0, true)
	# 工具绑定到臂的工具口（不占格）
	var arm_placed = g.organ_at(Vector2i(3, 1))
	check(arm_placed != null, "arm placed on the torso socket")
	check(arm_placed.data.tool_socket, "arm exposes a tool socket")
	check(g.bind_tool(arm_placed, lib[&"claw_tool"]), "claw binds to the arm")
	await process_frame

	var sk: Dictionary = g._check_skeleton()
	check(bool(sk.get("ok", false)), "skeleton check passes: %s" % str(sk.get("detail", "")))

	var units: Array = LimbChainBuilder.build_units(g)
	check(units.size() == 2, "two limb units parsed (got %d)" % units.size())
	var arm = null
	for c in units:
		if c.bind_action == &"attack":
			arm = c
	check(arm != null, "an attacking limb unit exists")
	if arm != null:
		check(arm.segments.size() == 3, "arm chain = 2 segments + tool (got %d)" % arm.segments.size())
		check(arm.motion != null, "arm carries its own motion")
		check(arm.body_anchor_cell == Vector2i(3, 1), "arm anchor is the torso socket")
		var tip_seg = arm.segments[arm.segments.size() - 1]
		check(tip_seg.is_tip and tip_seg.tip_damage > 0.0, "tool provides the damage")

	# 两骨 IK：脚应在目标点，膝在中间（腿朝下，膝朝前 = +x）
	var pts := LegIk.solve_points(Vector2(0, 0), Vector2(0, 150), 120.0, 90.0, 1.0)
	check(pts.size() == 3, "ik returns hip/knee/foot")
	check(absf(pts[2].y - 150.0) < 0.5, "ik foot reaches the target")
	check(pts[1].x > 1.0, "knee bends forward with bend=+1")

	# 瞄准：基准角跟着目标走
	var rig := LimbRig.new()
	root.add_child(rig)
	rig.setup(arm, arm.motion, Vector2.ZERO)
	rig.use_aim = true
	rig.aim_world = Vector2(600.0, -120.0)
	rig._physics_process(1.0 / 60.0)
	check(rig._locked_base_deg < -5.0, "aiming up-right gives a negative base (%.0f°)" % rig._locked_base_deg)
	var tip: Vector2 = rig._points[rig._points.size() - 1]
	check(tip.x > 20.0 and tip.y < 0.0, "arm points up-right at the aim")

	var fast := rig.compute_damage(2500.0)
	var slow := rig.compute_damage(400.0)
	check(fast > slow, "faster impact deals more damage (%.1f > %.1f)" % [fast, slow])

	print("LIMB_CHECK ", "PASS" if errors.is_empty() else "FAIL", " failures=", errors)
	quit(0 if errors.is_empty() else 1)
