extends SceneTree
## 桥接层测试：新装配系统 → 关卡世界坐标。

var errors: Array[String] = []

func check(v: bool, label: String) -> void:
	if not v:
		errors.append(label)
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lib := PartsLibrary.catalog()
	var a := Assembly.new()
	check(a.add_root(lib[&"chassis"], Vector2.ZERO), "chassis placed")
	check(a.attach(lib[&"leg_standard"], 0, &"hip"), "leg attaches to hip")

	var body := AssemblyBridge.from_assembly(a, Vector2.ZERO)
	check(body.parts.size() == 2, "bridge yields 2 parts (got %d)" % body.parts.size())
	check(body.root_index == 0, "root index kept")
	check(body.parts[0].position == Vector2.ZERO, "root placed at origin")
	check(body.bounds.size.y >= 192.0, "bounds tall enough (%.0f)" % body.bounds.size.y)

	# hip 接口 = 机身 hip 偏移
	var hip: Vector2 = AssemblyBridge.socket_of(body, &"hip")
	var expect: Vector2 = lib[&"chassis"].socket(&"hip").offset
	check(hip.is_equal_approx(expect), "hip socket matches chassis offset (got %s)" % str(hip))

	# 腿的挂点应落在 hip 上
	var leg_anchor: Vector2 = body.parts[1].position + lib[&"leg_standard"].anchor.offset
	check(leg_anchor.is_equal_approx(hip), "leg anchor sits on the hip socket")

	# 平移 origin 后整体跟着走
	var moved := AssemblyBridge.from_assembly(a, Vector2(100, 50))
	check(moved.parts[0].position == Vector2(100, 50), "origin shifts the whole body")
	check(AssemblyBridge.socket_of(moved, &"hip").is_equal_approx(expect + Vector2(100, 50)),
		"hip socket shifts too")

	print("BRIDGE_CHECK ", "PASS" if errors.is_empty() else "FAIL", " failures=", errors)
	quit(0 if errors.is_empty() else 1)
