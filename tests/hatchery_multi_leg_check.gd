extends "res://tests/hatchery_single_leg_check.gd"
## Isolated four-leg hatchery entry. Fake RunState, no autoloads, no disk writes.
const MultiBridge = preload("res://scripts/build/motion_test_bridge.gd")

class MultiState extends "res://scripts/run/run_state.gd":
	var saves := 0
	func _ready() -> void:
		pass
	func save_session() -> void:
		saves += 1
	func load_session() -> bool:
		return false
	func preset_names() -> Array[String]:
		return []

func multi_leg_jump_check() -> void:
	var jumps: int = walker.jump_count
	var landings: int = walker.landing_count
	check(walker.request_jump(), "grounded four-leg jump accepted")
	var start_y: float = walker.global_position.y
	var min_y: float = start_y
	var flight := false
	for _frame in range(200):
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
	await tick(90)
	check(walker.jump_phase == "standing" and walker.support_count == walker.leg_count(), "stable four-foot recovery")

func _run() -> void:
	check(get_root().get_child_count() == 0, "isolated no real autoload")
	var state := MultiState.new()
	state.name = "RunState"
	state.credits = 800
	state.meta_credits = 11
	get_root().add_child(state)
	var build = load("res://scenes/build/build_screen.tscn").instantiate()
	get_root().add_child(build)
	current_scene = build
	await process_frame
	var grid: AssemblyGrid = build._grid
	var lib := OrganLibrary.catalog()
	# Four legs in a row under the two 2x2 fats; two hearts cover the blood demand.
	for entry in [[&"fat", Vector2i(1, 1)], [&"fat", Vector2i(3, 1)], [&"heart", Vector2i(5, 2)], [&"heart", Vector2i(0, 1)], [&"brain", Vector2i(5, 0)], [&"parasite", Vector2i(4, 0)], [&"leg", Vector2i(1, 3)], [&"leg", Vector2i(2, 3)], [&"leg", Vector2i(3, 3)], [&"leg", Vector2i(4, 3)]]:
		check(grid.place(entry[1], lib[entry[0]], 0, true), "fixture organ placed")
	var organs := grid.organs()
	var fat_a = organs[0]
	var fat_b = organs[1]
	var heart = organs[2]
	var heart_aux = organs[3]
	var brain = organs[4]
	var parasite = organs[5]
	var legs := [organs[6], organs[7], organs[8], organs[9]]
	link(grid, parasite, &"nerve", brain, &"nerve_in", OrganData.NERVE)
	for leg in legs:
		link(grid, brain, &"nerve_out", leg, &"nerve", OrganData.NERVE)
		link(grid, heart, &"blood", leg, &"blood", OrganData.BLOOD)
	link(grid, heart, &"blood", brain, &"blood", OrganData.BLOOD)
	link(grid, heart, &"blood", fat_a, &"blood_a", OrganData.BLOOD)
	link(grid, heart, &"blood", fat_b, &"blood_a", OrganData.BLOOD)
	link(grid, heart_aux, &"blood", brain, &"blood", OrganData.BLOOD)
	build._on_layout_changed()
	check(grid.result().alive, "four-leg assembly passes survival validation")
	var prepared := MultiBridge.prepare(grid)
	check(prepared.errors.is_empty(), "four-leg assembly accepted: " + str(prepared.errors))
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
	check(lab != build and lab.scene_file_path == "res://scenes/build/motion_test_room.tscn", "four-leg room entered")
	if lab == build:
		printerr(build.get_node("MotionTestError").dialog_text)
		build.free()
		state.free()
		quit(1)
		return
	walker = lab.walker
	check(walker.leg_count() == 4, "room uses four compiled legs")
	check(walker.hit_shapes.size() == 8, "one hit pair per leg")
	check(walker.tuning.gait == 0 and not walker.tuning.is_hop(), "four legs select alternating gait")
	await tick(90)
	check(walker.support_count == 4 and walker.jump_phase == "standing", "four-leg assembly rests on real ground")
	var x: float = walker.position.x
	walker.set_walk_intent(1.0)
	await tick(240)
	var right: float = walker.position.x - x
	var steps: int = walker.completed_steps.size()
	check(right > 150.0, "four-leg assembly walks right")
	check(steps >= 4, "multiple wave-gait steps from real assembly")
	for i in range(1, steps):
		check(walker.completed_steps[i] != walker.completed_steps[i - 1], "consecutive steps use different legs")
	walker.set_walk_intent(0.0)
	await tick(120)
	check(walker.jump_phase == "standing" and walker.support_count == 4, "settles on four feet")
	x = walker.position.x
	walker.set_walk_intent(-1.0)
	await tick(240)
	var reverse: float = x - walker.position.x
	check(reverse > 150.0, "four-leg assembly walks left")
	walker.set_walk_intent(0.0)
	await tick(120)
	await multi_leg_jump_check()
	check(grid_bytes(grid) == old_grid and state_bytes(state) == old_state and state.saves == saves, "four-leg room never mutates grid/state or saves")
	lab.get_node("HUD/Panel/Box/Return").pressed.emit()
	walker = null
	await process_frame
	await process_frame
	check(current_scene == build and build.visible, "return restores build")
	check(grid_bytes(grid) == old_grid and state_bytes(state) == old_state and state.saves == saves, "four-leg roundtrip byte-identical")
	print("HATCHERY_MULTI_LEG_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures, " right=", right, " reverse=", reverse, " steps=", steps, " stance_samples=", checked_stance_frames, " max_drift=", max_stance_drift, " bone_error=", max_length_error)
	build.free()
	state.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
