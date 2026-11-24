extends SceneTree

var failures: Array[String] = []
const DT := 1.0 / 60.0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _stride_count(speed: float) -> int:
	var gait := GaitController.new()
	gait.init_stance(Vector2.ZERO, 200.0)
	gait.leg_reach = 185.0
	gait.sole_offset = 37.0
	var switches := 0
	var in_reach := true
	var planted := true
	var run_frames := 0
	for i in range(1, 241):
		var old_phase := gait._run_phase
		var state := gait.state
		var x := speed * DT * (i - 1)
		var left_x := x + gait.near_offset.x
		var right_x := x + gait.far_offset.x
		x += speed * DT
		gait.update(DT, Vector2(x, 0), speed, 1.0, true)
		if gait.running:
			run_frames += 1
			if floori(old_phase * 2.0) != floori(gait._run_phase * 2.0):
				switches += 1
		else:
			if state == GaitController.State.BOTH_GROUNDED and gait.state != state:
				switches += 1
			if state != GaitController.State.NEAR_SWING:
				planted = planted and absf(x + gait.near_offset.x - left_x) < 0.02
			if state != GaitController.State.FAR_SWING:
				planted = planted and absf(x + gait.far_offset.x - right_x) < 0.02
		for foot in [gait.near_offset, gait.far_offset]:
			in_reach = in_reach and (foot - Vector2(0, gait.sole_offset)).length() <= gait.leg_reach
	_check(in_reach, "foot targets stay within reach at %s" % speed)
	_check(planted, "walking support foot does not slide at %s" % speed)
	_check((run_frames > 200) == (speed >= gait.run_enter_speed), "speed selects walking or running")
	if run_frames > 0:
		_check(switches <= ceili(4.0 * gait.run_max_steps_per_second), "running cadence capped")
	var x := speed * DT * 240
	for i in 12:
		gait.update(DT, Vector2(x, 0), speed, 1.0, true)
	_check(gait.state == GaitController.State.BOTH_GROUNDED, "no stepping at zero displacement")
	return switches

func _relative_pose(player) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for rig in player._rigs:
		if rig.walk_mode:
			points.append(rig._points[1] - rig._points[0])
			points.append(rig._points[2] - rig._points[0])
	return points

func _same_pose(a: Array[Vector2], b: Array[Vector2]) -> bool:
	if a.size() != 4 or b.size() != 4:
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.001:
			return false
	return true

func _check_jump(room, speed: float) -> void:
	var p = room.player
	p.global_position = Vector2(-650, 542)
	p.set_walk_intent(0.0)
	for i in 25:
		await physics_frame
	p.set_walk_intent(speed)
	for i in 28:
		await physics_frame
	_check(p.is_on_floor(), "jump begins grounded")
	_check(p.request_jump(), "jump request accepted")
	var last_pose := _relative_pose(p)
	var saw_stretch := false
	var saw_air := false
	var saw_landing := false
	var locked := true
	for i in 90:
		await physics_frame
		var pose := _relative_pose(p)
		if not saw_air and p.is_on_floor():
			saw_stretch = saw_stretch or (p._jump_phase == p.JumpPhase.PUSH_OFF and p._body_offset_y < 5.0)
			last_pose = pose
		elif not p.is_on_floor():
			saw_air = true
			if p._gait._air_elapsed > p._gait.AIR_SETTLE_TIME and p._gait._air_landing_blend == 0.0:
				locked = locked and absf(p._gait.near_offset.x) < 0.001 and absf(p._gait.far_offset.x) < 0.001
				locked = locked and absf(p._gait.near_offset.y - (p._gait.stand_height - p._gait.AIR_MID_SHORTEN)) < 0.001
			var saved_facing: float = p.facing
			p.facing = -saved_facing
			# Zero delta checks that mirroring cannot advance the pose transition.
			p._animate_walk(0.0)
			locked = locked and _same_pose(pose, _relative_pose(p))
			p.facing = saved_facing
			p._animate_walk(0.0)
		elif saw_air:
			saw_landing = p._gait.state == GaitController.State.BOTH_GROUNDED
			for rig in p._rigs:
				if rig.walk_mode:
					var sole: Vector2 = p.to_global(rig._points[2] + Vector2(0, p._leg_spec.foot_offset.y))
					saw_landing = saw_landing and absf(sole.y - 550.0) < 1.0
			p.set_walk_intent(0.0)
			break
	_check(saw_stretch and saw_air and locked and saw_landing, "stretch, lock, turn and plant on contact at intent %s (%s %s %s %s)" % [speed, saw_stretch, saw_air, locked, saw_landing])
	for i in 35:
		await physics_frame

func _check_modes_and_air() -> void:
	var gait := GaitController.new()
	gait.init_stance(Vector2.ZERO, 200.0)
	gait.leg_reach = 185.0
	gait.sole_offset = 37.0
	var x := 0.0
	for pair in [[249.0, false], [251.0, true], [235.0, true], [219.0, false]]:
		x += pair[0] * DT
		gait.update(DT, Vector2(x, 0), pair[0], 1.0, true)
		_check(gait.running == pair[1], "threshold hysteresis at %s" % pair[0])
	var before_near := gait.near_offset
	var before_far := gait.far_offset
	gait.update(DT, Vector2(x, -3), 0, 1, false, false, -350)
	_check(gait.near_offset.is_equal_approx(before_near) and gait.far_offset.is_equal_approx(before_far), "takeoff starts at current pose without snapping")
	for i in 12:
		gait.update(DT, Vector2(x, -20), 0, 1, false, false, -100)
	_check(gait.near_offset.is_equal_approx(Vector2(0,190)) and gait.far_offset.is_equal_approx(Vector2(0,190)), "settles into centered mid extension")
	var mid := gait.near_offset
	for i in 12:
		gait.update(DT, Vector2(x, -35), 0, -1, false, false, 0)
	_check(gait.near_offset.is_equal_approx(mid), "midair pose stays fixed during turn")
	gait.update(DT, Vector2(x,0), 0,-1,true)
	_check(gait.state == GaitController.State.BOTH_GROUNDED and gait.near_offset.y == 200, "touchdown restores support immediately")

func _run() -> void:
	_check_modes_and_air()
	var ordinary := _stride_count(150.0)
	var fast := _stride_count(420.0)
	var faster := _stride_count(700.0)
	_check(abs(fast - faster) <= 1, "higher combat speed does not force faster leg cycling")
	_check(ordinary >= 4 and fast > ordinary, "higher speed increases cadence (%d -> %d)" % [ordinary, fast])
	var screen = load("res://scenes/assembly/assembly_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen._load_test_template()
	screen._on_depart()
	var room = current_scene
	await _check_jump(room, 0.0)
	await _check_jump(room, 1.0)
	room.return_to_build()
	await process_frame
	print("MOVEMENT_POSE_CHECK ", "PASS" if failures.is_empty() else "FAIL", " steps=", [ordinary, fast], " failures=", failures)
	quit(0 if failures.is_empty() else 1)
