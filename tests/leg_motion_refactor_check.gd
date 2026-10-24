extends SceneTree
## Run in a minimal isolated project; frozen formulas prove compatibility at boundaries.
const IK = preload("res://scripts/labs/leg_kinematics.gd")
const HITS = preload("res://scenes/labs/leg_hitboxes.tscn")
const SEGMENTS = ["LeftUpper", "LeftLower", "RightUpper", "RightLower"]
var failures: Array[String] = []
var cases: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition and not failures.has(label):
		failures.append(label)
		printerr("FAIL ", label)

func legacy_angles(hip: Vector2, foot: Vector2, upper: float, lower: float) -> Dictionary:
	var delta := foot - hip
	var distance := clampf(delta.length(), absf(upper - lower) + 0.01, upper + lower - 0.01)
	var direction := atan2(-delta.x, delta.y)
	var spread := acos(clampf((upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance), -1.0, 1.0))
	var knee := PI - acos(clampf((upper * upper + lower * lower - distance * distance) / (2.0 * upper * lower), -1.0, 1.0))
	return {"hip": direction - spread, "knee": knee, "distance": distance, "reachable": absf(distance - delta.length()) < 0.02}

func legacy_points(hip: Vector2, target: Vector2, upper: float, lower: float, margin: float, bend: float) -> Array[Vector2]:
	var v := target - hip
	var d := clampf(v.length(), absf(upper - lower) + margin, upper + lower - margin)
	var axis := v.normalized() if v.length_squared() > 0.0 else Vector2.DOWN
	var a := (upper * upper - lower * lower + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, upper * upper - a * a))
	return [hip + axis * a + Vector2(axis.y, -axis.x) * h * bend, hip + axis * d]

func solver_checks() -> void:
	for lengths in [Vector2(40, 40), Vector2(80, 80), Vector2(35, 50), Vector2(70, 30)]:
		var upper: float = lengths.x
		var lower: float = lengths.y
		for margin in [0.01, 2.0, 4.0]:
			var inner: float = absf(upper - lower) + margin
			var outer: float = upper + lower - margin
			for distance in [0.0, 0.001, inner - 0.021, inner, inner + 0.021, (inner + outer) * 0.5, outer - 0.021, outer, outer + 0.021, upper + lower + 100.0]:
				for direction in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2(0.6, 0.8), Vector2(-0.6, -0.8)]:
					var hip := Vector2(123, -57)
					var target: Vector2 = hip + direction * distance
					var angles := IK.solve(hip, target, upper, lower)
					check(angles == legacy_angles(hip, target, upper, lower), "angle API exact legacy values and reach classification")
					for bend in [-1.0, 1.0]:
						cases += 1
						var points := IK.solve_points(hip, target, upper, lower, margin, bend)
						check(points == legacy_points(hip, target, upper, lower, margin, bend), "point API exact legacy values including zero-target fallback")
						check(absf(hip.distance_to(points[0]) - upper) < 0.001 and absf(points[0].distance_to(points[1]) - lower) < 0.001, "both branches retain bone lengths")
						if target != hip:
							var axis := (target - hip).normalized()
							check((points[0] - hip).dot(Vector2(axis.y, -axis.x)) * bend >= -0.0001, "selected bend branch")
						if margin == 0.01 and bend == 1.0 and target != hip:
							var knee := hip + Vector2.DOWN.rotated(angles.hip) * upper
							var foot := knee + Vector2.DOWN.rotated(angles.hip + angles.knee) * lower
							check(knee.distance_to(points[0]) < 0.001 and foot.distance_to(points[1]) < 0.001, "angle and point wrapper geometric equivalence")
	# Controller wrapper must forward the authoritative resource and blueprint branch.
	var controller = preload("res://scripts/labs/procedural_walker.gd").new()
	controller.tuning = load("res://resources/labs/procedural_walk.tres")
	var hip := Vector2(10, 20)
	var target := Vector2(20, 90)
	check(controller._solve(hip, target) == IK.solve_points(hip, target, controller.tuning.upper_length, controller.tuning.lower_length, controller.tuning.reach_margin), "controller point wrapper forwards unchanged tuning")
	controller.free()
	var adapter = preload("res://scripts/labs/blueprint_walker.gd").new()
	check(adapter.configure(load("res://resources/labs/blueprint_normal.tres")).is_empty(), "blueprint setup for branch wrapper")
	adapter.layout.legs[0].motion = adapter.layout.legs[0].motion.duplicate()
	adapter.layout.legs[0].motion.bend = -1
	check(adapter._solve(hip, target) == IK.solve_points(hip, target, adapter.tuning.upper_length, adapter.tuning.lower_length, adapter.tuning.reach_margin, -1.0), "blueprint reverse branch forwards unchanged")
	adapter.free()

func hit_contract(hits: Node) -> Array[Shape2D]:
	check(hits is Node2D and hits.top_level and hits.get_child_count() == 4, "fixed top-level four-segment scene structure")
	var resources: Array[Shape2D] = []
	for segment in SEGMENTS:
		var area := hits.get_node(segment) as Area2D
		check(area != null and area.collision_layer == 1024 and area.collision_mask == 0 and not area.monitoring and area.monitorable, "nonpushing queryable area contract")
		check(area.get_child_count() == 1, "one shape per segment")
		var shape := area.get_node("Shape") as CollisionShape2D
		check(shape != null and shape.shape is CapsuleShape2D and shape.shape.resource_local_to_scene and not shape.disabled, "authored enabled local capsule")
		check(not resources.has(shape.shape), "segments do not share mutable capsule")
		resources.append(shape.shape)
	return resources

func scene_checks() -> void:
	var first := HITS.instantiate()
	var second := HITS.instantiate()
	var a := hit_contract(first)
	var b := hit_contract(second)
	for i in range(a.size()):
		check(a[i] != b[i], "scene instances do not share mutable capsule")
	var previous: float = b[0].radius
	a[0].radius = previous + 3.0
	check(b[0].radius == previous, "mutating one rig leaves the other untouched")
	first.free()
	second.free()
	var procedural := preload("res://scenes/labs/procedural_walk_lab.tscn").instantiate()
	var procedural_hits := procedural.get_node("Walker/LegHits")
	check(procedural_hits.scene_file_path == HITS.resource_path, "procedural lab instances native hit scene")
	hit_contract(procedural_hits)
	var blueprint = preload("res://scripts/labs/blueprint_walker.gd").new()
	check(blueprint.configure(load("res://resources/labs/blueprint_normal.tres")).is_empty(), "blueprint config remains valid")
	check(blueprint.get_node("LegHits").scene_file_path == HITS.resource_path, "blueprint instances same native hit scene")
	hit_contract(blueprint.get_node("LegHits"))
	procedural.free()
	blueprint.free()

func _run() -> void:
	check(root.get_child_count() == 0, "no autoload or session access")
	solver_checks()
	scene_checks()
	print("LEG_MOTION_REFACTOR_CHECK ", "PASS" if failures.is_empty() else "FAIL", " cases=", cases, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
