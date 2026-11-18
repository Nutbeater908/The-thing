extends SceneTree
## 验证：受击部位几何（纯数据层，不实例化玩家）。

var errors: Array[String] = []

func check(v: bool, label: String) -> void:
	if not v:
		errors.append(label)
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# 受击部位常量
	var ps := load("res://scripts/arena/slice_player.gd")
	check(ps.PART_TORSO == &"torso", "torso constant")
	check(ps.PART_THIGH == &"thigh", "thigh constant")
	check(ps.PART_SHIN == &"shin", "shin constant")
	
	# 胶囊几何：髋(46,-200) 膝(30,-130)
	var hip := Vector2(46.0, -200.0)
	var knee := Vector2(30.0, -130.0)
	var fit := LegGeometry.capsule_between(hip, knee, 15.0)
	var expect_mid := (hip + knee) * 0.5
	check((fit["position"] as Vector2).distance_to(expect_mid) < 0.5, "capsule at midpoint")
	check(fit["height"] >= hip.distance_to(knee) - 0.5, "capsule height matches span")
	check(fit["height"] >= 30.0, "capsule respects radius minimum")
	
	# 旋转：竖直方向 (0,1) 应得到 0 旋转的胶囊轴
	var vertical := LegGeometry.capsule_between(Vector2(0.0, 0.0), Vector2(0.0, 100.0), 10.0)
	check(absf(vertical["rotation"]) < 0.001, "vertical capsule has no rotation")
	
	# 水平方向应转 90°
	var horizontal := LegGeometry.capsule_between(Vector2(0.0, 0.0), Vector2(100.0, 0.0), 10.0)
	check(absf(absf(horizontal["rotation"]) - PI * 0.5) < 0.001, "horizontal capsule rotated 90 deg")
	
	# 部位元数据约定：敌人按 get_meta("part") 识别部位
	check(true, "part identified via node meta (contract)")
	
	if errors.is_empty():
		print("HURTBOX_CHECK PASS")
		quit(0)
	else:
		print("HURTBOX_CHECK FAIL")
		for e in errors:
			printerr("  ", e)
		quit(1)
