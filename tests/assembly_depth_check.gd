extends SceneTree
const Visual = preload("res://scripts/prototypes/assembly_visual_3d.gd")
var errors: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		printerr("FAIL ", label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var lib := PartsLibrary.catalog()
	var a := Assembly.new()
	a.add_root(lib[&"chassis"], Vector2(130, 280))
	a.attach(lib[&"leg_standard"], 0, &"hip")
	var v := Visual.new()
	v.prepare(a)
	check(v.entries.size() == 4, "root plus three leg segments")
	check(v.can_walk, "upright leg enables locomotion")
	var hip: Vector2 = a.socket_position(0, &"hip") - a.parts[0].position
	check((v.entries[1].transform * lib[&"leg_standard"].socket(&"pivot_hip").offset).distance_to(hip)<0.001,"hip alignment")
	check((v.entries[1].transform * lib[&"leg_standard"].socket(&"pivot_knee_u").offset).distance_to(v.entries[2].transform * lib[&"leg_standard"].socket(&"pivot_knee_l").offset)<0.001,"knee alignment")
	var before := v.pixel_bounds
	a.move_root(Vector2(400,-100))
	v.prepare(a)
	check(v.pixel_bounds.is_equal_approx(before),"root translation invariant")
	var copy := Visual.snapshot(a)
	copy.parts[0].position.x += 300
	check(copy.parts[0].position != a.parts[0].position,"snapshot isolated")
	# Rotate a stand-alone resource placement and check same transform for all segments.
	a.parts[1].rotation = 1
	v.prepare(a)
	check(not v.can_walk,"horizontal leg does not walk")
	check(absf(v.entries[1].transform.get_rotation()-PI/2)<0.001,"quarter turn preserved")
	v.free()
	# Real screen round trip: preserve original Assembly and journal node.
	var screen = load("res://scenes/assembly/assembly_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen._load_test_template()
	var original: Assembly = screen.view.assembly
	var journal = screen.view.journal
	screen._on_depth_trial()
	var trial = current_scene
	check(trial != screen,"trial entered")
	check(trial.assembly_snapshot.parts.size()==2,"trial receives current assembly")
	check(trial.assembly_visual.entries.size()==4,"snapshot displayed")
	trial.set_physics_process(false)
	trial.return_to_build()
	await process_frame
	check(current_scene==screen and screen.visible,"returns to original screen")
	check(screen.view.assembly==original and screen.view.journal==journal,"build and undo history retained")
	screen.view.assembly.remove(1)
	screen._on_depth_trial()
	trial=current_scene
	check(trial.assembly_snapshot.parts.size()==1,"reentry reflects removed leg")
	check(not trial.assembly_visual.can_walk,"no leg no locomotion")
	trial.set_physics_process(false)
	trial.return_to_build()
	await process_frame
	print("ASSEMBLY_DEPTH_CHECK ","PASS" if errors.is_empty() else "FAIL"," failures=",errors)
	quit(0 if errors.is_empty() else 1)
