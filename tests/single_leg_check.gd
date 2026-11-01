extends SceneTree
## Isolated single-leg HOP check. No autoloads, sessions, or disk writes.
var lab
var walker
var failures: Array[String] = []
var frames: int = 0
var max_length_error: float = 0.0
var max_stance_drift: float = 0.0
var max_tilt: float = 0.0
var previous_feet: Array[Vector2] = []
var previous_planted: Array[bool] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		printerr("FAIL frame=", frames, " ", message)

func tick(count: int) -> void:
	for _i in range(count):
		await physics_frame
		frames += 1
		observe()

func observe() -> void:
	if not is_instance_valid(walker) or walker.legs_spec.is_empty():
		return
	for i in range(walker.leg_count()):
		var spec = walker.legs_spec[i]
		var upper_error: float = absf(walker.hips[i].distance_to(walker.knees[i]) - spec.upper_length)
		var lower_error: float = absf(walker.knees[i].distance_to(walker.feet[i]) - spec.lower_length)
		max_length_error = maxf(max_length_error, maxf(upper_error, lower_error))
		check(upper_error < 0.01 and lower_error < 0.01, "fixed per-leg bone lengths")
		if walker.planted[i] and previous_planted.size() == walker.leg_count() and previous_planted[i] and walker.jump_phase == "standing":
			max_stance_drift = maxf(max_stance_drift, walker.feet[i].distance_to(previous_feet[i]))
	max_tilt = maxf(max_tilt, absf(walker.rotation))
	previous_feet.assign(walker.feet)
	previous_planted.assign(walker.planted)

func _run() -> void:
	check(get_root().get_child_count() == 0, "isolated test has no autoload/session access")
	lab = load("res://scenes/labs/single_leg_lab.tscn").instantiate()
	get_root().add_child(lab)
	walker = lab.get_node("Walker")
	await tick(90)
	check(walker.leg_count() == 1, "one leg from leg data")
	check(walker.hit_shapes.size() == 2, "one hit pair for one leg")
	check(walker.support_count == 1, "rests on the only foot")
	check(absf(walker.global_position.y - 464.0) < 3.0, "height controller holds rest height")
	var start_x: float = walker.global_position.x
	var hops_before: int = walker.hop_count
	walker.set_walk_intent(1.0)
	await tick(240)
	var right: float = walker.global_position.x - start_x
	var right_hops: int = walker.hop_count - hops_before
	print("HOP right=", right, " hops=", right_hops, " phase=", walker.jump_phase, " support=", walker.support_count)
	check(right > 150.0, "rightward hop travel")
	check(right_hops >= 3, "multiple automatic hops")
	walker.set_walk_intent(0.0)
	await tick(120)
	check(walker.jump_phase == "standing" and walker.support_count == 1, "settles on one foot after release")
	check(absf(walker.linear_velocity.x) < 2.0, "release brakes horizontally")
	start_x = walker.global_position.x
	hops_before = walker.hop_count
	walker.set_walk_intent(-1.0)
	await tick(240)
	var left: float = start_x - walker.global_position.x
	var left_hops: int = walker.hop_count - hops_before
	print("HOP reverse=", left, " hops=", left_hops)
	check(left > 150.0, "leftward hop travel")
	check(left_hops >= 3, "multiple reverse hops")
	walker.set_walk_intent(0.0)
	await tick(120)
	var jumps_before: int = walker.jump_count
	check(walker.request_jump(), "grounded full jump accepted")
	await tick(180)
	print("JUMP count=", walker.jump_count - jumps_before, " phase=", walker.jump_phase, " support=", walker.support_count)
	check(walker.jump_count == jumps_before + 1, "one full jump impulse")
	check(walker.jump_phase == "standing" and walker.support_count == 1, "full jump recovers on one foot")
	check(max_length_error < 0.01, "bone lengths conserved through hops")
	check(max_stance_drift < 0.05, "planted foot does not slide")
	check(max_tilt < 0.35, "torso stays upright through the hop cycle")
	print("SINGLE_LEG_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size(), " frames=", frames, " max_length_error=", max_length_error, " stance_drift=", max_stance_drift, " tilt=", max_tilt)
	quit(0 if failures.is_empty() else 1)
