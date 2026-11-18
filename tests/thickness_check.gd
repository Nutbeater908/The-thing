extends SceneTree
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var scene = load("res://scenes/prototypes/thickness_range.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	for i in 10:
		await process_frame
	check(scene.contour_vertices >= 8, "alpha contour extracted")
	var shell: CSGPolygon3D = scene.thickness_root.get_child(0)
	check(not shell.use_collision, "no added physics")
	check(shell.get_meshes().size() == 2, "native CSG produces mesh")
	check(scene.far_leg_root.get_child_count() == 3, "three far leg pieces")
	var original_shape: Vector3 = scene.player.get_node("MovementShape").shape.size
	scene.thickness_enabled = false
	scene._process(0.016)
	check(not scene.thickness_root.visible, "flat comparison hides extrusion")
	check(not scene.far_leg_root.visible, "flat comparison hides far leg")
	scene.thickness_enabled = true
	scene.facing = -1.0
	scene._process(0.016)
	check(scene.thickness_root.visible and scene.visual.rotation.is_equal_approx(Vector3.ZERO), "thick model keeps stable world orientation")
	check(scene.visual.scale.x < 0, "whole assembly mirrors")
	check(scene.player.get_node("MovementShape").shape.size == original_shape, "comparison preserves collision")
	print("THICKNESS_CHECK ", "PASS" if failures.is_empty() else "FAIL", " contour_vertices=",scene.contour_vertices," failures=",failures)
	quit(0 if failures.is_empty() else 1)
