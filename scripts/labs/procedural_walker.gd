extends RigidBody2D
const IK = preload("res://scripts/labs/leg_kinematics.gd")
const LegHitScene = preload("res://scenes/labs/leg_hitbox.tscn")
## One physical body; kinematic, non-pushing limb hit areas. No other motion controller.
## Leg count and geometry come from tuning.legs, never from hardcoded left/right slots.
@export var tuning: Resource
var walk_intent: float = 0.0
var feet: Array[Vector2] = []
var knees: Array[Vector2] = []
var hips: Array[Vector2] = []
var planted: Array[bool] = []
var last_ground: Array[float] = []
var swing_leg: int = -1
var next_leg: int = 0
var swing_time: float = 0.0
var swing_from: Vector2
var swing_to: Vector2
var cooldown: float = 0.0
var wave_direction: float = 0.0
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
var pose_clear: Array[bool] = []
var legs_spec: Array[LegRig] = []
var hit_shapes: Array[CollisionShape2D] = []
var space: PhysicsDirectSpaceState2D
var jump_phase: String = "standing"
var phase_time: float = 0.0
var jump_requested: bool = false
var hop_requested: bool = false
var hop_count: int = 0
var hop_direction: float = 0.0
var motion_is_hop: bool = false
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
	for i in range(leg_count()):
		if planted[i] and _contact(feet[i]) and limb_clear(_hip(pose, i), feet[i], i):
			count += 1
	return count

func _air_leg(pose: Transform2D, leg: int, distance: float, dt: float, can_land: bool, forward: float = 0.0) -> void:
	var hip := _hip(pose, leg)
	var old_hip := hips[leg]
	var old_foot := feet[leg]
	var desired := hip + Vector2(forward, distance)
	var hit := _ground(hip.x + forward, hip.y) if can_land else {}
	# Only acquire a surface the extending foot actually reaches this frame, never a remote ray hit.
	if not hit.is_empty() and hit.foot.y <= desired.y and _reachable(hip, hit.foot, leg):
		desired = hit.foot
	var candidate := old_foot.move_toward(desired, tuning.jump_pose_speed * dt + hip.distance_to(old_hip))
	if _sweep_clear(old_hip, old_foot, hip, candidate, leg):
		feet[leg] = candidate
	else:
		pose_safety_rejections += 1
		# Body motion is physical and cannot be rolled back by IK. Search a safe bent pose
		# with full segment/foot sweeps; never disable queries for jump animation.
		var accepted := false
		for offset in tuning.jump_pose_search_offsets:
			for length in [distance, tuning.jump_tuck_distance, tuning.jump_prepare_distance]:
				var alternative := hip + Vector2(forward + offset, length)
				if _sweep_clear(old_hip, old_foot, hip, alternative, leg):
					feet[leg] = alternative
					accepted = true
					break
			if accepted:
				break
		if not accepted:
			pose_safety_failures += 1
		# If no swept route exists, retain the previous target, explicitly flagged by pose_clear.
		# No support is granted for an unsafe pose; the torso continues natural physics.
	planted[leg] = can_land and _contact(feet[leg]) and limb_clear(hip, feet[leg], leg)
	hips[leg] = hip

func _jump_motion(state: PhysicsDirectBodyState2D) -> bool:
	var pose := state.transform
	var dt := state.step
	phase_time += dt
	if jump_requested:
		jump_requested = false
		hop_requested = false
		if jump_phase == "standing" and _real_support(pose) > 0:
			motion_is_hop = false
			swing_leg = -1
			_set_phase("crouch")
		else:
			rejected_jumps += 1
	if hop_requested:
		hop_requested = false
		if jump_phase == "standing" and _real_support(pose) > 0 and _is_hop():
			motion_is_hop = true
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
		var crouch_duration: float = tuning.hop_crouch_duration if motion_is_hop else tuning.jump_crouch_duration
		var crouch_height: float = tuning.hop_crouch_height if motion_is_hop else tuning.jump_crouch_height
		if _real_support(pose) == 0:
			_set_phase("descent")
		elif phase_time >= crouch_duration and pose.origin.y >= last_ground[0] - crouch_height - tuning.jump_crouch_tolerance:
			var vertical: float = tuning.hop_impulse_speed if motion_is_hop else tuning.jump_impulse_speed
			var impulse := Vector2.UP * vertical * mass
			if motion_is_hop:
				hop_direction = walk_intent
				impulse.x = (hop_direction * tuning.hop_launch_speed - state.linear_velocity.x) * mass
				hop_count += 1
			else:
				jump_count += 1
			state.apply_central_impulse(impulse)
			_set_phase("takeoff")
	if jump_phase in ["takeoff", "airborne_tuck", "descent"]:
		# No height or horizontal support controller acts in flight; only gravity and initial impulse.
		last_support_accel = 0.0
		last_horizontal_accel = 0.0
		support_count = 0
		var extend_distance: float = tuning.hop_extend_distance if motion_is_hop else tuning.jump_extend_distance
		var tuck_distance: float = tuning.hop_tuck_distance if motion_is_hop else tuning.jump_tuck_distance
		var prepare_distance: float = tuning.hop_prepare_distance if motion_is_hop else tuning.jump_prepare_distance
		var forward: float = hop_direction * tuning.hop_forward_lead if motion_is_hop else 0.0
		var distance: float = extend_distance
		if jump_phase == "takeoff" and _real_support(pose) == 0 and phase_time >= tuning.jump_tuck_delay:
			_set_phase("airborne_tuck")
		if jump_phase == "airborne_tuck":
			distance = tuck_distance
		if jump_phase != "takeoff" and state.linear_velocity.y >= tuning.jump_prepare_velocity:
			_set_phase("descent")
		if jump_phase == "descent":
			distance = prepare_distance
		for i in range(leg_count()):
			if jump_phase == "takeoff" and planted[i] and _sweep_clear(hips[i], feet[i], _hip(pose, i), feet[i], i):
				hips[i] = _hip(pose, i)
			else:
				planted[i] = false
				_air_leg(pose, i, distance, dt, jump_phase == "descent" and state.linear_velocity.y >= 0.0, forward)
			var solved := _solve(hips[i], feet[i], i)
			knees[i] = solved[0]
			feet[i] = solved[1]
			pose_clear[i] = limb_clear(hips[i], feet[i], i)
			if jump_phase == "descent" and planted[i] and pose_clear[i]:
				support_count += 1
				last_ground[i] = feet[i].y + tuning.foot_radius + tuning.clearance
		if support_count > 0:
			landing_count += 1
			landing_start_height = pose.origin.y
			_set_phase("landing")
		else:
			return true
	var landing_duration: float = tuning.hop_landing_duration if motion_is_hop else tuning.jump_landing_duration
	var recover_duration: float = tuning.hop_recover_duration if motion_is_hop else tuning.jump_recover_duration
	if jump_phase == "landing" and phase_time >= landing_duration and absf(state.linear_velocity.y) < tuning.jump_stable_speed:
		_set_phase("recover")
	if jump_phase == "recover" and phase_time >= recover_duration and absf(pose.origin.y - (last_ground[0] - tuning.support_height)) < tuning.contact_tolerance and absf(state.linear_velocity.y) < tuning.jump_stable_speed:
		_set_phase("standing")
		motion_is_hop = false
	return false
func _ready() -> void:
	spawn_pose = global_transform
	mass = tuning.body_mass
	inertia = tuning.body_inertia
	can_sleep = false
	_refresh_rig()

## Build the leg list and the per-leg state/hit arrays from tuning.
func _refresh_rig() -> void:
	legs_spec = _resolve_legs()
	var n := legs_spec.size()
	if n <= 0:
		return
	if hips.size() != n:
		hips.resize(n)
		knees.resize(n)
		feet.resize(n)
		planted.resize(n)
		last_ground.resize(n)
		pose_clear.resize(n)
		for i in n:
			hips[i] = Vector2.ZERO
			knees[i] = Vector2.ZERO
			feet[i] = Vector2.ZERO
			planted[i] = false
			last_ground[i] = 0.0
			pose_clear[i] = true
		initialized = false
		swing_leg = -1
		next_leg = 0
		wave_direction = 0.0
	if hit_shapes.size() != n * 2:
		_rebuild_hit_shapes(n)

func _resolve_legs() -> Array[LegRig]:
	var out: Array[LegRig] = []
	if tuning == null:
		return out
	if not tuning.legs.is_empty():
		out.assign(tuning.legs)
		return out
	# Legacy scalar fallback: exactly the verified two-leg rig.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var spec := LegRig.new()
		spec.mount = Vector2(side * tuning.hip_half_spacing, tuning.hip_drop)
		spec.rest_foot_offset = side * tuning.rest_foot_spacing
		spec.upper_length = tuning.upper_length
		spec.lower_length = tuning.lower_length
		spec.bend = 1.0
		out.append(spec)
	return out

func _rebuild_hit_shapes(n: int) -> void:
	var root := get_node_or_null("LegHits") as Node2D
	if root == null:
		root = Node2D.new()
		root.name = "LegHits"
		root.top_level = true
		add_child(root)
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	hit_shapes.clear()
	for i in n:
		var leg := LegHitScene.instantiate() as Node2D
		leg.name = "Leg%d" % i
		root.add_child(leg)
		hit_shapes.append(leg.get_node("Upper/Shape") as CollisionShape2D)
		hit_shapes.append(leg.get_node("Lower/Shape") as CollisionShape2D)

func _ensure_legs() -> void:
	if legs_spec.is_empty():
		legs_spec = _resolve_legs()

func leg_count() -> int:
	_ensure_legs()
	return legs_spec.size()

func _is_hop() -> bool:
	return tuning != null and tuning.has_method("is_hop") and tuning.is_hop()

func _all_planted() -> bool:
	if planted.is_empty():
		return false
	for value in planted:
		if not value:
			return false
	return true

func set_walk_intent(value: float) -> void:
	walk_intent = clampf(value, -1.0, 1.0)

func reset_walker() -> void:
	walk_intent = 0.0
	reset_requested = true

func _rest_foot_x(pose: Transform2D, leg: int) -> float:
	_ensure_legs()
	return pose.origin.x + legs_spec[leg].rest_foot_offset

func _hip(pose: Transform2D, leg: int) -> Vector2:
	_ensure_legs()
	return pose * legs_spec[leg].mount

func _reachable(hip: Vector2, foot: Vector2, leg: int = 0) -> bool:
	_ensure_legs()
	var spec := legs_spec[leg]
	var d := hip.distance_to(foot)
	# The solver clamps exactly to the reach boundary; allow float rounding at that seam.
	var epsilon := 0.01
	return d <= spec.upper_length + spec.lower_length - tuning.reach_margin + epsilon and d >= absf(spec.upper_length - spec.lower_length) + tuning.reach_margin - epsilon

func _bend_direction(leg: int = 0) -> float:
	_ensure_legs()
	return legs_spec[leg].bend

func _solve(hip: Vector2, target: Vector2, leg: int = 0) -> Array[Vector2]:
	_ensure_legs()
	var spec := legs_spec[leg]
	return IK.solve_points(hip, target, spec.upper_length, spec.lower_length, tuning.reach_margin, _bend_direction(leg))

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

func limb_clear(hip: Vector2, foot: Vector2, leg: int = 0) -> bool:
	if not _reachable(hip, foot, leg):
		return false
	var solved := _solve(hip, foot, leg)
	return _capsule_clear(hip, solved[0], tuning.limb_radius + tuning.clearance) and _capsule_clear(solved[0], solved[1], tuning.limb_radius + tuning.clearance) and _capsule_clear(foot, foot, tuning.foot_radius)

func _sweep_clear(old_hip: Vector2, old_foot: Vector2, hip: Vector2, foot: Vector2, leg: int = 0) -> bool:
	# Subdivide the entire solved pair of capsules, not just a foot ray.
	var old_knee := _solve(old_hip, old_foot, leg)[0]
	var knee := _solve(hip, foot, leg)[0]
	var travel := maxf(maxf(old_hip.distance_to(hip), old_foot.distance_to(foot)), old_knee.distance_to(knee))
	var samples := maxi(1, ceili(travel / tuning.sweep_spacing))
	if samples > tuning.max_sweep_samples:
		return false
	for j in range(1, samples + 1):
		var f := float(j) / samples
		if not limb_clear(old_hip.lerp(hip, f), old_foot.lerp(foot, f), leg):
			return false
	return true

func _arc(from: Vector2, to: Vector2, fraction: float) -> Vector2:
	var smooth := fraction * fraction * (3.0 - 2.0 * fraction)
	return from.lerp(to, smooth) + Vector2.UP * sin(PI * fraction) * tuning.swing_height

func _swing_duration() -> float:
	return tuning.wide_swing_duration if leg_count() > 2 else tuning.swing_duration

func _step_cooldown() -> float:
	return tuning.wide_step_cooldown if leg_count() > 2 else tuning.step_cooldown

func _walk_speed() -> float:
	if leg_count() > 2:
		return minf(tuning.walk_speed, tuning.wide_speed_cap)
	return tuning.walk_speed

func _pick_step_leg(direction: float) -> int:
	# Two legs keep the verified strict alternation. Wider rigs use a front-to-back
	# wave: the leading foot steps first and opens room for the next one. A lag-only
	# pick would deadlock against the ordered landing clamp.
	if leg_count() == 2:
		return next_leg
	var signed := signf(direction)
	if signed != wave_direction:
		wave_direction = signed
		next_leg = leg_count() - 1 if direction > 0.0 else 0
	return next_leg

## Landing x must stay inside the neighbouring feet, so a wave gait never crosses legs.
## An empty interval means the rig is too compressed this cycle; reject rather than cross.
func _ordered_target_x(leg: int, proposed: float) -> float:
	# The verified biped keeps its original landing search unchanged.
	if leg_count() <= 2:
		return proposed
	var gap: float = tuning.foot_radius * 2.0 + 2.0
	var lower := -INF
	var upper := INF
	if leg > 0:
		lower = feet[leg - 1].x + gap
	if leg < leg_count() - 1:
		upper = feet[leg + 1].x - gap
	if lower > upper:
		return NAN
	return clampf(proposed, lower, upper)

func _plan_step(pose: Transform2D, direction: float) -> bool:
	var leg := _pick_step_leg(direction)
	if leg < 0:
		return false
	var hip := _hip(pose, leg)
	var approach_speed: float = walk_intent * _walk_speed() if leg_count() > 2 else tuning.walk_speed
	for offset in tuning.landing_search_offsets:
		var target_x := _ordered_target_x(leg, hip.x + direction * (tuning.step_lead + offset))
		if is_nan(target_x):
			continue
		var hit := _ground(target_x, hip.y)
		if hit.is_empty():
			continue
		if leg_count() > 2:
			# Wide rigs must make forward progress; never shuffle a foot backwards.
			if direction > 0.0 and hit.foot.x < feet[leg].x + tuning.minimum_step:
				continue
			if direction < 0.0 and hit.foot.x > feet[leg].x - tuning.minimum_step:
				continue
		elif absf(hit.foot.x - feet[leg].x) < tuning.minimum_step:
			continue
		var previous_hip := hip
		var previous_foot := feet[leg]
		var valid := true
		for sample in range(1, tuning.path_samples + 1):
			var f: float = float(sample) / tuning.path_samples
			var future_hip := hip + Vector2(direction * approach_speed * _swing_duration() * f, 0.0)
			var future_foot := _arc(feet[leg], hit.foot, f)
			if not _sweep_clear(previous_hip, previous_foot, future_hip, future_foot, leg):
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
	cooldown = _step_cooldown()
	return false

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	space = state.get_space_state()
	if reset_requested:
		state.transform = spawn_pose
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		initialized = false
		reset_requested = false
		wave_direction = 0.0
		completed_steps.clear()
		step_starts = 0
		rejected_steps = 0
		aborted_steps = 0
		jump_requested = false
		hop_requested = false
		hop_count = 0
		hop_direction = 0.0
		motion_is_hop = false
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
		for i in range(leg_count()):
			hips[i] = _hip(pose, i)
			var x: float = _rest_foot_x(pose, i)
			var hit := _ground(x, hips[i].y)
			feet[i] = hit.foot if not hit.is_empty() and _reachable(hips[i], hit.foot, i) else _solve(hips[i], hips[i] + Vector2.DOWN * tuning.support_height, i)[1]
			planted[i] = not hit.is_empty() and limb_clear(hips[i], feet[i], i) and _contact(feet[i])
		initialized = true
	cooldown = maxf(0.0, cooldown - dt)
	if _jump_motion(state):
		_stabilize(state)
		_update_hit_areas()
		queue_redraw()
		return
	for i in range(leg_count()):
		var hip := _hip(pose, i)
		var lost_contact := false
		if planted[i] and (not _contact(feet[i]) or not _sweep_clear(hips[i], feet[i], hip, feet[i], i)):
			planted[i] = false
			lost_contact = true
		if not planted[i] and swing_leg != i and not lost_contact and jump_phase != "standing":
			# An interrupted swing joins crouch/landing through the same swept pose path.
			_air_leg(pose, i, tuning.jump_extend_distance, dt, true)
		elif not planted[i] and swing_leg != i and not lost_contact:
			# Falling/recovery reaches for real ground, never invents a support plane.
			var hit := _ground(hip.x, hip.y)
			if not hit.is_empty() and limb_clear(hip, hit.foot, i) and state.linear_velocity.y >= -tuning.landing_speed:
				feet[i] = hit.foot
				planted[i] = true
			else:
				feet[i] = _solve(hip, hip + Vector2.DOWN * tuning.support_height, i)[1]
		hips[i] = hip
	if swing_leg >= 0:
		var i := swing_leg
		var fraction := minf(1.0, (swing_time + dt) / _swing_duration())
		var candidate := _arc(swing_from, swing_to, fraction)
		if _sweep_clear(hips[i], feet[i], hips[i], candidate, i):
			feet[i] = candidate
			swing_time += dt
			if fraction >= 1.0:
				planted[i] = _contact(feet[i])
				if planted[i]:
					completed_steps.append(i)
					if leg_count() == 2:
						next_leg = 1 - i
					elif wave_direction > 0.0:
						next_leg = (i - 1 + leg_count()) % leg_count()
					else:
						next_leg = (i + 1) % leg_count()
				swing_leg = -1
				cooldown = _step_cooldown()
		else:
			aborted_steps += 1
			swing_leg = -1
			cooldown = _step_cooldown()
	var blocked := false
	# HOP gait never swings the only support; the jump phase machine replaces this block.
	if not _is_hop():
		# Conservative stopping envelope for torso-driven changes to the stance skeleton.
		# This may stop before a small block rather than solve a climbing gait.
		if walk_intent != 0.0:
			for i in range(leg_count()):
				if planted[i]:
					var ahead_hip := hips[i] + Vector2(walk_intent * tuning.step_lead, 0.0)
					var ahead := _solve(ahead_hip, feet[i], i)
					if not _capsule_clear(ahead_hip, ahead[0], tuning.limb_radius + tuning.clearance) or not _capsule_clear(ahead[0], ahead[1], tuning.limb_radius + tuning.clearance):
						blocked = true
		if blocked and cooldown <= 0.0:
			rejected_steps += 1
			cooldown = _step_cooldown()
		if jump_phase == "standing" and not blocked and swing_leg < 0 and cooldown <= 0.0 and walk_intent != 0.0 and _all_planted():
			var lag := -INF
			for i in range(leg_count()):
				lag = maxf(lag, (hips[i].x - feet[i].x) * walk_intent)
			if lag > tuning.step_trigger:
				blocked = not _plan_step(pose, signf(walk_intent))
		# Rejected/aborted steps brake rather than dragging an unreachable stance leg.
		if swing_leg < 0 and walk_intent != 0.0:
			for i in range(leg_count()):
				if planted[i] and (hips[i].x - feet[i].x) * walk_intent > tuning.step_trigger and cooldown > 0.0:
					blocked = true
	support_count = 0
	var surface_sum := 0.0
	for i in range(leg_count()):
		var solved := _solve(hips[i], feet[i], i)
		knees[i] = solved[0]
		feet[i] = solved[1]
		pose_clear[i] = limb_clear(hips[i], feet[i], i)
		if planted[i] and pose_clear[i] and _contact(feet[i]):
			support_count += 1
			last_ground[i] = feet[i].y + tuning.foot_radius + tuning.clearance
			surface_sum += last_ground[i]
	last_support_accel = 0.0
	last_horizontal_accel = 0.0
	if support_count > 0:
		var height: float = tuning.support_height
		if jump_phase == "crouch":
			height = tuning.hop_crouch_height if motion_is_hop else tuning.jump_crouch_height
		elif jump_phase == "landing":
			height = tuning.jump_landing_height
		elif jump_phase == "recover":
			var recover_duration: float = tuning.hop_recover_duration if motion_is_hop else tuning.jump_recover_duration
			height = lerpf(tuning.jump_landing_height, tuning.support_height, minf(1.0, phase_time / recover_duration))
		var target_y: float = surface_sum / support_count - height
		last_support_accel = clampf(state.total_gravity.y + tuning.height_gain * (pose.origin.y - target_y) + tuning.height_damping * state.linear_velocity.y, 0.0, tuning.max_support_accel)
		var desired_speed: float = 0.0 if blocked or jump_phase in ["landing", "recover"] else walk_intent * _walk_speed()
		last_horizontal_accel = clampf((desired_speed - state.linear_velocity.x) * tuning.velocity_gain, -tuning.max_horizontal_accel, tuning.max_horizontal_accel)
		state.apply_central_force(Vector2(last_horizontal_accel, -last_support_accel) * mass)
	# The hop cycle repeats while intent is held; releasing intent lets the current hop finish.
	if _is_hop() and jump_phase == "standing" and walk_intent != 0.0 and support_count > 0 and not jump_requested and not hop_requested and cooldown <= 0.0:
		hop_requested = true
		cooldown = tuning.hop_interval
	_stabilize(state)
	_update_hit_areas()
	queue_redraw()

func _stabilize(state: PhysicsDirectBodyState2D) -> void:
	var angular_accel: float = clampf(-tuning.upright_gain * state.transform.get_rotation() - tuning.upright_damping * state.angular_velocity, -tuning.max_angular_accel, tuning.max_angular_accel)
	state.apply_torque(angular_accel * inertia)

func _update_hit_areas() -> void:
	if hit_shapes.size() < leg_count() * 2:
		return
	for i in range(leg_count()):
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
	for i in range(leg_count()):
		var color := Color(0.3, 0.8, 0.95) if i == 0 else Color(1.0, 0.65, 0.25)
		if leg_count() > 2:
			color = Color.from_hsv(float(i) / float(leg_count()), 0.65, 0.95)
		draw_line(to_local(hips[i]), to_local(knees[i]), color, tuning.limb_radius * 2.0, true)
		draw_line(to_local(knees[i]), to_local(feet[i]), color, tuning.limb_radius * 2.0, true)
		draw_circle(to_local(knees[i]), tuning.limb_radius + 1.0, color)
		draw_circle(to_local(feet[i]), tuning.foot_radius, color)
		if planted[i]:
			draw_line(to_local(feet[i] + Vector2(-7, 5)), to_local(feet[i] + Vector2(7, 5)), Color.WHITE, 2.0)
