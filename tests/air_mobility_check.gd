extends SceneTree
const Summary = preload("res://scripts/assembly/air_mobility_summary.gd")
const DT := 1.0/60.0
var errors: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		printerr("FAIL ", label)
func _initialize() -> void:
	_run.call_deferred()
func _assembly(powered := true) -> Assembly:
	var lib := PartsLibrary.catalog()
	var a := Assembly.new()
	a.add_root(lib[&"chassis"])
	a.attach(lib[&"leg_standard"],0,&"hip")
	a.attach(lib[&"air_mobility_light"],0,&"utility_rear")
	if powered:
		a.attach(lib[&"power_core"],0,&"bay_power")
	return a
func _apply(p, a: Assembly) -> void:
	var bridge := AssemblyBridge.from_assembly(a)
	bridge = AssemblyBridge.from_assembly(a,AssemblyBridge.hip_ground_lift(bridge))
	p.apply_body(bridge)
func _run() -> void:
	var lib := PartsLibrary.catalog()
	var a := _assembly()
	var summary := Summary.evaluate(a)
	check(summary.active and summary.mass==43.0 and summary.balance==10.0,"powered light build active")
	check(not Summary.evaluate(_assembly(false)).active,"missing power disables ability")
	var heavy := _assembly()
	heavy.parts[0].data = heavy.parts[0].data.duplicate()
	heavy.parts[0].data.mass = 50
	check(not Summary.evaluate(heavy).active,"overweight disables ability")
	var copy_part := Assembly.Part.new()
	copy_part.data = lib[&"air_mobility_light"]
	a.parts.append(copy_part)
	check(Summary.evaluate(a).acceleration == summary.acceleration,"multiple units do not stack")
	a = _assembly()
	a.remove(2)
	check(not Summary.evaluate(a).installed,"removal loses ability")

	var screen = load("res://scenes/assembly/assembly_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.view.assembly = _assembly()
	screen._refresh_status()
	check(screen.status.text.contains("空中机动有效"),"build UI shows ability")
	screen._on_movement_trial()
	var room = current_scene
	var p = room.player
	room.set_process(false)
	room.set_physics_process(false)
	p.set_physics_process(false)
	await physics_frame
	check(p.air_control_enabled,"ability reaches runtime")
	# Body is placed high enough to remain airborne. Test by calling object methods.
	p.global_position = Vector2(300,-400)
	p.vertical_speed = 0
	p.motor_speed = 0
	p.set_walk_intent(1)
	for i in 12:
		await physics_frame
		p._physics_process(DT)
	check(p.motor_speed > 50,"airborne from platform/fall can accelerate")
	p.set_walk_intent(0)
	var before: float = p.motor_speed
	await physics_frame
	p._physics_process(DT)
	check(is_equal_approx(p.motor_speed,before),"release preserves horizontal inertia")
	p.motor_speed = 500
	p.set_walk_intent(1)
	await physics_frame
	p._physics_process(DT)
	check(is_equal_approx(p.motor_speed,500),"same direction does not clamp inherited overspeed")
	p.set_walk_intent(-1)
	p.external_velocity = Vector2(70,0)
	await physics_frame
	p._physics_process(DT)
	check(p.motor_speed < 500 and p.motor_speed > 0 and p.external_velocity.x > 0,"reverse brakes gradually; knockback survives")
	p.motor_speed = 30
	for i in 10:
		await physics_frame
		p._physics_process(DT)
	check(p.motor_speed < 0,"reverse crosses zero into other direction")
	# Removing the installed unit must reset all control fields.
	_apply(p,a)
	check(not p.air_control_enabled and not p.ability_move_in_air,"remove/reapply disables runtime")
	p.motor_speed = 170
	p.set_walk_intent(-1)
	await physics_frame
	p._physics_process(DT)
	check(is_equal_approx(p.motor_speed,170),"no module preserves inertia even on non-jump fall")
	# Mid-landing horizontal movement is not forced to plant both feet.
	_apply(p,_assembly())
	p._jump_phase = p.JumpPhase.LAND
	p.set_walk_intent(1)
	check(p.walk_intent==1,"landing accepts movement input")
	room.respawn_at(0)
	p.tuning = p.tuning.duplicate()
	p.tuning.walk_speed = 420
	p.set_walk_intent(1)
	for i in 70:
		await physics_frame
		p._physics_process(DT)
	check(p.is_on_floor() and p.request_jump(),"running jump for landing check")
	var was_air := false
	var landed := false
	var resumed := false
	for i in 130:
		await physics_frame
		p._physics_process(DT)
		if not p.is_on_floor():
			was_air = true
		elif was_air:
			landed = true
			if p._jump_phase == p.JumpPhase.LAND and p._gait.running:
				resumed = true
		if resumed:
			break
	check(landed and resumed,"run gait resumes during landing buffer")
	room.return_to_build()
	await process_frame
	check(current_scene==screen and screen.current_assembly().parts.size()==4,"round trip preserves assembly")
	print("AIR_MOBILITY_CHECK ","PASS" if errors.is_empty() else "FAIL"," failures=",errors)
	quit(0 if errors.is_empty() else 1)
