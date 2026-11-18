extends SceneTree

var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var scene = load("res://scenes/prototypes/depth_range.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.set_process(false)
	for i in 60:
		await physics_frame
		scene.advance_player(1.0 / 60, Vector2.ZERO, false)
	check(scene.player.is_on_floor(), "player settles on floor")
	var initial: Vector3 = scene.player.position
	for i in 60:
		await physics_frame
		scene.advance_player(1.0 / 60, Vector2(0, -1), false)
	check(scene.player.position.z < initial.z - 3, "depth movement works")
	var jump_y: float = scene.player.position.y
	scene.advance_player(1.0 / 60, Vector2(1, 0), true)
	var air_x: float = scene.player.velocity.x
	for i in 12:
		await physics_frame
		scene.advance_player(1.0 / 60, Vector2(-1, 0), false)
	check(scene.player.position.y > jump_y + 0.5, "jump rises")
	check(absf(scene.player.velocity.x - air_x) < 0.001, "air input cannot change horizontal speed")
	for i in 100:
		await physics_frame
		scene.advance_player(1.0 / 60, Vector2.ZERO, false)
	check(scene.player.is_on_floor(), "jump lands")
	# Clear shot at near target, depth axis resolved in true 3D.
	scene.player.position = Vector3(0, 0.05, -5)
	scene.player.velocity = Vector3.ZERO
	scene.facing = 1.0
	await physics_frame
	var result: Dictionary = scene.fire_at(scene.targets[0].position)
	check(result.get("collider") == scene.targets[0], "clear ray hits target")
	check(scene.hits == 1, "target records hit")
	# Tall wall separates player from aim point.
	scene.player.position = Vector3(4, 0.05, 1)
	await physics_frame
	result = scene.resolve_shot(Vector3(12, 2.25, 1))
	check(result.get("collider") != null and result["collider"].name == "TallWall", "wall blocks muzzle ray")
	# Camera projection onto two different target depths/heights.
	for target in scene.targets:
		var screen: Vector2 = scene.camera.unproject_position(target.position)
		scene.update_aim(screen)
		check(scene.aim_point.distance_to(target.position) < 1.3, "screen aim resolves " + str(target.name))
	# 两侧接近墙体：必须按纵深半尺寸阻挡，而非旧胶囊半径。
	for side in [-1.0, 1.0]:
		scene.player.position = Vector3(8, 0.05, 1 + side * 5.0)
		scene.player.velocity = Vector3.ZERO
		for i in 90:
			await physics_frame
			scene.advance_player(1.0 / 60, Vector2(0, -side), false)
		var wall_clearance: float = (scene.player.position.z - 1.0) * side
		check(wall_clearance >= 2.5 + scene.body_depth * 0.5 - 0.03, "depth envelope blocks wall from side " + str(side))
	# 静态贴图关节在同一坐标系精确重合，镜像整组不破坏关系。
	var layout: Array = scene.sprite_layout
	var leg_path := "res://resources/parts/leg_standard.tres"
	var chassis_hip: Vector2 = scene._resource_vector("res://resources/parts/chassis.tres", "hip")
	check((layout[1]["origin"] + scene._resource_vector(leg_path, "pivot_hip")).distance_to(chassis_hip) < 0.001, "chassis hip aligned")
	check((layout[1]["origin"] + scene._resource_vector(leg_path, "pivot_knee_u")).distance_to(layout[2]["origin"] + scene._resource_vector(leg_path, "pivot_knee_l")) < 0.001, "knee aligned")
	check((layout[2]["origin"] + scene._resource_vector(leg_path, "pivot_ankle_s")).distance_to(layout[3]["origin"] + scene._resource_vector(leg_path, "pivot_ankle_f")) < 0.001, "ankle aligned")
	print("DEPTH_RANGE_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)
