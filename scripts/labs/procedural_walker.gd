extends RigidBody2D
const IK = preload("res://scripts/labs/leg_kinematics.gd")
## One physical body; kinematic, non-pushing limb hit areas. No other motion controller.
@export var tuning: Resource
var walk_intent: float = 0.0
var feet: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var knees: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var hips: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var planted: Array[bool] = [false, false]
var last_ground: Array[float] = [0.0, 0.0]
var swing_leg: int = -1
var next_leg: int = 0
var swing_time: float = 0.0
var swing_from: Vector2
var swing_to: Vector2
var cooldown: float = 0.0
var initialized: bool = false
var reset_requested: bool = false
var spawn_pose: Transform2D
var support_count: int = 0
var completed_steps: Array[int] = []
var step_starts: int = 0
var rejected_steps: int = 0
var aborted_steps: int = 0
var last_support_accel: float = 0.0
var last_horizontal_accel: float = 0.0
var pose_clear: Array[bool] = [true, true]
var space: PhysicsDirectSpaceState2D
var jump_phase: String = "standing"
var phase_time: float = 0.0
var jump_requested: bool = false
var jump_count: int = 0
var landing_count: int = 0
var rejected_jumps: int = 0
var pose_safety_rejections: int = 0
var pose_safety_failures: int = 0
var landing_start_height: float = 0.0

func request_jump() -> bool:
	# Requests are consumed in the physics callback and revalidated against the world.
	if jump_phase != "standing" or support_count == 0 or jump_requested:
		rejected_jumps += 1
		return false
	jump_requested = true
	return true

func _set_phase(value: String) -> void:
	jump_phase = value
	phase_time = 0.0

func _real_support(pose: Transform2D) -> int:
	var count := 0
	for i in range(2):
		if planted[i] and _contact(feet[i]) and limb_clear(_hip(pose, i), feet[i]):
			count += 1
	return count

func _air_leg(pose: Transform2D, leg: int, distance: float, dt: float, can_land: bool) -> void:
	var hip := _hip(pose, leg)
	var old_hip := hips[leg]
	var old_foot := feet[leg]
	var desired := hip + Vector2.DOWN * distance
	var hit := _ground(hip.x, hip.y) if can_land else {}
	# Only acquire a surface the extending foot actually reaches this frame, never a remote ray hit.
	if not hit.is_empty() and hit.foot.y <= desired.y and _reachable(hip, hit.foot):
		desired = hit.foot
	var candidate := old_foot.move_toward(desired, tuning.jump_pose_speed * dt + hip.distance_to(old_hip))
	if _sweep_clear(old_hip, old_foot, hip, candidate):
		feet[leg] = candidate
	else:
		pose_safety_rejections += 1
		# Body motion is physical and cannot be rolled back by IK. Search a safe bent pose
		# with full segment/foot sweeps; never disable queries for jump animation.
		var accepted := false
		for offset in tuning.jump_pose_search_offsets:
			for length in [distance, tuning.jump_tuck_distance, tuning.jump_prepare_distance]:
				var alternative := hip + Vector2(offset, length)
				if _sweep_clear(old_hip, old_foot, hip, alternative):
					feet[leg] = alternative
					accepted = true
					break
			if accepted:
				break
		if not accepted:
			pose_safety_failures += 1
		# If no swept route exists, retain the previous target, explicitly flagged by pose_clear.
		# No support is granted for an unsafe pose; the torso continues natural physics.
	planted[leg] = can_land and _contact(feet[leg]) and limb_clear(hip, feet[leg])
	hips[leg] = hip

func _jump_motion(state: PhysicsDirectBodyState2D) -> bool:
	var pose := state.transform
	var dt := state.step
	phase_time += dt
	if jump_requested:
		jump_requested = false
		if jump_phase == "standing" and _real_support(pose) > 0:
			swing_leg = -1
			_set_phase("crouch")
		else:
			rejected_jumps += 1
	if jump_phase == "standing":
		if _real_support(pose) > 0:
			return false
		# Walking off support is a fall, not a held support plane or a free jump.
		swing_leg = -1
		_set_phase("descent")
	if jump_phase == "crouch":
		if _real_support(pose) == 0:
			_set_phase("descent")
		elif phase_time >= tuning.jump_crouch_duration and pose.origin.y >= last_ground[0] - tuning.jump_crouch_height - tuning.jump_crouch_tolerance:
			state.apply_central_impulse(Vector2.UP * tuning.jump_impulse_speed * mass)
			jump_count += 1
			_set_phase("takeoff")
	if jump_phase in ["takeoff", "airborne_tuck", "descent"]:
		# No height or horizontal support controller acts in flight; only gravity and initial impulse.
		last_support_accel = 0.0
		last_horizontal_accel = 0.0
		support_count = 0
		var distance: float = tuning.jump_extend_distance
		if jump_phase == "takeoff" and _real_support(pose) == 0 and phase_time >= tuning.jump_tuck_delay:
			_set_phase("airborne_tuck")
		if jump_phase == "airborne_tuck":
			distance = tuning.jump_tuck_distance
		if jump_phase != "takeoff" and state.linear_velocity.y >= tuning.jump_prepare_velocity:
			_set_phase("descent")
		if jump_phase == "descent":
			distance = tuning.jump_prepare_distance
		for i in range(2):
			if jump_phase == "takeoff" and planted[i] and _sweep_clear(hips[i], feet[i], _hip(pose, i), feet[i]):
				hips[i] = _hip(pose, i)
			else:
				planted[i] = false
				_air_leg(pose, i, distance, dt, jump_phase == "descent" and state.linear_velocity.y >= 0.0)
			var solved := _solve(hips[i], feet[i])
			knees[i] = solved[0]
			feet[i] = solved[1]
			pose_clear[i] = limb_clear(hips[i], feet[i])
			if jump_phase == "descent" and planted[i] and pose_clear[i]:
				support_count += 1
				last_ground[i] = feet[i].y + tuning.foot_radius + tuning.clearance
		if support_count > 0:
			landing_count += 1
			landing_start_height = pose.origin.y
			_set_phase("landing")
		else:
			return true
	if jump_phase == "landing" and phase_time >= tuning.jump_landing_duration and absf(state.linear_velocity.y) < tuning.jump_stable_speed:
		_set_phase("recover")
	if jump_phase == "recover" and phase_time >= tuning.jump_recover_duration and absf(pose.origin.y - (last_ground[0] - tuning.support_height)) < tuning.contact_tolerance and absf(state.linear_velocity.y) < tuning.jump_stable_speed:
		_set_phase("standing")
	return false
@onready var hit_shapes: Array[CollisionShape2D] = [
	$LegHits/LeftUpper/Shape, $LegHits/LeftLower/Shape,
	$LegHits/RightUpper/Shape, $LegHits/RightLower/Shape]

func _ready() -> void:
	spawn_pose = global_transform
	mass = tuning.body_mass
	inertia = tuning.body_inertia
	can_sleep = false

func set_walk_intent(value: float) -> void:
	walk_intent = clampf(value, -1.0, 1.0)

func reset_walker() -> void:
	walk_intent = 0.0
	reset_requested = true

func _rest_foot_x(pose: Transform2D, leg: int) -> float:
	return pose.origin.x + (-1.0 if leg == 0 else 1.0) * tuning.rest_foot_spacing

func _hip(pose: Transform2D, leg: int) -> Vector2:
	return pose * Vector2((-1.0 if leg == 0 else 1.0) * tuning.hip_half_spacing, tuning.hip_drop)

func _reachable(hip: Vector2, foot: Vector2) -> bool:
	var d := hip.distance_to(foot)
	return d <= tuning.upper_length + tuning.lower_length - tuning.reach_margin and d >= absf(tuning.upper_length - tuning.lower_length) + tuning.reach_margin

func _bend_direction() -> float:
	return 1.0

func _solve(hip: Vector2, target: Vector2) -> Array[Vector2]:
	return IK.solve_points(hip, target, tuning.upper_length, tuning.lower_length, tuning.reach_margin, _bend_direction())

func _ground(x: float, reference_y: float) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(Vector2(x, reference_y - tuning.probe_up), Vector2(x, reference_y + tuning.probe_down), tuning.ground_mask)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.normal.y > -tuning.min_ground_normal:
		return {}
	return {"foot": hit.position + Vector2.UP * (tuning.foot_radius + tuning.clearance), "surface_y": hit.position.y}

func _contact(foot: Vector2) -> bool:
	var hit := _ground(foot.x, foot.y)
	return not hit.is_empty() and foot.distance_to(hit.foot) <= tuning.contact_tolerance

func _capsule_clear(a: Vector2, b: Vector2, radius: float) -> bool:
	var shape := CapsuleShape2D.new()
	shape.radius = radius
	shape.height = a.distance_to(b) + 2.0 * radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D((b - a).angle() - PI / 2.0, (a + b) * 0.5)
	query.collision_mask = tuning.ground_mask
	return space.intersect_shape(query, 1).is_empty()

func limb_clear(hip: Vector2, foot: Vector2) -> bool:
	if not _reachable(hip, foot):
		return false
	var solved := _solve(hip, foot)
	return _capsule_clear(hip, solved[0], tuning.limb_radius + tuning.clearance) and _capsule_clear(solved[0], solved[1], tuning.limb_radius + tuning.clearance) and _capsule_clear(foot, foot, tuning.foot_radius)

func _sweep_clear(old_hip: Vector2, old_foot: Vector2, hip: Vector2, foot: Vector2) -> bool:
	# Subdivide the entire solved pair of capsules, not just a foot ray.
	var old_knee := _solve(old_hip, old_foot)[0]
	var knee := _solve(hip, foot)[0]
	var travel := maxf(maxf(old_hip.distance_to(hip), old_foot.distance_to(foot)), old_knee.distance_to(knee))
	var samples := maxi(1, ceili(travel / tuning.sweep_spacing))
	if samples > tuning.max_sweep_samples:
		return false
	for j in range(1, samples + 1):
		var f := float(j) / samples
		if not limb_clear(old_hip.lerp(hip, f), old_foot.lerp(foot, f)):
			return false
	return true

func _arc(from: Vector2, to: Vector2, fraction: float) -> Vector2:
	var smooth := fraction * fraction * (3.0 - 2.0 * fraction)
	return from.lerp(to, smooth) + Vector2.UP * sin(PI * fraction) * tuning.swing_height

func _plan_step(pose: Transform2D, direction: float) -> bool:
	var leg := next_leg
	var hip := _hip(pose, leg)
	for offset in tuning.landing_search_offsets:
		var hit := _ground(hip.x + direction * (tuning.step_lead + offset), hip.y)
		if hit.is_empty() or absf(hit.foot.x - feet[leg].x) < tuning.minimum_step:
			continue
		var previous_hip := hip
		var previous_foot := feet[leg]
		var valid := true
		for sample in range(1, tuning.path_samples + 1):
			var f: float = float(sample) / tuning.path_samples
			var future_hip := hip + Vector2(direction * tuning.walk_speed * tuning.swing_duration * f, 0.0)
			var future_foot := _arc(feet[leg], hit.foot, f)
			if not _sweep_clear(previous_hip, previous_foot, future_hip, future_foot):
				valid = false
				break
			previous_hip = future_hip
			previous_foot = future_foot
		if valid:
			swing_leg = leg
			swing_time = 0.0
			swing_from = feet[leg]
			swing_to = hit.foot
			planted[leg] = false
			step_starts += 1
			return true
	rejected_steps += 1
	cooldown = tuning.step_cooldown
	return false

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	space = state.get_space_state()
	if reset_requested:
		state.transform = spawn_pose
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		initialized = false
		reset_requested = false
		completed_steps.clear()
		step_starts = 0
		rejected_steps = 0
		aborted_steps = 0
		jump_requested = false
		jump_count = 0
		landing_count = 0
		rejected_jumps = 0
		pose_safety_rejections = 0
		pose_safety_failures = 0
		_set_phase("standing")
	var pose := state.transform
	var dt := state.step
	if not initialized:
		swing_leg = -1
		next_leg = 0
		cooldown = 0.0
		for i in range(2):
			hips[i] = _hip(pose, i)
			var x: float = _rest_foot_x(pose, i)
			var hit := _ground(x, hips[i].y)
			feet[i] = hit.foot if not hit.is_empty() and _reachable(hips[i], hit.foot) else _solve(hips[i], hips[i] + Vector2.DOWN * tuning.support_height)[1]
			planted[i] = not hit.is_empty() and limb_clear(hips[i], feet[i]) and _contact(feet[i])
		initialized = true
	cooldown = maxf(0.0, cooldown - dt)
	if _jump_motion(state):
		_stabilize(state)
		_update_hit_areas()
		queue_redraw()
		return
	for i in range(2):
		var hip := _hip(pose, i)
		var lost_contact := false
		if planted[i] and (not _contact(feet[i]) or not _sweep_clear(hips[i], feet[i], hip, feet[i])):
			planted[i] = false
			lost_contact = true
		if not planted[i] and swing_leg != i and not lost_contact and jump_phase != "standing":
			# An interrupted swing joins crouch/landing through the same swept pose path.
			_air_leg(pose, i, tuning.jump_extend_distance, dt, true)
		elif not planted[i] and swing_leg != i and not lost_contact:
			# Falling/recovery reaches for real ground, never invents a support plane.
			var hit := _ground(hip.x, hip.y)
			if not hit.is_empty() and limb_clear(hip, hit.foot) and state.linear_velocity.y >= -tuning.landing_speed:
				feet[i] = hit.foot
				planted[i] = true
			else:
				feet[i] = _solve(hip, hip + Vector2.DOWN * tuning.support_height)[1]
		hips[i] = hip
	if swing_leg >= 0:
		var i := swing_leg
		var fraction := minf(1.0, (swing_time + dt) / tuning.swing_duration)
		var candidate := _arc(swing_from, swing_to, fraction)
		if _sweep_clear(hips[i], feet[i], hips[i], candidate):
			feet[i] = candidate
			swing_time += dt
			if fraction >= 1.0:
				planted[i] = _contact(feet[i])
				if planted[i]:
					completed_steps.append(i)
					next_leg = 1 - i
				swing_leg = -1
				cooldown = tuning.step_cooldown
		else:
			aborted_steps += 1
			swing_leg = -1
			cooldown = tuning.step_cooldown
	var blocked := false
	# Conservative stopping envelope for torso-driven changes to the stance skeleton.
	# This may stop before a small block rather than solve a climbing gait.
	if walk_intent != 0.0:
		for i in range(2):
			if planted[i]:
				var ahead_hip := hips[i] + Vector2(walk_intent * tuning.step_lead, 0.0)
				var ahead := _solve(ahead_hip, feet[i])
				if not _capsule_clear(ahead_hip, ahead[0], tuning.limb_radius + tuning.clearance) or not _capsule_clear(ahead[0], ahead[1], tuning.limb_radius + tuning.clearance):
					blocked = true
	if blocked and cooldown <= 0.0:
		rejected_steps += 1
		cooldown = tuning.step_cooldown
	if jump_phase == "standing" and not blocked and swing_leg < 0 and cooldown <= 0.0 and walk_intent != 0.0 and planted[0] and planted[1]:
		var lag := maxf((hips[0].x - feet[0].x) * walk_intent, (hips[1].x - feet[1].x) * walk_intent)
		if lag > tuning.step_trigger:
			blocked = not _plan_step(pose, signf(walk_intent))
	# Rejected/aborted steps brake rather than dragging an unreachable stance leg.
	if swing_leg < 0 and walk_intent != 0.0:
		for i in range(2):
			if planted[i] and (hips[i].x - feet[i].x) * walk_intent > tuning.step_trigger and cooldown > 0.0:
				blocked = true
	support_count = 0
	var surface_sum := 0.0
	for i in range(2):
		var solved := _solve(hips[i], feet[i])
		knees[i] = solved[0]
		feet[i] = solved[1]
		pose_clear[i] = limb_clear(hips[i], feet[i])
		if planted[i] and pose_clear[i] and _contact(feet[i]):
			support_count += 1
			last_ground[i] = feet[i].y + tuning.foot_radius + tuning.clearance
			surface_sum += last_ground[i]
	last_support_accel = 0.0
	last_horizontal_accel = 0.0
	if support_count > 0:
		var height: float = tuning.support_height
		if jump_phase == "crouch":
			height = tuning.jump_crouch_height
		elif jump_phase == "landing":
			height = tuning.jump_landing_height
		elif jump_phase == "recover":
			height = lerpf(tuning.jump_landing_height, tuning.support_height, minf(1.0, phase_time / tuning.jump_recover_duration))
		var target_y: float = surface_sum / support_count - height
		last_support_accel = clampf(state.total_gravity.y + tuning.height_gain * (pose.origin.y - target_y) + tuning.height_damping * state.linear_velocity.y, 0.0, tuning.max_support_accel)
		var desired_speed: float = 0.0 if blocked or jump_phase in ["landing", "recover"] else walk_intent * tuning.walk_speed
		last_horizontal_accel = clampf((desired_speed - state.linear_velocity.x) * tuning.velocity_gain, -tuning.max_horizontal_accel, tuning.max_horizontal_accel)
		state.apply_central_force(Vector2(last_horizontal_accel, -last_support_accel) * mass)
	_stabilize(state)
	_update_hit_areas()
	queue_redraw()

func _stabilize(state: PhysicsDirectBodyState2D) -> void:
	var angular_accel: float = clampf(-tuning.upright_gain * state.transform.get_rotation() - tuning.upright_damping * state.angular_velocity, -tuning.max_angular_accel, tuning.max_angular_accel)
	state.apply_torque(angular_accel * inertia)

func _update_hit_areas() -> void:
	for i in range(2):
		var points: Array[Vector2] = [hips[i], knees[i], feet[i]]
		for segment in range(2):
			var shape := hit_shapes[i * 2 + segment]
			shape.global_position = (points[segment] + points[segment + 1]) * 0.5
			shape.global_rotation = (points[segment + 1] - points[segment]).angle() - PI / 2.0
			shape.shape.radius = tuning.limb_radius
			shape.shape.height = points[segment].distance_to(points[segment + 1]) + 2.0 * tuning.limb_radius

func _draw() -> void:
	if not initialized:
		return
	for i in range(2):
		var color := Color(0.3, 0.8, 0.95) if i == 0 else Color(1.0, 0.65, 0.25)
		draw_line(to_local(hips[i]), to_local(knees[i]), color, tuning.limb_radius * 2.0, true)
		draw_line(to_local(knees[i]), to_local(feet[i]), color, tuning.limb_radius * 2.0, true)
		draw_circle(to_local(knees[i]), tuning.limb_radius + 1.0, color)
		draw_circle(to_local(feet[i]), tuning.foot_radius, color)
		if planted[i]:
			draw_line(to_local(feet[i] + Vector2(-7, 5)), to_local(feet[i] + Vector2(7, 5)), Color.WHITE, 2.0)
