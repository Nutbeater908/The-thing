extends Node2D
const IK = preload("res://scripts/labs/leg_kinematics.gd")
@export var tuning: Resource = preload("res://resources/labs/two_leg_tuning.tres")
var drive_enabled := true
var assistance_enabled := true
var jump_phase := "idle"
var phase_time := 0.0
var jump_time := 0.0
var assist_impulse := 0.0
var last_assist_force := 0.0
var last_attitude_torque := 0.0
var jump_count := 0
var landing_count := 0
var airborne_seen := false
var landing_height := 0.0
var jump_outcome := ""
var assist_grounded := false
var crouching := false
var status := "settling"
var bodies: Array[RigidBody2D] = []
var legs: Array[Dictionary] = []
var target_height := 0.0
var stand_height := 0.0
var crouch_height := 0.0
var reference_x := 0.0
var elapsed := 0.0
var support_points: Array[Vector2] = []
var supported_feet := 0
var bad_contact := false
var anomalous_contacts: Array[Dictionary] = []
var com := Vector2.ZERO
var max_saturation := 0.0
var torque_residual := 0.0
var max_gap := 0.0
var max_drift := 0.0
var last_torques: Array[float] = []
var last_stop_torques: Array[float] = []
var max_limit_penetration := 0.0
@onready var torso: RigidBody2D = $Torso

func _ready() -> void:
	bodies.assign([$Torso, $RearThigh, $RearShin, $FrontThigh, $FrontShin])
	for body in bodies:
		body.mass = tuning.torso_mass if body == torso else (tuning.shin_mass if "Shin" in body.name else tuning.thigh_mass)
		var material := PhysicsMaterial.new()
		material.friction = tuning.friction
		material.bounce = 0.0
		body.physics_material_override = material
	for prefix in ["Rear", "Front"]:
		var thigh: RigidBody2D = get_node(prefix + "Thigh")
		var shin: RigidBody2D = get_node(prefix + "Shin")
		var hip: Marker2D = torso.get_node(prefix + "Hip")
		var upper: float = thigh.get_node("Start").position.distance_to(thigh.get_node("End").position)
		var lower: float = shin.get_node("Start").position.distance_to(shin.get_node("End").position)
		var foot: Vector2 = shin.get_node("End").global_position
		var hip_joint: PinJoint2D = get_node(prefix + "HipJoint")
		var knee_joint: PinJoint2D = get_node(prefix + "KneeJoint")
		# Verified against a13da4feb/modules/godot_physics_2d/godot_joints_2d.cpp:
		# native limits measure the origin-to-origin vector, not joint rotation.
		# Use explicit passive compliant stops instead; never claim exact hard stops.
		hip_joint.angular_limit_enabled = false
		knee_joint.angular_limit_enabled = false
		legs.append({"thigh": thigh, "shin": shin, "hip_marker": hip, "upper": upper, "lower": lower, "anchor": foot})
	stand_height = (legs[0].upper + legs[0].lower) * tuning.stand_ratio
	crouch_height = (legs[0].upper + legs[0].lower) * tuning.crouch_ratio
	target_height = stand_height
	reference_x = torso.global_position.x

func request_crouch(value: bool) -> void:
	if jump_phase == "idle":
		crouching = value

func request_jump() -> bool:
	# No queued / midair launch: the physical feet, not a timer, grant permission.
	if not drive_enabled or jump_phase != "idle" or elapsed < tuning.contact_grace or supported_feet != 2 or bad_contact or absf(torso.rotation) > tuning.max_tilt:
		return false
	crouching = false
	assist_impulse = 0.0
	airborne_seen = false
	jump_outcome = ""
	jump_time = 0.0
	_set_phase("squat")
	return true

func _set_phase(value: String) -> void:
	jump_phase = value
	phase_time = 0.0

func _jump_step(delta: float) -> void:
	phase_time += delta
	jump_time += delta
	if jump_time > tuning.jump_timeout or bad_contact:
		jump_outcome = "安全中止 / 超时"
		_set_phase("idle")
		return
	match jump_phase:
		"squat":
			target_height = move_toward(target_height, tuning.jump_squat_height, tuning.jump_squat_speed * delta)
			if phase_time >= tuning.jump_squat_time:
				if supported_feet == 2:
					_set_phase("push")
				else:
					jump_outcome = "下蹲失去支撑"
					_set_phase("idle")
		"push":
			target_height = move_toward(target_height, tuning.jump_extend_height, tuning.jump_extend_speed * delta)
			if supported_feet == 0:
				airborne_seen = true
				jump_count += 1
				_set_phase("ascent")
			elif phase_time > tuning.jump_push_timeout:
				jump_outcome = "起跳失败：未离地"
				# Re-anchor at the real feet after a failed push; no body relocation.
				for leg in legs:
					leg.anchor = leg.shin.get_node("End").global_position
				reference_x = torso.global_position.x
				target_height = clampf(legs[0].anchor.y - torso.global_position.y, crouch_height, stand_height)
				_set_phase("recover")
			elif assistance_enabled and supported_feet > 0 and target_height >= tuning.jump_assist_start_height:
				last_assist_force = minf(tuning.jump_assist_force, maxf(0.0, tuning.jump_assist_impulse_cap - assist_impulse) / delta)
				assist_grounded = true
				assist_impulse += last_assist_force * delta
				torso.apply_central_force(Vector2.UP * last_assist_force)
		"ascent", "descent":
			# Touchdown is an actual foot collider contact, never the end of a timer.
			if supported_feet > 0:
				landing_count += 1
				landing_height = legs[0].anchor.y - torso.global_position.y
				target_height = clampf(landing_height, tuning.jump_cushion_height, tuning.jump_extend_height)
				for leg in legs:
					leg.anchor = leg.shin.get_node("End").global_position
				reference_x = torso.global_position.x
				_set_phase("cushion")
			else:
				if torso.linear_velocity.y >= 0.0 and jump_phase != "descent":
					_set_phase("descent")
				var desired: float = tuning.jump_tuck_height if jump_phase == "ascent" else tuning.jump_prepare_height
				target_height = move_toward(target_height, desired, tuning.jump_air_pose_speed * delta)
		"cushion":
			target_height = move_toward(target_height, tuning.jump_cushion_height, tuning.jump_air_pose_speed * delta)
			if phase_time >= tuning.jump_cushion_time and supported_feet == 2:
				_set_phase("recover")
		"recover":
			if supported_feet == 2:
				target_height = move_toward(target_height, stand_height, tuning.jump_recover_speed * delta)
			if phase_time >= tuning.jump_recover_time and supported_feet == 2 and absf(torso.rotation) < tuning.max_tilt and absf(legs[0].anchor.y - torso.global_position.y - stand_height) < 8.0:
				jump_outcome = "落地恢复" if airborne_seen else jump_outcome
				_set_phase("idle")

func _physics_process(delta: float) -> void:
	elapsed += delta
	_measure()
	last_torques.clear()
	last_stop_torques.clear()
	max_saturation = 0.0
	torque_residual = 0.0
	last_assist_force = 0.0
	last_attitude_torque = 0.0
	assist_grounded = false
	# Mechanical stops remain active with actuators off; no pose/velocity writes.
	for leg in legs:
		var thigh: RigidBody2D = leg.thigh
		var shin: RigidBody2D = leg.shin
		var torso_state := PhysicsServer2D.body_get_direct_state(torso.get_rid())
		var thigh_state := PhysicsServer2D.body_get_direct_state(thigh.get_rid())
		var shin_state := PhysicsServer2D.body_get_direct_state(shin.get_rid())
		var ht := IK.stop_torque(thigh.rotation - torso.rotation, thigh.angular_velocity - torso.angular_velocity, tuning.hip_min, tuning.hip_max, tuning.stop_kp, tuning.stop_kd, tuning.max_stop_torque, delta, torso_state.inverse_inertia + thigh_state.inverse_inertia)
		var kt := IK.stop_torque(shin.rotation - thigh.rotation, shin.angular_velocity - thigh.angular_velocity, tuning.knee_min, tuning.knee_max, tuning.stop_kp, tuning.stop_kd, tuning.max_stop_torque, delta, thigh_state.inverse_inertia + shin_state.inverse_inertia)
		thigh.apply_torque(ht - kt)
		shin.apply_torque(kt)
		torso.apply_torque(-ht)
		torque_residual += (ht - kt) + kt - ht
		last_stop_torques.append_array([ht, kt])
	if not drive_enabled:
		if jump_phase != "idle":
			jump_outcome = "驱动关闭中止"
			_set_phase("idle")
		status = "驱动关闭：自由软倒"
		return
	if jump_phase != "idle":
		_jump_step(delta)
		if assistance_enabled and jump_phase != "idle":
			last_attitude_torque = IK.torque(0.0, torso.rotation, torso.angular_velocity, tuning.jump_attitude_kp, tuning.jump_attitude_kd, tuning.jump_attitude_cap)
			torso.apply_torque(last_attitude_torque)
	var safe: bool = supported_feet == 2 and not bad_contact and absf(torso.rotation) < tuning.max_tilt
	if elapsed < tuning.contact_grace:
		status = "等待脚底接触"
	elif not safe:
		status = "暂停高度过渡：失去双脚支撑 / 主体触地 / 倾斜"
	else:
		status = "下蹲" if crouching else "站立"
		if jump_phase == "idle":
			var desired := crouch_height if crouching else stand_height
			target_height = move_toward(target_height, desired, tuning.height_speed * delta)
		var left := minf(legs[0].anchor.x, legs[1].anchor.x)
		var right := maxf(legs[0].anchor.x, legs[1].anchor.x)
		var support_center := (left + right) * 0.5
		var correction := clampf((support_center - com.x) * tuning.balance_gain, -tuning.balance_shift_limit, tuning.balance_shift_limit)
		var desired_x := clampf(support_center + correction, left + 3.0, right - 3.0)
		reference_x = move_toward(reference_x, desired_x, tuning.balance_speed * delta)
	if jump_phase != "idle":
		status = "跳跃：" + jump_phase
	for leg in legs:
		var hip_position := Vector2(reference_x, leg.anchor.y - target_height)
		var foot_target: Vector2 = leg.anchor
		if jump_phase == "ascent" or jump_phase == "descent":
			# Body-relative airborne foot target, solved with fixed lengths and reach clamp.
			hip_position = Vector2.ZERO
			foot_target = Vector2(leg.anchor.x - reference_x, target_height)
		var solution: Dictionary = IK.solve(hip_position, foot_target, leg.upper, leg.lower)
		if not solution.reachable:
			status = "目标超出可达域：保持可达角度"
		var thigh: RigidBody2D = leg.thigh
		var shin: RigidBody2D = leg.shin
		# Relative targets reference an upright torso; never apply world torque to torso.
		var hip_target := clampf(solution.hip, tuning.hip_min, tuning.hip_max)
		var knee_target := clampf(solution.knee, tuning.knee_min, tuning.knee_max)
		var ht := IK.torque(hip_target, thigh.rotation - torso.rotation, thigh.angular_velocity - torso.angular_velocity, tuning.hip_kp, tuning.hip_kd, tuning.max_hip_torque)
		var kt := IK.torque(knee_target, shin.rotation - thigh.rotation, shin.angular_velocity - thigh.angular_velocity, tuning.knee_kp, tuning.knee_kd, tuning.max_knee_torque)
		thigh.apply_torque(ht - kt)
		shin.apply_torque(kt)
		torso.apply_torque(-ht)
		torque_residual += (ht - kt) + kt - ht
		last_torques.append_array([ht, kt])
		max_saturation = maxf(max_saturation, maxf(absf(ht) / tuning.max_hip_torque, absf(kt) / tuning.max_knee_torque))

func _measure() -> void:
	com = Vector2.ZERO
	var mass_sum := 0.0
	for body in bodies:
		com += body.global_position * body.mass
		mass_sum += body.mass
	com /= mass_sum
	support_points.clear()
	supported_feet = 0
	anomalous_contacts.clear()
	bad_contact = not torso.ground_contacts.is_empty()
	max_gap = 0.0
	max_drift = 0.0
	max_limit_penetration = 0.0
	for leg in legs:
		var shin: RigidBody2D = leg.shin
		var thigh: RigidBody2D = leg.thigh
		var foot: Vector2 = shin.get_node("End").global_position
		var hip_angle := wrapf(thigh.rotation - torso.rotation, -PI, PI)
		var knee_angle := wrapf(shin.rotation - thigh.rotation, -PI, PI)
		max_limit_penetration = maxf(max_limit_penetration, maxf(tuning.hip_min - hip_angle, hip_angle - tuning.hip_max))
		max_limit_penetration = maxf(max_limit_penetration, maxf(tuning.knee_min - knee_angle, knee_angle - tuning.knee_max))
		var contacts: Array = shin.ground_contacts
		var supported := false
		for contact in contacts:
			# Foot shape is the second collision child; reject shaft / knee contacts.
			if contact.shape == 1 and contact.normal.y < -0.65:
				support_points.append(contact.point)
				supported = true
			else:
				bad_contact = true
				anomalous_contacts.append({"body": shin.name, "contact": contact.duplicate()})
		if supported:
			supported_feet += 1
		bad_contact = bad_contact or not thigh.ground_contacts.is_empty()
		max_drift = maxf(max_drift, absf(foot.x - leg.anchor.x))
		max_gap = maxf(max_gap, leg.hip_marker.global_position.distance_to(thigh.get_node("Start").global_position))
		max_gap = maxf(max_gap, thigh.get_node("End").global_position.distance_to(shin.get_node("Start").global_position))

func diagnostics() -> Dictionary:
	return {"status": status, "height": legs[0].anchor.y - torso.global_position.y, "target_height": target_height, "tilt_deg": rad_to_deg(torso.rotation), "feet": supported_feet, "bad_contact": bad_contact, "com": com, "foot_drift": max_drift, "joint_gap": max_gap, "saturation": max_saturation, "torque_residual": torque_residual, "limit_penetration_rad": max_limit_penetration, "phase": jump_phase, "outcome": jump_outcome, "assist_force": last_assist_force, "assist_impulse": assist_impulse, "attitude_torque": last_attitude_torque, "assist_grounded": assist_grounded, "jumps": jump_count, "landings": landing_count}
