extends SceneTree

var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var scene = load("res://scenes/prototypes/material_range.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	await process_frame
	check(scene.REPEAT_METRES[scene.diagnostic_mode] == 24.0, "24m default")
	check(scene.floor_material.uv1_scale.is_equal_approx(Vector3.ONE / 24.0), "24m mapping")
	for path in ["Terrain/Ramp/Visual", "Terrain/PlatformA/Visual", "Terrain/PlatformB/Visual"]:
		check(scene.get_node(path).material_override == scene.floor_material, "concrete on " + path)
	check(scene.get_node("Cover/EquipmentA/Visual").material_override == scene.trial_material, "equipment steel unchanged")
	var terrain = scene.get_node("Terrain").get_child(0)
	check(terrain.get_node("Visual").material_override == scene.floor_material, "floor shares material")
	check(scene.floor_material.uv1_world_triplanar, "world mapping enabled")
	check(scene.floor_material.albedo_texture.get_image().has_mipmaps(), "concrete mipmaps imported")
	scene.texture_enabled = false
	scene._apply_material_trial()
	for i in scene.trial_surfaces.size():
		check(scene.trial_surfaces[i].material_override == scene.original_materials[i], "graybox restore " + str(i))
	print("MATERIAL_RANGE_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)
