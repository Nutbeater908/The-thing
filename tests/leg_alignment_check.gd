extends SceneTree
## 验证：关卡里腿部各段接头处保持重合。

var errors: Array[String] = []

func check(value: bool, label: String) -> void:
	if not value:
		errors.append(label)
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lib := PartsLibrary.catalog()
	var assembly := Assembly.new()
	assembly.add_root(lib[&"chassis"], Vector2.ZERO)
	assembly.attach(lib[&"leg_standard"], 0, &"hip", 0)
	
	var bridge := AssemblyBridge.from_assembly(assembly, Vector2.ZERO)
	var spec := LegGeometry.from_part(lib[&"leg_standard"])
	
	# 髋点位置
	var hip := AssemblyBridge.socket_of(bridge, &"hip")
	check(hip.length() > 0.0, "hip position valid")
	
	# 站立时踝点应该在髋点下方约185px（腿长）
	var ankle := hip + Vector2(0.0, spec.total_length)
	
	# 计算三段变换
	var transforms := LegGeometry.compute_transforms(spec, hip, ankle)
	check(transforms.size() == 3, "three transforms")
	
	# 大腿起点 = 髋点
	var t0: Dictionary = transforms[0]
	var thigh_start: Vector2 = t0["position"]
	check(thigh_start.distance_to(hip) < 0.5, "thigh starts at hip")
	
	# 膝点：大腿变换后的 knee_upper
	var knee_from_thigh := thigh_start + (spec.knee_upper - spec.hip).rotated(t0["rotation"])
	
	# 小腿起点应该等于膝点
	var t1: Dictionary = transforms[1]
	var shin_start: Vector2 = t1["position"]
	var knee_gap := shin_start.distance_to(knee_from_thigh)
	check(knee_gap < 0.5, "knee joint aligned (gap=%.2f)" % knee_gap)
	
	# 踝点：小腿变换后的 ankle_shin
	var ankle_from_shin := shin_start + (spec.ankle_shin - spec.knee_lower).rotated(t1["rotation"])
	
	# 脚起点应该等于踝点
	var t2: Dictionary = transforms[2]
	var foot_start: Vector2 = t2["position"]
	var ankle_gap := foot_start.distance_to(ankle_from_shin)
	check(ankle_gap < 0.5, "ankle joint aligned (gap=%.2f)" % ankle_gap)
	
	# 脚底应该贴地
	var foot_bottom := foot_start.y + spec.foot_offset.y
	var expected_ground := hip.y + spec.total_length + spec.foot_offset.y
	var ground_gap := absf(foot_bottom - expected_ground)
	check(ground_gap < 1.0, "foot on ground (gap=%.2f)" % ground_gap)
	
	if errors.is_empty():
		print("LEG_ALIGNMENT_CHECK PASS")
		quit(0)
	else:
		print("LEG_ALIGNMENT_CHECK FAIL")
		for e in errors:
			printerr("  ", e)
		quit(1)
