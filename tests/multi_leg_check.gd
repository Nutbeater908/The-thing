extends SceneTree
## Isolated four-leg wave-gait check. No autoloads, sessions, or disk writes.
var lab
var walker
var failures: Array[String] = []
var frames: int = 0
var max_length_error: float = 0.0
var max_stance_drift: float = 0.0
var max_tilt: float = 0.0
var previous_feet: Array[Vector2] = []
var previous_planted: Array[bool] = []
var previous_swing: int = -1

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
	if not is_instance_valid(walker) or not walker.initialized:
		return
	for i in range(walker.leg_count()):
		var spec = walker.legs_spec[i]
		var upper_error: float = absf(walker.hips[i].distance_to(walker.knees[i]) - spec.upper_length)
		var lower_error: float = absf(walker.knees[i].distance_to(walker.feet[i]) - spec.lower_length)
		max_length_error = maxf(max_length_error, maxf(upper_error, lower_error))
		check(upper_error < 0.01 and lower_error < 0.01, "fixed per-leg bone lengths")
		if walker.planted[i] and previous_planted.size() == walker.leg_count() and previous_planted[i] and walker.swing_leg != i and previous_swing != i and walker.jump_phase == "standing":
			var drift: float = walker.feet[i].distance_to(previous_feet[i])
			max_stance_drift = maxf(max_stance_drift, drift)
			check(drift < 0.02, "planted foot world drift")
	max_tilt = maxf(max_tilt, absf(walker.rotation))
	previous_feet.assign(walker.feet)
	previous_planted.assign(walker.planted)
	previous_swing = walker.swing_leg

func jump_check() -> void:
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
	check(walker.jump_phase == "standing" and walker.support_count == walker.leg_count(), "stable multi-foot recovery")

func _run() -> void:
	check(get_root().get_child_count() == 0, "isolated test has no autoload/session access")
	lab = load("res://scenes/labs/multi_leg_lab.tscn").instantiate()
	get_root().add_child(lab)
	walker = lab.get_node("Walker")
	await tick(90)
	check(walker.leg_count() == 4, "four legs from leg data")
	check(walker.hit_shapes.size() == 8, "one hit pair per leg")
	check(walker.support_count == 4, "rests on all four feet")
	check(absf(walker.global_position.y - 464.0) < 3.0, "height controller holds rest height")
	var start_x: float = walker.global_position.x
	walker.set_walk_intent(1.0)
	await tick(240)
	var right: float = walker.global_position.x - start_x
	var steps: int = walker.completed_steps.size()
	print("MULTI right=", right, " steps=", steps, " phase=", walker.jump_phase, " support=", walker.support_count)
	check(right > 150.0, "rightward multi-leg travel")
	check(steps >= 4, "multiple wave-gait steps")
	for i in range(1, steps):
		check(walker.completed_steps[i] != walker.completed_steps[i - 1], "steps do not repeat the same leg")
	walker.set_walk_intent(0.0)
	await tick(120)
	check(walker.jump_phase == "standing" and walker.support_count == 4, "settles on four feet")
	start_x = walker.global_position.x
	walker.set_walk_intent(-1.0)
	await tick(240)
	var reverse: float = start_x - walker.global_position.x
	print("MULTI reverse=", reverse)
	check(reverse > 150.0, "leftward multi-leg travel")
	walker.set_walk_intent(0.0)
	await tick(120)
	await jump_check()
	check(max_length_error < 0.01, "bone lengths conserved through multi-leg gait")
	check(max_stance_drift < 0.05, "planted feet do not slide")
	check(max_tilt < 0.35, "torso stays upright through multi-leg gait")
	print("MULTI_LEG_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size(), " frames=", frames, " max_length_error=", max_length_error, " stance_drift=", max_stance_drift, " tilt=", max_tilt)
	quit(0 if failures.is_empty() else 1)
