extends SceneTree
## Run only in a minimal dependency-preserving copy, without the real project's autoloads.
var lab
var walker
var failures: Array[String] = []
var frames: int = 0
var checked_stance_frames: int = 0
var max_stance_drift: float = 0.0
var max_length_error: float = 0.0
var max_hit_error: float = 0.0
var max_tilt: float = 0.0
var previous_feet: Array[Vector2] = []
var previous_planted: Array[bool] = []
var previous_swing: int = -1
var inspect: bool = true
var monitor_stance: bool = true

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		printerr("FAIL frame=", frames, " ", message)
		if is_instance_valid(walker):
			printerr("position=", walker.global_position, " hips=", walker.hips, " knees=", walker.knees, " feet=", walker.feet, " planted=", walker.planted, " swing=", walker.swing_leg)

func tick(count: int) -> void:
	for _i in range(count):
		await physics_frame
		frames += 1
		if inspect and walker.initialized:
			observe()

func observe() -> void:
	var t = walker.tuning
	for i in range(2):
		var upper_error: float = absf(walker.hips[i].distance_to(walker.knees[i]) - t.upper_length)
		var lower_error: float = absf(walker.knees[i].distance_to(walker.feet[i]) - t.lower_length)
		max_length_error = maxf(max_length_error, maxf(upper_error, lower_error))
		check(upper_error < 0.01 and lower_error < 0.01, "fixed bone lengths")
		# Independent capsule query from actual solved segments; do not trust pose_clear.
		check(segment_clear(walker.hips[i], walker.knees[i], t.limb_radius), "upper limb intersects world")
		check(segment_clear(walker.knees[i], walker.feet[i], t.limb_radius), "lower limb intersects world")
		check(segment_clear(walker.feet[i], walker.feet[i], t.foot_radius), "foot intersects world")
		check(walker.pose_clear[i], "full clearance queries stay safe")
		if monitor_stance and previous_feet.size() == 2 and walker.planted[i] and previous_planted[i] and walker.swing_leg != i and previous_swing != i:
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
	check(walker.pose_safety_failures == 0, "every jump pose has a safe swept route")
	check(walker.last_support_accel <= t.max_support_accel + 0.01, "support force bounded")
	check(absf(walker.last_horizontal_accel) <= t.max_horizontal_accel + 0.01, "motion force bounded")
	previous_feet.assign(walker.feet)
	previous_planted.assign(walker.planted)
	previous_swing = walker.swing_leg

func segment_clear(a: Vector2, b: Vector2, radius: float) -> bool:
	var shape := CapsuleShape2D.new()
	shape.radius = radius
	shape.height = a.distance_to(b) + radius * 2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D((b - a).angle() - PI / 2.0, (a + b) * 0.5)
	query.collision_mask = 256
	return lab.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func clear_history() -> void:
	previous_feet.clear()
	previous_planted.clear()

func reset() -> void:
	clear_history()
	walker.reset_walker()
	await tick(90)
	check(walker.global_position.distance_to(Vector2(640, 464)) < 3.0, "reset restores spawn and stable support")
	check(walker.completed_steps.is_empty() and walker.walk_intent == 0.0, "reset clears gait and intent")

func jump_check(label: String) -> void:
	var start_y: float = walker.global_position.y
	var start_x: float = walker.global_position.x
	var before: int = walker.jump_count
	var landings: int = walker.landing_count
	check(walker.request_jump(), label + " accepts grounded request")
	var min_y := start_y
	var max_crouch := start_y
	var peak_foot_clearance := 0.0
	var first_foot_clearance := 10000.0
	var peak_rise_speed := 0.0
	var peak_landing_speed := 0.0
	var rising := false
	var flight := false
	var contact_landing := false
	var landing_low := -10000.0
	var phases: Array[String] = []
	for _frame in range(240):
		await tick(1)
		if not phases.has(walker.jump_phase):
			phases.append(walker.jump_phase)
		min_y = minf(min_y, walker.global_position.y)
		if walker.jump_phase == "crouch":
			max_crouch = maxf(max_crouch, walker.global_position.y)
		if walker.jump_phase in ["takeoff", "airborne_tuck", "descent"]:
			rising = rising or walker.linear_velocity.y < -100.0
			check(walker.last_support_accel == 0.0, label + " no flight support controller")
			if walker.support_count == 0 and walker.jump_phase == "airborne_tuck":
				flight = true
				var clearance: float = 550.0 - maxf(walker.feet[0].y, walker.feet[1].y) - walker.tuning.foot_radius
				first_foot_clearance = minf(first_foot_clearance, clearance)
				peak_foot_clearance = maxf(peak_foot_clearance, clearance)
				peak_rise_speed = maxf(peak_rise_speed, -walker.linear_velocity.y)
				check(not walker.request_jump(), label + " denies airborne repeat")
		if walker.jump_phase == "landing":
			contact_landing = contact_landing or walker.support_count > 0
			landing_low = maxf(landing_low, walker.global_position.y)
			peak_landing_speed = maxf(peak_landing_speed, walker.linear_velocity.y)
			check(walker.landing_start_height < walker.global_position.y + 2.0, label + " cushioning begins after contact")
		if walker.jump_phase == "standing" and walker.landing_count > landings:
			break
	print("JUMP ", label, " rise=", start_y - min_y, " crouch=", max_crouch - start_y, " peak_foot_clearance=", peak_foot_clearance, " first_tuck_clearance=", first_foot_clearance, " peak_rise_speed=", peak_rise_speed, " peak_landing_speed=", peak_landing_speed, " travel_x=", walker.global_position.x - start_x, " landing_low=", landing_low, " phases=", phases, " safety_rejections=", walker.pose_safety_rejections)
	check(walker.jump_count == before + 1 and walker.landing_count == landings + 1, label + " one impulse and actual landing")
	check(start_y - min_y > 35.0 and rising and flight and peak_foot_clearance > 40.0 and first_foot_clearance > 2.0, label + " measured physical airborne clearance")
	check(max_crouch - start_y > 4.0 and contact_landing and landing_low > start_y + 4.0, label + " crouch and contact cushioning")
	check(phases.has("airborne_tuck") and phases.has("descent") and phases.has("recover"), label + " full pose sequence")
	check(walker.jump_phase == "standing" and walker.support_count > 0 and absf(walker.linear_velocity.y) < 12.0, label + " stable recovery")

func _run() -> void:
	check(get_root().get_child_count() == 0, "isolated test has no autoload/session access")
	var controller = load("res://scripts/labs/procedural_walker.gd")
	var tuning_script = load("res://scripts/labs/procedural_walk_tuning.gd")
	if controller == null or not controller.can_instantiate() or tuning_script == null or not tuning_script.can_instantiate():
		printerr("PROCEDURAL_WALK_CHECK FAIL: script parse/load")
		quit(2)
		return
	lab = load("res://scenes/labs/procedural_walk_lab.tscn").instantiate()
	get_root().add_child(lab)
	walker = lab.get_node("Walker")
	await tick(90)
	check(walker.support_count == 2, "rest has two real reachable contacts")
	check(absf(walker.global_position.y - 464.0) < 3.0, "one height controller holds rest height")
	for jump_index in range(3):
		await jump_check("standing_%d" % (jump_index + 1))
		await tick(30)
	walker.set_walk_intent(1.0)
	await tick(60)
	var steps_before_jump: int = walker.completed_steps.size()
	await jump_check("moving")
	var resume_x: float = walker.global_position.x
	await tick(120)
	var resume_distance: float = walker.global_position.x - resume_x
	print("RESUME steps_before=", steps_before_jump, " steps_after=", walker.completed_steps.size(), " distance=", resume_distance, " speed=", walker.linear_velocity.x)
	# Existing alternating gait brakes briefly between strides: measure motion over time, not one frame's speed.
	check(walker.completed_steps.size() > steps_before_jump + 1 and resume_distance > 130.0, "moving jump resumes gait")
	await reset()
	var start_x: float = walker.global_position.x
	walker.set_walk_intent(1.0)
	await tick(240)
	var right_distance: float = walker.global_position.x - start_x
	var right_steps: int = walker.completed_steps.size()
	print("RIGHT distance=", right_distance, " steps=", walker.completed_steps, " rejected=", walker.rejected_steps, " aborted=", walker.aborted_steps)
	check(right_distance > 250.0, "real rightward motion")
	check(right_steps >= 6, "multiple completed rightward steps")
	for i in range(1, right_steps):
		check(walker.completed_steps[i] != walker.completed_steps[i - 1], "steps alternate")
	walker.set_walk_intent(0.0)
	await tick(90)
	var stop_x: float = walker.global_position.x
	var stopped_steps: int = walker.completed_steps.size()
	await tick(60)
	check(absf(walker.linear_velocity.x) < 0.5 and absf(walker.global_position.x - stop_x) < 1.0, "release stops torso")
	check(walker.completed_steps.size() == stopped_steps and walker.swing_leg == -1, "stop settles ongoing step without continuous stepping")
	check(checked_stance_frames > 300 and max_stance_drift < 0.02, "substantial world-planted stance coverage")
	# Reverse without reset, then test reset separately.
	start_x = walker.global_position.x
	walker.set_walk_intent(-1.0)
	await tick(240)
	var left_distance: float = start_x - walker.global_position.x
	print("LEFT distance=", left_distance, " total_steps=", walker.completed_steps.size(), " rejected=", walker.rejected_steps, " aborted=", walker.aborted_steps)
	check(left_distance > 250.0, "real leftward motion after reversal")
	check(walker.completed_steps.size() >= right_steps + 6, "multiple completed leftward steps")
	for i in range(1, walker.completed_steps.size()):
		check(walker.completed_steps[i] != walker.completed_steps[i - 1], "steps alternate across reversal")
	await reset()
	# A finite angular perturbation must recover through finite torque, not a lock.
	walker.angular_velocity = 1.0
	await tick(120)
	check(not walker.lock_rotation and absf(walker.rotation) < 0.03, "finite upright stabilizer recovers")
	# The optional block must actually exist in the physics world.
	lab.set_block_enabled(true)
	await tick(3)
	var ray := PhysicsRayQueryParameters2D.create(Vector2(810, 500), Vector2(810, 570), 256)
	var hit: Dictionary = lab.get_world_2d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider == lab.get_node("Block") and absf(hit.position.y - 532.0) < 0.01, "toggle exposes real block collider")
	# Endpoint-only ground rays cannot detect this shin intersection: both points are outside.
	check(not walker.limb_clear(Vector2(765, 490), Vector2(830, 545)), "whole limb query rejects an obstructed shin")
	walker.set_walk_intent(1.0)
	await tick(240)
	print("BLOCK position=", walker.global_position, " steps=", walker.completed_steps, " rejected=", walker.rejected_steps, " aborted=", walker.aborted_steps)
	check(walker.rejected_steps + walker.aborted_steps > 0 or walker.global_position.x > 842.0, "obstacle either safely traversed or invalid steps rejected")
	check(walker.global_position.y < 500.0, "obstacle does not collapse reachable support")
	walker.set_walk_intent(0.0)
	lab.set_block_enabled(false)
	await reset()
	# Remove all reachable ground: there must be gravity, not an invisible support plane.
	monitor_stance = false
	inspect = false
	lab.get_node("Ground/Shape").set_deferred("disabled", true)
	await tick(4)
	var airborne_y: float = walker.global_position.y
	await tick(24)
	check(walker.support_count == 0 and walker.last_support_accel == 0.0, "no foot contact means zero support force")
	check(not walker.request_jump() and walker.jump_count == 0, "unsupported natural fall denies jump")
	check(walker.global_position.y > airborne_y + 40.0 and walker.linear_velocity.y > 250.0, "unsupported torso falls under real gravity")
	# Physical torso collision, independently of IK support: ground on, far below leg reach.
	lab.get_node("Ground/Shape").set_deferred("disabled", false)
	await tick(180)
	check(walker.global_position.y <= 534.0 and absf(walker.linear_velocity.y) < 2.0, "actual torso shape collides with ground")
	inspect = true
	monitor_stance = true
	await reset()
	check(max_tilt < 0.3, "torso stays upright within finite stabilization")
	print("METRICS frames=", frames, " stance_samples=", checked_stance_frames, " max_stance_drift=", max_stance_drift, " max_length_error=", max_length_error, " max_hit_endpoint_error=", max_hit_error, " max_tilt=", max_tilt)
	print("PROCEDURAL_WALK_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	lab.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
