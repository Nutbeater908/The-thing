extends SceneTree
const DT := 1.0/60.0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var screen = load("res://scenes/assembly/assembly_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen._load_test_template()
	var assembly = screen.current_assembly()
	screen._on_movement_trial()
	var room = current_scene
	check(room.get("shot_trial") == null,"no shooting trial or enemy AI")
	check(room.checkpoints.size() == 8,"eight terrain zones")
	check(room.player._assembly_body.parts.size() == assembly.parts.size(),"all assembled parts passed to player")
	check(room.player._assembly_body.parts[0].data.texture != null,"chassis texture present")
	check(room.player._rigs.size() == 2,"both leg rigs present")
	var ground: Node2D = room.get_node("Terrain")
	check(ground.z_index < room.player.z_index,"terrain behind chassis")
	var background: Polygon2D = ground.get_node("Background")
	for rig in room.player._rigs:
		check(background.z_index + ground.z_index < rig.z_index + room.player.z_index,"background behind each leg")
	await physics_frame
	for i in room.checkpoints.size():
		room.respawn_at(i)
		var marker: Marker2D = room.checkpoints[i]
		check(room.player.global_position == marker.global_position,"zone spawn "+str(i))
		var q := PhysicsRayQueryParameters2D.create(marker.global_position-Vector2(0,300),marker.global_position+Vector2(0,600),256,[room.player.get_rid()])
		var hit: Dictionary = room.get_world_2d().direct_space_state.intersect_ray(q)
		check(not hit.is_empty(),"ground under zone "+str(i))
	room.respawn_at(0)
	for i in 25:
		await physics_frame
	var p = room.player
	p.tuning = p.tuning.duplicate()
	p.tuning.walk_speed = 420
	p.set_walk_intent(1)
	for i in 60:
		await physics_frame
	check(p._gait.running,"test course supports running")
	var h: GaitController = p._gait
	h.run_step_height = 60
	var foot: Vector2 = h._run_foot(h.RUN_CONTACT+(1-h.RUN_CONTACT)*0.5,20,1)
	check(absf(h._ground_offset(foot.x)-foot.y-60)<0.01,"independent run lift parameter")
	check(p.request_jump(),"running jump accepted")
	var moving_during_push := false
	var left_floor := false
	for i in 35:
		await physics_frame
		if p._jump_phase == p.JumpPhase.CROUCH or p._jump_phase == p.JumpPhase.PUSH_OFF:
			moving_during_push = moving_during_push or p._gait.running
		if not p.is_on_floor():
			left_floor = true
			break
	check(moving_during_push and left_floor,"running feet do not freeze through charge and takeoff")
	room.respawn_at(6)
	check(p._body_offset_y == 0 and not p._gait.running,"reset clears jump and run state")
	room.return_to_build()
	await process_frame
	check(current_scene == screen and screen.current_assembly() == assembly,"course returns original assembly")
	print("MOVEMENT_COURSE_CHECK ","PASS" if failures.is_empty() else "FAIL"," failures=",failures)
	quit(0 if failures.is_empty() else 1)
