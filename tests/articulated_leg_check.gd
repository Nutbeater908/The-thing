## Run ONLY in an isolated minimal project containing labs and this test, no autoloads.
## The launcher must also fail on SCRIPT ERROR / ERROR output (Godot can otherwise exit 0).
## Exit 0 = all pass; 1 = lab/fallback failure; 2 = native hard-limit blocker only.
extends SceneTree
const IK = preload("res://scripts/labs/leg_kinematics.gd")
const RIG = preload("res://scenes/labs/articulated_biped.tscn")
const LAB = preload("res://scenes/labs/two_leg_lab.tscn")
const CONTACT = preload("res://scripts/labs/lab_contact_body.gd")
var failed := 0
var native_limit_failures := 0
var lab: Node2D

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool, detail: Variant = "") -> void:
	if not condition:
		failed += 1
	print("%s %s %s" % ["PASS" if condition else "FAIL", label, str(detail)])

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func _run() -> void:
	check("no autoload / session singleton", not root.has_node("RunState") and root.get_child_count() == 0)
	var structure = RIG.instantiate()
	root.add_child(structure)
	var rigid_count := 0
	var joint_count := 0
	for node in structure.get_children():
		if node is RigidBody2D:
			rigid_count += 1
			check("free sibling " + node.name, not node.lock_rotation and not node.freeze and node.collision_layer == 2 and node.collision_mask == 1)
			check("collision belongs to body " + node.name, node.get_node("Shaft").get_parent() == node)
		if node is PinJoint2D:
			joint_count += 1
			check("pin joins two bodies / motor off " + node.name, not node.motor_enabled and not node.angular_limit_enabled and node.get_node(node.node_a) is RigidBody2D and node.get_node(node.node_b) is RigidBody2D)
	structure._measure()
	check("five rigid bodies / four pins", rigid_count == 5 and joint_count == 4)
	check("initial coincident endpoint markers", structure.max_gap < 0.001, structure.max_gap)
	root.remove_child(structure)
	structure.free()
	for x in [-40.0, 0.0, 40.0]:
		var previous := -10.0
		for h in [150.0, 140.0, 120.0, 100.0]:
			var result: Dictionary = IK.solve(Vector2.ZERO, Vector2(x, h), 80, 80)
			var a: float = result.hip
			var k: float = result.knee
			var endpoint := Vector2.DOWN.rotated(a) * 80.0 + Vector2.DOWN.rotated(a + k) * 80.0
			check("IK length / branch / continuity", endpoint.distance_to(Vector2(x, h)) < 0.001 and k > 0.0 and (previous < -5.0 or absf(a - previous) < 0.5))
			previous = a
	check("IK unreachable clamped", not IK.solve(Vector2.ZERO, Vector2(0, 500), 80, 80).reachable)
	check("PD finite cap and sign", IK.torque(1, 0, 0, 1000, 10, 100) == 100 and IK.torque(-1, 0, 0, 1000, 10, 100) == -100)
	await _pin_reference_probe(1.0, 0.2)
	await _pin_reference_probe(-1.0, -0.1)
	# Keep native probes visible as failures; separately validate the approved fallback.
	for direction in [-1.0, 1.0]:
		await _stop_probe(direction, false)
		await _stop_probe(direction, true)
	check("passive stops inactive inside interval", IK.stop_torque(0, 5, -0.1, 0.2, 3000000, 60000, 800000, 1.0 / 120.0, 0.01) == 0.0)
	check("passive stop finite cap", IK.stop_torque(-3.0, -100, -0.1, 0.2, 3000000, 60000, 800000, 1.0 / 120.0, 0.01) == 800000.0)
	await _contact_probe()
	lab = LAB.instantiate()
	root.add_child(lab)
	var rig = lab.get_node("ArticulatedBiped")
	var worst_tilt := 0.0
	var worst_drift := 0.0
	var worst_gap := 0.0
	var lost_frames := 0
	var bad_frames := 0
	var saturated_frames := 0
	var worst_penetration := 0.0
	var crouch_min := 1000.0
	var stand_final := 0.0
	# 10 s stand, then three 4 s down / 4 s up cycles at 120 Hz.
	for tick in 4080:
		if tick >= 1200:
			var cycle_tick := (tick - 1200) % 960
			if cycle_tick == 0:
				rig.request_crouch(true)
			if cycle_tick == 480:
				rig.request_crouch(false)
		await physics_frame
		var d: Dictionary = rig.diagnostics()
		check_finite(d)
		if tick > 120:
			worst_tilt = maxf(worst_tilt, absf(d.tilt_deg))
			worst_drift = maxf(worst_drift, d.foot_drift)
			worst_gap = maxf(worst_gap, d.joint_gap)
			worst_penetration = maxf(worst_penetration, d.limit_penetration_rad)
			if d.feet < 2:
				lost_frames += 1
			if d.bad_contact:
				bad_frames += 1
				print("BAD_CONTACT captured=", rig.anomalous_contacts, " t=", tick / 120.0, " ", rig.get_node("Torso").ground_contacts, " ", rig.get_node("RearThigh").ground_contacts, " ", rig.get_node("RearShin").ground_contacts, " ", rig.get_node("FrontThigh").ground_contacts, " ", rig.get_node("FrontShin").ground_contacts)
			if d.saturation > 0.99:
				saturated_frames += 1
			if tick >= 1200 and rig.crouching:
				crouch_min = minf(crouch_min, d.height)
		if tick % 480 == 479:
			print("MEASURE t=%.1f %s" % [(tick + 1) / 120.0, JSON.stringify(d)])
		stand_final = d.height
	print("SUMMARY ", JSON.stringify({"worst_tilt_deg": worst_tilt, "worst_foot_drift_px": worst_drift, "worst_joint_gap_px": worst_gap, "lost_support_frames": lost_frames, "bad_contact_frames": bad_frames, "saturated_frames": saturated_frames, "crouch_min": crouch_min, "final_height": stand_final}))
	check("10 s stand + three crouch/recover cycles", worst_tilt < rad_to_deg(rig.tuning.max_tilt) and lost_frames < 40 and bad_frames == 0)
	check("foot drift bounded", worst_drift < rig.tuning.max_foot_drift, worst_drift)
	check("joint endpoint constraint", worst_gap < rig.tuning.max_joint_gap, worst_gap)
	check("actual crouch depth", absf(crouch_min - rig.crouch_height) < 10.0, crouch_min)
	check("actual stand recovery", absf(stand_final - rig.stand_height) < 10.0, stand_final)
	check("drive not continuously saturated", saturated_frames < 408)
	check("stance remains inside anatomical stops", worst_penetration == 0.0, worst_penetration)
	await _jump_checks(rig)
	var driven_height: float = rig.diagnostics().height
	rig.drive_enabled = false
	var release_penetration := 0.0
	var release_stop_peak := 0.0
	for tick in 480:
		await physics_frame
		var d: Dictionary = rig.diagnostics()
		check_finite(d)
		release_penetration = maxf(release_penetration, d.limit_penetration_rad)
		for value in rig.last_stop_torques:
			release_stop_peak = maxf(release_stop_peak, absf(value))
		if not rig.last_torques.is_empty():
			check("actuators actually off", false)
	var released: Dictionary = rig.diagnostics()
	print("RELEASE_STOP peak_penetration_rad=", release_penetration, " peak_torque=", release_stop_peak)
	check("passive stops exercised and capped with drive off", release_stop_peak > 0.0 and release_stop_peak <= rig.tuning.max_stop_torque)
	print("RELEASE ", JSON.stringify(released))
	check("drive off collapses naturally", released.height < driven_height - 35.0 or absf(released.tilt_deg) > 45.0)
	lab.free()
	await _jump_guard_checks()
	print("RESULT fallback_failures=", failed, " native_hard_limit_failures=", native_limit_failures)
	# Exit 2 explicitly means fallback passes but true native hard limits remain blocked.
	quit(1 if failed else (2 if native_limit_failures else 0))

func _jump_checks(rig: Node2D) -> void:
	for attempt in 3:
		var start_y: float = rig.torso.global_position.y
		var start_x: float = rig.torso.global_position.x
		var max_horizontal := 0.0
		var cushion_start := 0.0
		var cushion_min := INF
		var rise := 0.0
		var clearance := 0.0
		var tilt := 0.0
		var bad := 0
		var air_frames := 0
		var phases: Array[String] = []
		var old_landings: int = rig.landing_count
		var peak_force := 0.0
		var peak_attitude := 0.0
		var gap := 0.0
		var invalid_assist := false
		var accepted_rejump := false
		check("jump request accepted " + str(attempt + 1), rig.request_jump())
		for tick in 720:
			await physics_frame
			var d: Dictionary = rig.diagnostics()
			check_finite(d)
			max_horizontal = maxf(max_horizontal, absf(rig.torso.global_position.x - start_x))
			if d.phase == "cushion":
				if cushion_start == 0.0:
					cushion_start = d.height
				cushion_min = minf(cushion_min, d.height)
			if d.phase == "squat":
				rig.request_crouch(true)
				if tick == 5:
					check("crouch guarded during jump", not rig.crouching)
			if not phases.has(d.phase):
				phases.append(d.phase)
				print("JUMP_PHASE ", attempt + 1, " t=", tick / 120.0, " ", JSON.stringify(d))
			rise = maxf(rise, start_y - rig.torso.global_position.y)
			tilt = maxf(tilt, absf(d.tilt_deg))
			gap = maxf(gap, d.joint_gap)
			if d.bad_contact:
				bad += 1
			peak_force = maxf(peak_force, d.assist_force)
			peak_attitude = maxf(peak_attitude, absf(d.attitude_torque))
			invalid_assist = invalid_assist or (d.assist_force > 0.0 and (not d.assist_grounded or d.phase != "push"))
			if d.feet == 0:
				air_frames += 1
				accepted_rejump = accepted_rejump or rig.request_jump()
				var lower_foot: float = maxf(rig.legs[0].shin.get_node("End").global_position.y, rig.legs[1].shin.get_node("End").global_position.y)
				clearance = maxf(clearance, 540.0 - lower_foot)
			if d.phase == "idle" and tick > 120:
				break
		print("JUMP_SUMMARY ", attempt + 1, " ", JSON.stringify({"rise_px": rise, "clearance_px": clearance, "horizontal_drift_px": max_horizontal, "cushion_start_px": cushion_start, "cushion_min_px": cushion_min, "air_frames": air_frames, "tilt_deg": tilt, "bad_frames": bad, "gap_px": gap, "force_peak": peak_force, "attitude_peak": peak_attitude, "impulse": rig.assist_impulse, "phases": phases, "final": rig.diagnostics()}))
		check("measurable jump rise / both feet clearance", rise > 30.0 and clearance > 15.0 and air_frames >= 12)
		check("actual touchdown and stable stand", rig.landing_count == old_landings + 1 and rig.jump_phase == "idle" and rig.supported_feet == 2 and absf(rig.diagnostics().height - rig.stand_height) < 8.0 and absf(rig.torso.rotation) < 0.2)
		check("full pose sequence", phases.has("squat") and phases.has("push") and phases.has("ascent") and phases.has("descent") and phases.has("cushion") and phases.has("recover"))
		check("bounded in-place drift", max_horizontal < 65.0, max_horizontal)
		check("landing cushion bends before recovery", cushion_min < cushion_start - 3.0, {"contact_height": cushion_start, "lowest": cushion_min})
		check("no body or knee ground / joint separation", bad == 0 and gap < rig.tuning.max_joint_gap)
		check("bounded contact-only assistance", not invalid_assist and peak_force <= rig.tuning.jump_assist_force and rig.assist_impulse <= rig.tuning.jump_assist_impulse_cap + 0.001 and peak_attitude <= rig.tuning.jump_attitude_cap)
		check("no airborne repeat launch", not accepted_rejump)
		await frames(240)

func _jump_guard_checks() -> void:
	var no_help := LAB.instantiate()
	root.add_child(no_help)
	var natural = no_help.get_node("ArticulatedBiped")
	await frames(150)
	natural.assistance_enabled = false
	check("assisted option disabled", natural.request_jump())
	var saw_air := false
	var natural_clearance := 0.0
	var help_off := true
	var guard_phases: Array[String] = []
	for tick in 720:
		await physics_frame
		var d: Dictionary = natural.diagnostics()
		check_finite(d)
		help_off = help_off and d.assist_force == 0.0 and d.attitude_torque == 0.0
		if not guard_phases.has(d.phase):
			guard_phases.append(d.phase)
			print("NO_HELP_PHASE ", tick / 120.0, " ", JSON.stringify(d))
		if d.feet == 0:
			saw_air = true
			var foot_y: float = maxf(natural.legs[0].shin.get_node("End").global_position.y, natural.legs[1].shin.get_node("End").global_position.y)
			natural_clearance = maxf(natural_clearance, 540.0 - foot_y)
		if d.phase == "idle" and tick > 120:
			break
	check("assistance off has zero help throughout", help_off and natural.assist_impulse == 0.0)
	print("NO_HELP_COMPARISON ", JSON.stringify({"airborne": saw_air, "clearance": natural_clearance, "final": natural.diagnostics()}))
	await frames(360)
	check("unassisted safety abort returns to stance", natural.jump_phase == "idle" and natural.supported_feet == 2 and absf(natural.diagnostics().height - natural.stand_height) < 8.0)
	no_help.free()
	await frames(30)
	var failed_push := LAB.instantiate()
	root.add_child(failed_push)
	var guarded = failed_push.get_node("ArticulatedBiped")
	await frames(180)
	guarded.tuning = guarded.tuning.duplicate()
	guarded.tuning.jump_assist_force = 0.0
	guarded.tuning.jump_extend_speed = 0.0
	check("failed-push fixture request accepted", guarded.request_jump())
	var saw_timeout := false
	for tick in 600:
		await physics_frame
		check_finite(guarded.diagnostics())
		if guarded.jump_outcome.contains("未离地"):
			saw_timeout = true
		if guarded.jump_phase == "idle" and tick > 120:
			break
	print("FAILED_PUSH ", JSON.stringify(guarded.diagnostics()))
	check("grounded failed takeoff bounded recovery", saw_timeout and guarded.jump_count == 0 and guarded.landing_count == 0 and guarded.jump_phase == "idle" and guarded.supported_feet == 2 and absf(guarded.diagnostics().height - guarded.stand_height) < 8.0)
	# Reset is a fresh scene instance (the only deliberate structural reset).
	failed_push._reset()
	guarded = failed_push.rig
	check("reset clears phase and budget", guarded.jump_phase == "idle" and guarded.assist_impulse == 0.0)
	await frames(180)
	check("drive interruption request accepted", guarded.request_jump())
	await frames(30)
	guarded.drive_enabled = false
	await frames(2)
	check("drive interruption clears jump and all actuation", guarded.jump_phase == "idle" and guarded.last_torques.is_empty() and guarded.last_assist_force == 0.0 and guarded.last_attitude_torque == 0.0 and not guarded.request_jump())
	failed_push.free()
	await frames(30)

func check_finite(d: Dictionary) -> void:
	if not is_finite(d.height) or not is_finite(d.tilt_deg) or absf(d.torque_residual) > 0.001:
		check("finite / equal opposite torque", false, d)
		quit(1)

func _pin_reference_probe(direction: float, expected_offset: float) -> void:
	var fixture := Node2D.new()
	var a := StaticBody2D.new()
	var b := RigidBody2D.new()
	a.rotation = 0.3
	b.rotation = 0.9
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 30)
	shape.shape = rectangle
	b.add_child(shape)
	b.collision_layer = 0
	b.collision_mask = 0
	b.gravity_scale = 0.0
	b.inertia = 100.0
	b.angular_damp = 0.5
	a.name = "Anchor"
	b.name = "Body"
	fixture.add_child(a)
	fixture.add_child(b)
	root.add_child(fixture)
	await frames(2)
	var joint := PinJoint2D.new()
	fixture.add_child(joint)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
	joint.angular_limit_enabled = true
	joint.angular_limit_lower = -0.1
	joint.angular_limit_upper = 0.2
	await frames(2)
	for i in 240:
		b.apply_torque(direction * 1000.0)
		await physics_frame
	var offset := wrapf(b.rotation - a.rotation - 0.6, -PI, PI)
	var within_limit := absf(offset - expected_offset) < 0.035
	if not within_limit:
		native_limit_failures += 1
	print("%s native pin initial-relative reference / sign %s" % ["PASS" if within_limit else "FAIL (ENGINE; compliant fallback required)", str({"direction": direction, "measured_offset": offset, "expected": expected_offset})])
	fixture.free()

func _stop_probe(direction: float, dynamic_pair: bool) -> void:
	var fixture := Node2D.new()
	var a: PhysicsBody2D = RigidBody2D.new() if dynamic_pair else StaticBody2D.new()
	var b := RigidBody2D.new()
	a.rotation = 0.3
	b.rotation = 0.9
	for body in [a, b]:
		if body is RigidBody2D:
			body.gravity_scale = 0.0
			body.inertia = 100.0
			body.angular_damp = 0.0
			body.can_sleep = false
		body.collision_layer = 0
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		body.add_child(shape)
		fixture.add_child(body)
	root.add_child(fixture)
	var joint := PinJoint2D.new()
	fixture.add_child(joint)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
	await frames(2)
	var tuning = load("res://resources/labs/two_leg_tuning.tres")
	var peak := 0.0
	var final_offset := 0.0
	# No active PD: sustained external load, then remove it and observe spring recoil.
	for tick in 480:
		var offset := wrapf(b.rotation - a.rotation - 0.6, -PI, PI)
		var relative_velocity: float = b.angular_velocity - (a.angular_velocity if dynamic_pair else 0.0)
		var stop := IK.stop_torque(offset, relative_velocity, -0.1, 0.2, tuning.stop_kp, tuning.stop_kd, tuning.max_stop_torque, 1.0 / 120.0, 0.02 if dynamic_pair else 0.01)
		var external := direction * 1000.0 if tick < 360 else 0.0
		b.apply_torque(stop + external)
		if dynamic_pair:
			a.apply_torque(-stop - external)
		await physics_frame
		final_offset = wrapf(b.rotation - a.rotation - 0.6, -PI, PI)
		peak = maxf(peak, maxf(-0.1 - final_offset, final_offset - 0.2))
	check("compliant stop sustained load / unload", peak < 0.035 and final_offset > -0.1 and final_offset < 0.2, {"direction": direction, "dynamic_pair": dynamic_pair, "peak_penetration": peak, "final_offset": final_offset})
	if dynamic_pair:
		check("stop pair angular momentum conserved", absf(a.angular_velocity + b.angular_velocity) < 0.001, a.angular_velocity + b.angular_velocity)
	fixture.free()

func _contact_probe() -> void:
	var fixture := Node2D.new()
	var ground := StaticBody2D.new()
	ground.add_to_group("lab_ground")
	var gs := CollisionShape2D.new()
	var gr := RectangleShape2D.new()
	gr.size = Vector2(300, 20)
	gs.shape = gr
	ground.add_child(gs)
	ground.position.y = 100
	fixture.add_child(ground)
	var body := RigidBody2D.new()
	body.set_script(CONTACT)
	body.position.y = 70
	body.rotation = 0.43
	body.lock_rotation = true
	body.max_contacts_reported = 8
	body.contact_monitor = true
	var bs := CollisionShape2D.new()
	var br := RectangleShape2D.new()
	br.size = Vector2(30, 20)
	bs.shape = br
	body.add_child(bs)
	fixture.add_child(body)
	root.add_child(fixture)
	await frames(120)
	var contacts: Array = body.ground_contacts
	check("rotated probe has real floor contact", not contacts.is_empty())
	if not contacts.is_empty():
		var c: Dictionary = contacts[0]
		check("local point transformed to world floor", absf(c.point.y - 90.0) < 2.0, c)
		check("contact normal world UP on rotated body", c.normal.distance_to(Vector2.UP) < 0.02, c.normal)
	fixture.free()
