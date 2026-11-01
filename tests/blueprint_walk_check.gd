extends "res://tests/procedural_walk_check.gd"
## Inherit independent bone/world/stance/hit checks and full jump acceptance thresholds.
const SPEC = preload("res://scripts/labs/blueprint_walk_spec.gd")
var reports: Array[Dictionary] = []

func rejected(spec: Resource, label: String) -> void:
	check(not spec.compile().errors.is_empty(), label)

func data_checks() -> void:
	var normal = load("res://resources/labs/blueprint_normal.tres")
	var expected_com := [Vector2(64.0 / 14.0, 96.0 / 14.0), Vector2(112.0 / 14.0, 96.0 / 14.0), Vector2(-64.0 / 14.0, 96.0 / 14.0)]
	# Independent worksheet: 14 unit cells; normal sum(x,y)=(4,6), sum(x²+y²)=52.
	# moved mount: sums=(7,6), squared sum=61; shifted fat: sums=(-4,6), squared sum=60.
	var squared_sums := [52.0, 61.0, 60.0]
	for i in range(3):
		var fixture = lab.FIXTURES[i]
		var compiled: Dictionary = fixture.compile()
		check(compiled.errors.is_empty(), "fixture compiles %d" % i)
		if not compiled.errors.is_empty():
			continue
		check(compiled.mass == 14.0, "handcomputed 14kg total")
		check(compiled.com.distance_to(expected_com[i]) < 0.0001, "handcomputed COM %d" % i)
		var expected_inertia: float = squared_sums[i] * 256.0 - 14.0 * expected_com[i].length_squared() + 14.0 * 256.0 / 6.0
		check(absf(compiled.inertia - expected_inertia) < 0.01, "handcomputed inertia %d" % i)
		check(compiled.fixed.size() == 8, "eight fixed cells, no six leg cells welded into torso")
		check(compiled.legs[0].mount == Vector2(-16, 8) and compiled.legs[1].mount == Vector2(32 if i == 1 else 16, 8), "explicit lower-edge mounts %d" % i)
	var broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.organs.remove_at(5)
	var one_leg: Dictionary = broken.compile()
	check(one_leg.errors.is_empty() and one_leg.legs.size() == 1, "one supported downward leg compiles")
	broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.organs.append(broken.organs[5].duplicate(true))
	rejected(broken, "reject overlapping duplicate leg")
	broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.organs[5].rotation = 1
	rejected(broken, "reject sideways rotated leg")
	broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.organs[5].motion = null
	rejected(broken, "never infer missing mount from ports/cells")
	broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.organs[5].motion.mount = Vector2(0.1, -0.5)
	rejected(broken, "reject detached mount")
	broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.organs[0].data.mass_per_cell = NAN
	rejected(broken, "reject nonfinite organ mass")
	broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.organs[5].motion.upper_length = INF
	rejected(broken, "reject nonfinite bone length")
	broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.organs[0].anchor = Vector2i(100, 0)
	rejected(broken, "reject disconnected fixed torso")
	broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	broken.organs[0].anchor = Vector2i(0, 0)
	rejected(broken, "reject reference overlap")
	# Rotation acts on BOTH explicit direction/mount and cells. A locally upward
	# definition rotated 180 degrees is a supported downward definition.
	broken = normal.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var entry: Dictionary = broken.organs[5]
	entry.data = entry.data.duplicate(true)
	entry.data.cells.assign([Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, -2)])
	entry.motion = entry.motion.duplicate(true)
	entry.motion.organ = entry.data
	entry.motion.mount = Vector2(0, 0.5)
	entry.motion.direction = Vector2.UP
	entry.rotation = 2
	var rotated: Dictionary = broken.compile()
	check(rotated.errors.is_empty(), "explicit rotated definition remains downward")
	if rotated.errors.is_empty():
		check(rotated.legs[1].mount.is_equal_approx(Vector2(16, 8)), "rotation transforms explicit mount")

func rig_checks(index: int) -> void:
	check(walker.get_script() == preload("res://scripts/labs/blueprint_walker.gd"), "shared inherited adapter")
	check(walker.mass == 14.0 and walker.center_of_mass_mode == RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM, "actual physical custom mass/COM")
	check(walker.center_of_mass.distance_to(walker.layout.com) < 0.0001, "physical COM in unchanged local layout frame")
	check(walker.hips[1].distance_to(walker.global_transform * Vector2(32 if index == 1 else 16, 8)) < 0.01, "actual solved hip follows selected mount")
	for i in range(2):
		if walker.planted[i]:
			var ray := PhysicsRayQueryParameters2D.create(walker.feet[i] + Vector2.UP * 2.0, walker.feet[i] + Vector2.DOWN * 10.0, 256)
			var hit: Dictionary = lab.get_world_2d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty() and hit.collider == lab.get_node("Ground") and absf(hit.position.y - 550.0) < 0.001, "planted feet have independently measured real ground")
	var collider_count := 0
	# Hand-authored expected cell set, independent of compiler metadata.
	var expected_cells: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0)]
	var fat_x := -2 if index == 2 else 0
	for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		expected_cells.append(Vector2i(fat_x, -2) + offset)
	for child in walker.get_children():
		if child is CollisionShape2D:
			collider_count += 1
			var grid: Vector2i = child.get_meta("grid_cell")
			check(expected_cells.has(grid), "collider belongs to independent expected cell set")
			expected_cells.erase(grid)
			check(child.position == Vector2(grid) * 16.0 and child.shape.size == Vector2(16, 16), "exact cell collider transform")
			check(child.get_meta("organ_index") < 4 and child.get_parent() == walker, "only fixed organ shapes owned by torso")
	check(expected_cells.is_empty() and collider_count == 8 and walker.get_shape_owners().size() == 8, "eight compound torso shapes without capsule proxy")
	# Rigid shape owner positions must be the authored layout, not COM-recentered twice.
	for owner_id in walker.get_shape_owners():
		var owner = walker.shape_owner_get_owner(owner_id)
		check(walker.shape_owner_get_transform(owner_id).origin == owner.position, "physics shape owner uses true local cell frame")
	for shape in walker.hit_shapes:
		check(shape.get_parent() is Area2D and shape.get_parent().collision_layer == 1024, "moving leg shapes are nonpushing hit Areas")
	var pose := Transform2D(0.2, Vector2(100, 200))
	check(walker._hip(pose, 0).distance_to(pose * Vector2(-16, 8)) < 0.001, "gait transforms true local mount")
	check(absf(walker._rest_foot_x(Transform2D.IDENTITY, 1) - (38.0 if index == 1 else 22.0)) < 0.001, "moved mount moves neutral foot workspace")

func _run() -> void:
	check(get_root().get_child_count() == 0, "isolated no autoload/session")
	lab = load("res://scenes/labs/blueprint_walk_lab.tscn").instantiate()
	get_root().add_child(lab)
	data_checks()
	for index in range(3):
		clear_history()
		lab.select_blueprint(index)
		walker = lab.walker
		check(is_instance_valid(walker), "valid fixture creates rig")
		if not is_instance_valid(walker):
			continue
		await tick(90)
		rig_checks(index)
		check(walker.support_count == 2 and walker.jump_phase == "standing", "fixture stable two-foot support")
		var x: float = walker.position.x
		walker.set_walk_intent(1.0)
		await tick(240)
		var distance: float = walker.position.x - x
		var steps: int = walker.completed_steps.size()
		check(distance > 250.0 and steps >= 6, "fixture right walk >250px and six steps")
		for s in range(1, steps):
			check(walker.completed_steps[s] != walker.completed_steps[s - 1], "fixture alternating gait")
		walker.set_walk_intent(0.0)
		await tick(90)
		check(absf(walker.linear_velocity.x) < 0.5, "fixture stops")
		await jump_check("blueprint_%d" % index)
		var right_x: float = walker.position.x
		walker.set_walk_intent(-1.0)
		await tick(240)
		var reverse: float = right_x - walker.position.x
		check(reverse > 250.0, "fixture left reverse >250px")
		walker.set_walk_intent(0.0)
		await tick(60)
		check(not walker.limb_clear(Vector2(640, 540), Vector2(680, 590)), "world shape query rejects floor penetration")
		reports.append({"fixture": index, "mass": walker.mass, "com": walker.center_of_mass, "inertia": walker.inertia, "right": distance, "reverse": reverse, "steps": steps, "jumps": walker.jump_count, "safety_failures": walker.pose_safety_failures})
		var old_id: int = walker.get_instance_id()
		clear_history()
		lab._on_reset_pressed()
		walker = lab.walker
		check(walker.get_instance_id() != old_id and walker.position == Vector2(640, 464) and walker.walk_intent == 0.0, "reset replaces whole rig at spawn")
		await tick(90)
		check(walker.completed_steps.is_empty() and walker.jump_count == 0 and walker.support_count == 2, "new rig has clean gait/support")
		# Finite angular perturbation exercises custom COM/inertia, not rotation lock.
		walker.angular_velocity = 1.0
		await tick(120)
		check(not walker.lock_rotation and absf(walker.rotation) < 0.03, "compound rig finite upright recovery")
		# Turn off only leg world sensing, not body collision. The exact fixed-cell
		# compound must physically stop the otherwise unsupported falling torso.
		inspect = false
		walker.tuning.ground_mask = 0
		await tick(180)
		check(walker.support_count == 0 and walker.last_support_accel == 0.0, "no synthetic support with leg queries off")
		check(walker.position.y > 538.0 and walker.position.y <= 543.0 and absf(walker.linear_velocity.y) < 2.0, "actual compound cell torso collides with ground")
		inspect = true
	# Rejection must be visible with no fallback rig.
	var bad = lab.FIXTURES[0].duplicate(true)
	bad.organs.remove_at(5)
	bad.organs.remove_at(4)
	lab.replace_rig(bad)
	walker = null
	await process_frame
	await process_frame
	check(lab.walker == null and lab.status.text.begins_with("REJECTED:"), "unsupported layout visibly rejects without default biped")
	print("BLUEPRINT_REPORTS ", reports)
	print("METRICS frames=", frames, " stance_samples=", checked_stance_frames, " drift=", max_stance_drift, " length_error=", max_length_error, " hit_error=", max_hit_error, " tilt=", max_tilt)
	print("BLUEPRINT_WALK_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	lab.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
