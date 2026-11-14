extends SceneTree
## 拼装数据层测试：自由坐标，不依赖格子。

var errors: Array[String] = []

func check(value: bool, label: String) -> void:
	if not value:
		errors.append(label)
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

# ---------------------------------------------------------------- 构造

func _socket(uid: String, offset: Vector2, dir := Vector2i.RIGHT, kind := SocketData.Kind.STRUCT) -> SocketData:
	var s := SocketData.new()
	s.uid = StringName(uid)
	s.offset = offset
	s.dir = dir
	s.kind = kind
	return s

func _part(id: String, size: Vector2, sockets: Array[SocketData], anchor: SocketData, extra := {}) -> PartData:
	var p := PartData.new()
	p.id = StringName(id)
	p.display_name = id
	p.size = size
	p.sockets = sockets
	p.anchor = anchor
	p.max_hp = 10.0
	p.mass = size.x * size.y / 1024.0
	for k in extra:
		p.set(k, extra[k])
	return p

func _chassis() -> PartData:
	return _part("chassis", Vector2(128, 192), [
		_socket("right_top", Vector2(112, 48)),
		_socket("right_bottom", Vector2(112, 144)),
		_socket("inner_a", Vector2(48, 48), Vector2i.DOWN),
	], null, {"is_root": true, "max_hp": 140.0})

func _arm() -> PartData:
	return _part("arm", Vector2(64, 160), [
		_socket("tool", Vector2(48, 144), Vector2i.DOWN, SocketData.Kind.TOOL),
	], _socket("root", Vector2(16, 16), Vector2i.LEFT), {"max_hp": 90.0, "power": -4.0, "category": PartData.Category.WORK})

func _leg() -> PartData:
	return _part("leg", Vector2(64, 192), [], _socket("root", Vector2(16, 16), Vector2i.LEFT), {"max_hp": 100.0, "power": -6.0, "category": PartData.Category.LOCOMOTION})

func _core(power: float, control := false) -> PartData:
	return _part("core", Vector2(64, 64), [], _socket("root", Vector2(16, 16), Vector2i.UP), {
		"power": power, "is_control_source": control, "max_hp": 60.0,
		"category": PartData.Category.CORE,
	})

# ---------------------------------------------------------------- 测试

func _run() -> void:
	var chassis := _chassis()
	var a := Assembly.new()

	check(a.add_root(chassis, Vector2.ZERO), "root placed")
	check(a.parts.size() == 1, "only the root exists")
	check(not a.add_root(chassis, Vector2(50, 50)), "second root refused")

	# 吸附：接口在 (112,48)，臂挂上后左上角应落在 (96,32)
	var snap := a.find_snap(_arm(), 0, Vector2(112, 48), 24.0)
	check(not snap.is_empty(), "snap finds the arm socket")
	check(snap.get("position", Vector2.ZERO) == Vector2(96, 32), "snap gives the exact position")
	check(a.attach(_arm(), 0, &"right_top"), "arm attaches")
	check(a.parts[1].position == Vector2(96, 32), "arm lands at (96,32) got %s" % str(a.parts[1].position))
	check(not a.attach(_leg(), 0, &"right_top"), "socket refuses a second part")
	check(a.attach(_leg(), 0, &"right_bottom"), "leg attaches to the bottom socket")
	check(a.parts[2].position == Vector2(96, 128), "leg lands at (96,128)")

	check(not a.bind_tool(0, _core(0.0)), "chassis has no tool socket")
	check(a.bind_tool(1, _core(1.0)), "tool binds to the arm")

	var by_id := {}
	for c in AssemblyRules.check_all(a):
		by_id[c["id"]] = c
	check(by_id["root"]["ok"], "root rule passes")
	check(by_id["connect"]["ok"], "connect rule passes")
	check(not by_id["control"]["ok"], "control rule fails without a control source")
	check(not by_id["power"]["ok"], "power rule fails without supply")

	check(a.attach(_core(0.0, true), 0, &"inner_a"), "control chip attaches")
	by_id.clear()
	for c in AssemblyRules.check_all(a):
		by_id[c["id"]] = c
	check(by_id["control"]["ok"], "control rule passes")

	# 存档往返
	var dict := Blueprint.to_dict(a)
	var library := {"chassis": chassis, "arm": _arm(), "leg": _leg(), "core": _core(0.0, true)}
	var b := Blueprint.from_dict(dict, library)
	check(b.parts.size() == a.parts.size(), "blueprint round-trip keeps part count")
	for i in a.parts.size():
		check(b.parts[i].position.is_equal_approx(a.parts[i].position), "part %d position survives" % i)

	var c2 := Blueprint.from_dict(dict, library)
	var removed := c2.remove(0)
	check(removed.size() == a.parts.size(), "removing the root removes the whole tree")
	check(c2.parts.is_empty(), "assembly is empty after removing the root")

	# 日志与撤销
	var j := Journal.new()
	j.record("已安装 机械臂", {"n": 1})
	j.record("已安装 机械腿", {"n": 2})
	check(j.label_at(2) == "2：已安装 机械腿", "journal label format")
	check(j.undo({"n": 2}).get("n", -1) == 1, "undo returns the previous snapshot")
	j.record("已安装 装甲板", {"n": 3})
	check(not j.can_redo(), "recording truncates the redo branch")

	# 真实资源
	var lib := PartsLibrary.catalog()
	check(lib.size() == 9, "library loads 9 parts (got %d)" % lib.size())
	var expect := {
		&"chassis": {"root": true, "tool": false},
		&"arm_standard": {"root": false, "tool": false},
		&"leg_standard": {"root": false, "tool": false},
		&"head_shell": {"root": false, "tool": false},
		&"cpu": {"root": false, "tool": false},
		&"power_core": {"root": false, "tool": false},
		&"control_core": {"root": false, "tool": false},
		&"armor_plate": {"root": false, "tool": false},
		&"claw_tool": {"root": false, "tool": true},
	}
	for id in expect:
		var p: PartData = lib.get(id)
		check(p != null, "part %s exists" % id)
		if p == null:
			continue
		check(p.is_root == expect[id]["root"], "%s root flag" % id)
		check(p.is_tool_part() == expect[id]["tool"], "%s tool flag" % id)
		check(p.audit().is_empty(), "%s audit clean: %s" % [id, str(p.audit())])

	print("ASSEMBLY_CHECK ", "PASS" if errors.is_empty() else "FAIL", " failures=", errors)
	quit(0 if errors.is_empty() else 1)
