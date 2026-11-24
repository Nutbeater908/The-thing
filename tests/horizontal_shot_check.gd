extends SceneTree

var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var screen = load("res://scenes/assembly/assembly_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen._on_depart()
	check(current_scene == screen, "empty assembly stays in build screen")
	screen._load_test_template()
	screen.view._record("射击测试撤销记录")
	var assembly = screen.current_assembly()
	var journal = screen.view.journal
	var count: int = journal.entries.size()
	screen._on_depart()
	var room = current_scene
	if room == screen or room.get("shot_trial") == null:
		printerr("FAIL no shooting trial")
		quit(1)
		return
	check(not screen.visible, "assembly suspended")
	var trial = room.shot_trial
	trial.set_physics_process(false)
	room.set_physics_process(false)
	room.set_process(false)
	room.player.set_physics_process(false)
	await physics_frame
	check(not trial.target.is_physics_processing(), "target cannot retaliate")
	check(not room.enemies.visible, "legacy enemies hidden in trial")
	var player = room.player
	var body: AssemblyBridge.Body = player._assembly_body
	var shoulder: Vector2 = body.parts[body.root_index].position + body.parts[body.root_index].data.socket_offset(&"shoulder")
	player._body_offset_y = 11.0
	for facing in [1.0, -1.0]:
		player.facing = facing
		var expected := shoulder + Vector2(0, 11.0)
		if facing < 0.0:
			expected.x = body.bounds.size.x - expected.x
		var base: Vector2 = player.to_global(expected)
		var direction := Vector2(facing, -0.28).normalized()
		trial.update_aim(base + direction * 300.0)
		check(trial.pivot.global_position.is_equal_approx(base), "shoulder matches facing and crouch")
		check((trial.muzzle.global_position - base).normalized().dot(direction) > 0.9999, "muzzle axis follows aim")
	check(trial.fire_at(trial.pivot.global_position + Vector2(0, -300)).get("kind") == &"rejected", "out-of-arc shot rejected")

	player.facing = 1.0
	player._body_offset_y = 0.0
	_check_camera(room, trial)
	var hp_before: float = trial.target.hp
	var low_aim: Vector2 = trial.target.global_position + Vector2(0, 64.0)
	var blocked: Dictionary = trial.fire_at(low_aim)
	check(blocked.get("kind") == &"blocked" and blocked.get("collider") == trial.cover, "cover intercepts lower shot")
	check(trial.target.hp == hp_before, "blocked shot does not damage target")
	var high_aim: Vector2 = trial.target.global_position + Vector2(0, -63.0)
	for i in 3:
		check(trial.fire_at(high_aim).get("kind") == &"target", "exposed upper portion hits target")
	check(trial.target.dead and not room.settled, "target breaks without legacy settlement")

	room.return_to_build()
	await process_frame
	await process_frame
	check(current_scene == screen and screen.visible, "returns to assembly")
	check(not is_instance_valid(room), "old room freed")
	check(screen.current_assembly() == assembly and screen.view.journal == journal and journal.entries.size() == count, "assembly and undo record retained")
	check(screen._notice_text.contains("已完成横版射击试验"), "return notice delivered")
	print("HORIZONTAL_SHOT_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _check_camera(room, trial) -> void:
	var camera: Camera2D = room.camera
	var rect: Rect2 = room.get_viewport_rect()
	var center: float = rect.get_center().x
	var right: float = rect.end.x - 1.0
	var anchor: Vector2 = room.player.global_position
	var zoom: Vector2 = camera.zoom
	room._update_camera_view(1.0, center + rect.size.x * 0.04, false)
	check(absf(camera.global_position.x - anchor.x) < 0.1, "center dead zone holds camera steady")
	room._update_camera_view(0.016, right, false)
	var first_step: float = camera.global_position.x - anchor.x
	room._update_camera_view(1.0, right, false)
	var ordinary: float = camera.global_position.x - anchor.x
	check(first_step > 0.0 and first_step < ordinary, "mouse follow ramps in smoothly")
	room._update_camera_view(1.0, right, true)
	var extended: float = camera.global_position.x - anchor.x
	check(extended > ordinary * 1.8, "holding observe increases look-ahead")
	check(camera.zoom == zoom and is_equal_approx(camera.global_position.y, anchor.y), "observe preserves zoom and vertical anchor")
	var canvas: Transform2D = trial.get_canvas_transform()
	check(rect.has_point(canvas * anchor), "player remains on screen")
	var world_aim: Vector2 = trial.target.global_position + Vector2(0, -63.0)
	var screen_aim: Vector2 = canvas * world_aim
	check(rect.has_point(screen_aim), "target stays visible with pushed camera")
	var recovered_aim := canvas.affine_inverse() * screen_aim
	trial.update_aim(recovered_aim)
	var direction: Vector2 = (trial.muzzle.global_position - trial.pivot.global_position).normalized()
	check(direction.dot((world_aim - trial.pivot.global_position).normalized()) > 0.9999, "pushed camera keeps barrel on cursor target")
	room._update_camera_view(1.0, right, false)
	check(absf(camera.global_position.x - anchor.x - ordinary) < 1.0, "release returns to ordinary lead")
	room._update_camera_view(1.0, rect.position.x, true)
	check(camera.global_position.x < anchor.x, "observe also looks left")
	room.trial_camera_follow = false
	room._update_camera_view(1.0, right, true)
	check(absf(camera.global_position.x - anchor.x) < 1.0, "comparison toggle returns to centered camera")
	room.trial_camera_follow = true
