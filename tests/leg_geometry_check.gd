extends SceneTree
## 验证：腿部几何计算与实际标定一致。

var errors: Array[String] = []

func check(value: bool, label: String) -> void:
	if not value:
		errors.append(label)
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	test_leg_geometry_reads_pivots()
	test_leg_geometry_transforms_align()
	test_gait_controller_inits()
	test_gait_controller_stays_still_when_stopped()
	test_gait_controller_starts_swing_when_moving()
	
	if errors.is_empty():
		print("LEG_GEOMETRY_CHECK PASS")
		quit(0)
	else:
		print("LEG_GEOMETRY_CHECK FAIL")
		for e in errors:
			printerr("  ", e)
		quit(1)

func assert_not_null(value, label: String) -> void:
	check(value != null, label)

func assert_almost_eq(a: float, b: float, eps: float, label: String) -> void:
	check(absf(a - b) < eps, "%s (%.2f vs %.2f)" % [label, a, b])

func assert_gt(a: float, b: float, label: String) -> void:
	check(a > b, "%s (%.2f > %.2f)" % [label, a, b])

func assert_lt(a: float, b: float, label: String) -> void:
	check(a < b, "%s (%.2f < %.2f)" % [label, a, b])

func assert_eq(a, b, label: String) -> void:
	check(a == b, "%s (%s == %s)" % [label, str(a), str(b)])

func assert_ne(a, b, label: String) -> void:
	check(a != b, "%s (%s != %s)" % [label, str(a), str(b)])

func test_leg_geometry_reads_pivots() -> void:
	var lib := PartsLibrary.catalog()
	var leg: PartData = lib.get(&"leg_standard")
	assert_not_null(leg, "leg_standard exists")
	
	var spec := LegGeometry.from_part(leg)
	
	# 标定点读取
	assert_almost_eq(spec.hip.x, 24.0, 1.0, "hip x")
	assert_almost_eq(spec.hip.y, 24.0, 1.0, "hip y")
	assert_almost_eq(spec.knee_upper.x, 28.0, 1.0, "knee_upper x")
	assert_almost_eq(spec.knee_upper.y, 99.0, 1.0, "knee_upper y")
	assert_almost_eq(spec.knee_lower.x, 28.0, 1.0, "knee_lower x")
	assert_almost_eq(spec.knee_lower.y, 10.0, 1.0, "knee_lower y")
	
	# 骨长：髋→膝约75.1，膝→踝约110
	assert_gt(spec.upper_length, 70.0, "upper_length > 70")
	assert_lt(spec.upper_length, 80.0, "upper_length < 80")
	assert_gt(spec.lower_length, 105.0, "lower_length > 105")
	assert_lt(spec.lower_length, 115.0, "lower_length < 115")
	
	assert_gt(spec.total_length, 180.0, "total > 180")
	assert_lt(spec.total_length, 200.0, "total < 200")
	
	# 脚底偏移
	assert_gt(spec.foot_offset.y, 30.0, "foot_offset.y > 30")
	assert_lt(spec.foot_offset.y, 45.0, "foot_offset.y < 45")


func test_leg_geometry_transforms_align() -> void:
	var lib := PartsLibrary.catalog()
	var leg: PartData = lib.get(&"leg_standard")
	var spec := LegGeometry.from_part(leg)
	
	var hip := Vector2(100.0, 100.0)
	var ankle := Vector2(100.0, 280.0)  # 垂直向下
	
	var transforms := LegGeometry.compute_transforms(spec, hip, ankle)
	assert_eq(transforms.size(), 3, "three transforms")
	
	# 大腿起点应该是髋点
	var t0: Dictionary = transforms[0]
	assert_almost_eq(t0["position"].x, hip.x, 1.0, "thigh starts at hip x")
	assert_almost_eq(t0["position"].y, hip.y, 1.0, "thigh starts at hip y")
	
	# 小腿起点应该是膝点（大约在髋下方75px）
	var t1: Dictionary = transforms[1]
	assert_gt(t1["position"].y, hip.y + 70.0, "knee below hip")
	assert_lt(t1["position"].y, hip.y + 80.0, "knee not too far")
	
	# 脚起点应该是踝点（小腿起点下方约110px）
	var t2: Dictionary = transforms[2]
	assert_gt(t2["position"].y, t1["position"].y + 105.0, "ankle below knee")
	assert_lt(t2["position"].y, t1["position"].y + 115.0, "ankle not too far")
	
	# 脚保持水平
	assert_almost_eq(t2["rotation"], 0.0, 0.01, "foot horizontal")


func test_gait_controller_inits() -> void:
	var gait := GaitController.new()
	gait.init_stance(Vector2(100.0, 50.0), 150.0)
	
	# 初始化时双脚应该在髋点下方150px
	assert_almost_eq(gait.near_foot.x, 100.0, 1.0, "near foot x")
	assert_almost_eq(gait.near_foot.y, 200.0, 1.0, "near foot y")
	assert_almost_eq(gait.far_foot.x, 100.0, 1.0, "far foot x")
	assert_almost_eq(gait.far_foot.y, 200.0, 1.0, "far foot y")
	assert_eq(gait.state, GaitController.State.BOTH_GROUNDED, "grounded")


func test_gait_controller_stays_still_when_stopped() -> void:
	var gait := GaitController.new()
	gait.init_stance(Vector2(100.0, 50.0), 150.0)
	
	var feet := gait.update(0.1, Vector2(100.0, 50.0), Vector2.ZERO, true)
	
	# 静止时不应换步
	assert_almost_eq(feet["near"].x, 100.0, 1.0, "near unchanged")
	assert_almost_eq(feet["far"].x, 100.0, 1.0, "far unchanged")


func test_gait_controller_starts_swing_when_moving() -> void:
	var gait := GaitController.new()
	gait.init_stance(Vector2(100.0, 50.0), 150.0)
	gait.stride_length = 60.0
	
	# 髋点向前移动，触发某只脚迈步
	for i in 10:
		var feet := gait.update(0.05, Vector2(100.0 + i * 5.0, 50.0), Vector2(50.0, 0.0), true)
	
	# 应该有一只脚进入摆动状态
	assert_ne(gait.state, GaitController.State.BOTH_GROUNDED, "started swinging")
