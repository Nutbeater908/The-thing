extends "res://tests/hatchery_motion_check.gd"
## Isolated one-leg hatchery entry. Fake RunState, no autoloads, no disk writes.
const OneLegBridge = preload("res://scripts/build/motion_test_bridge.gd")

class TestState extends "res://scripts/run/run_state.gd":
	var saves := 0
	func _ready() -> void:
		pass
	func save_session() -> void:
		saves += 1
	func load_session() -> bool:
		return false
	func preset_names() -> Array[String]:
		return []

var pose_debug := false

func observe() -> void:
	if not is_instance_valid(walker) or not walker.initialized:
		return
	for i in range(walker.leg_count()):
		var spec = walker.legs_spec[i]
		var upper_error: float = absf(walker.hips[i].distance_to(walker.knees[i]) - spec.upper_length)
		var lower_error: float = absf(walker.knees[i].distance_to(walker.feet[i]) - spec.lower_length)
		max_length_error = maxf(max_length_error, maxf(upper_error, lower_error))
		check(upper_error < 0.01 and lower_error < 0.01, "fixed per-leg bone lengths")
		check(segment_clear(walker.hips[i], walker.knees[i], walker.tuning.limb_radius), "upper limb intersects world")
		check(segment_clear(walker.knees[i], walker.feet[i], walker.tuning.limb_radius), "lower limb intersects world")
		check(walker.pose_clear[i], "full clearance queries stay safe leg %d" % i)
		if not walker.pose_clear[i] and not pose_debug:
			pose_debug = true
			var clearance: float = walker.tuning.limb_radius + walker.tuning.clearance
			printerr("POSE_DEBUG leg=", i, " hip=", walker.hips[i], " knee=", walker.knees[i], " foot=", walker.feet[i], " reachable=", walker._reachable(walker.hips[i], walker.feet[i], i), " upper=", walker._capsule_clear(walker.hips[i], walker.knees[i], clearance), " lower=", walker._capsule_clear(walker.knees[i], walker.feet[i], clearance), " foot_capsule=", walker._capsule_clear(walker.feet[i], walker.feet[i], walker.tuning.foot_radius))
		if walker.planted[i] and previous_planted.size() == walker.leg_count() and previous_planted[i] and walker.swing_leg != i and previous_swing != i:
			var drift: float = walker.feet[i].distance_to(previous_feet[i])
			max_stance_drift = maxf(max_stance_drift, drift)
			checked_stance_frames += 1
			check(drift < 0.02, "planted foot world drift")
		var points: Array[Vector2] = [walker.hips[i], walker.knees[i], walker.feet[i]]
		for s in range(2):
			var hit: CollisionShape2D = walker.hit_shapes[i * 2 + s]
			var axis := Vector2.DOWN.rotated(hit.global_rotation)
			var half: float = (hit.shape.height - hit.shape.radius * 2.0) * 0.5
			var error := maxf((hit.global_position - axis * half).distance_to(points[s]), (hit.global_position + axis * half).distance_to(points[s + 1]))
			max_hit_error = maxf(max_hit_error, error)
			check(error < 2.0, "moving hit capsules track solved bones")
	max_tilt = maxf(max_tilt, absf(walker.rotation))
	check(walker.pose_safety_failures == 0, "every hop pose has a safe swept route")
	previous_feet.assign(walker.feet)
	previous_planted.assign(walker.planted)
	previous_swing = walker.swing_leg

func one_leg_jump_check() -> void:
	var jumps: int = walker.jump_count
	var landings: int = walker.landing_count
	check(walker.request_jump(), "grounded one-leg jump accepted")
	var start_y: float = walker.global_position.y
	var min_y: float = start_y
	var flight := false
	for _frame in range(180):
		await tick(1)
		min_y = minf(min_y, walker.global_position.y)
		if walker.jump_phase in ["takeoff", "airborne_tuck", "descent"]:
			check(walker.last_support_accel == 0.0, "no flight support controller")
			if walker.support_count == 0:
				flight = true
		if walker.jump_phase == "standing" and walker.landing_count > landings:
			break
	check(walker.jump_count == jumps + 1 and walker.landing_count == landings + 1, "one impulse and actual landing")
	check(start_y - min_y > 35.0 and flight, "measured physical airborne clearance")
	check(walker.jump_phase == "standing" and walker.support_count == 1, "stable one-foot recovery")

func _run() -> void:
	check(get_root().get_child_count() == 0, "isolated no real autoload")
	var state := TestState.new()
	state.name = "RunState"
	state.credits = 500
	state.meta_credits = 7
	get_root().add_child(state)
	var build = load("res://scenes/build/build_screen.tscn").instantiate()
	get_root().add_child(build)
	current_scene = build
	await process_frame
	var grid: AssemblyGrid = build._grid
	var lib := OrganLibrary.catalog()
	# Symmetric ballast around a centered one-leg mount.
	for entry in [[&"fat", Vector2i(2, 1)], [&"fat", Vector2i(5, 1)], [&"heart", Vector2i(4, 2)], [&"brain", Vector2i(4, 0)], [&"parasite", Vector2i(3, 0)], [&"leg", Vector2i(4, 3)]]:
		check(grid.place(entry[1], lib[entry[0]], 0, true), "fixture organ placed")
	var organs := grid.organs()
	var fat_a = organs[0]
	var fat_b = organs[1]
	var heart = organs[2]
	var brain = organs[3]
	var parasite = organs[4]
	var leg = organs[5]
	link(grid, parasite, &"nerve", brain, &"nerve_in", OrganData.NERVE)
	link(grid, brain, &"nerve_out", leg, &"nerve", OrganData.NERVE)
	link(grid, heart, &"blood", brain, &"blood", OrganData.BLOOD)
	link(grid, heart, &"blood", leg, &"blood", OrganData.BLOOD)
	link(grid, heart, &"blood", fat_a, &"blood_a", OrganData.BLOOD)
	link(grid, heart, &"blood", fat_b, &"blood_a", OrganData.BLOOD)
	build._on_layout_changed()
	check(grid.result().alive, "one-leg assembly passes survival validation")
	var prepared := OneLegBridge.prepare(grid)
	check(prepared.errors.is_empty(), "one-leg assembly accepted: " + str(prepared.errors))
	if not prepared.errors.is_empty():
		build.free()
		state.free()
		quit(1)
		return
	var old_grid := grid_bytes(grid)
	var old_state := state_bytes(state)
	var saves: int = state.saves
	build._on_motion_test()
	lab = current_scene
	check(lab != build and lab.scene_file_path == "res://scenes/build/motion_test_room.tscn", "one-leg room entered")
	if lab == build:
		printerr(build.get_node("MotionTestError").dialog_text)
		build.free()
		state.free()
		quit(1)
		return
	walker = lab.walker
	check(walker.leg_count() == 1, "room uses one compiled leg")
	check(walker.hit_shapes.size() == 2, "one hit pair for one leg")
	check(walker.tuning.gait == 1 and walker.tuning.is_hop(), "one leg selects HOP gait")
	await tick(90)
	check(walker.support_count == 1 and walker.jump_phase == "standing", "one-leg assembly rests on real ground")
	var x: float = walker.position.x
	var hops_before: int = walker.hop_count
	walker.set_walk_intent(1.0)
	await tick(240)
	var right: float = walker.position.x - x
	var hops: int = walker.hop_count - hops_before
	check(right > 150.0, "one-leg assembly hops right")
	check(hops >= 3, "multiple hops from real assembly")
	walker.set_walk_intent(0.0)
	await tick(120)
	check(walker.jump_phase == "standing" and walker.support_count == 1, "settles on one foot")
	x = walker.position.x
	walker.set_walk_intent(-1.0)
	await tick(240)
	var reverse: float = x - walker.position.x
	check(reverse > 150.0, "one-leg assembly hops left")
	walker.set_walk_intent(0.0)
	await tick(120)
	await one_leg_jump_check()
	check(grid_bytes(grid) == old_grid and state_bytes(state) == old_state and state.saves == saves, "one-leg room never mutates grid/state or saves")
	lab.get_node("HUD/Panel/Box/Return").pressed.emit()
	walker = null
	await process_frame
	await process_frame
	check(current_scene == build and build.visible, "return restores build")
	check(grid_bytes(grid) == old_grid and state_bytes(state) == old_state and state.saves == saves, "one-leg roundtrip byte-identical")
	print("HATCHERY_SINGLE_LEG_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures, " right=", right, " reverse=", reverse, " hops=", hops, " stance_samples=", checked_stance_frames, " max_drift=", max_stance_drift, " bone_error=", max_length_error)
	build.free()
	state.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
