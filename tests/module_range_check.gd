extends SceneTree
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var scene = load("res://scenes/prototypes/module_range.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	await physics_frame
	var low: Vector3 = scene.get_node("Terrain/Ramp/Sockets/Low").global_position
	var high: Vector3 = scene.get_node("Terrain/Ramp/Sockets/High").global_position
	var platform: Vector3 = scene.get_node("Terrain/PlatformA/Sockets/Left").global_position
	check(high.distance_to(platform) < 0.001, "ramp high matches platform seam")
	check(low.distance_to(Vector3(2,0,0)) < 0.001, "ramp low matches floor seam")
	# Compare ground ray height against wedge equation including seams.
	for x in [1.99,2.01,3.0,4.0,5.0,5.99,6.01,9.0]:
		var hit: Dictionary = scene._ray(Vector3(x,5,0),Vector3(x,-2,0),1)
		check(not hit.is_empty(), "surface exists x=" + str(x))
		if not hit.is_empty():
			var expected: float = clampf((x-2.0)/4.0,0.0,1.0)
			check(absf(hit["position"].y-expected)<0.015,"continuous surface x="+str(x))
	# Walk up, across seam, then reverse and descend without jumping.
	scene.player.position = Vector3(0,0.05,0)
	scene.player.velocity = Vector3.ZERO
	for i in 45:
		await physics_frame
		scene.advance_player(1.0/60,Vector2.ZERO,false)
	for i in 120:
		await physics_frame
		scene.advance_player(1.0/60,Vector2(1,0),false)
	check(scene.player.position.x>8.5,"walk crosses upper seam")
	check(absf(scene.player.position.y-1.0)<0.1,"stands on raised platform")
	for i in 150:
		await physics_frame
		scene.advance_player(1.0/60,Vector2(-1,0),false)
	check(scene.player.position.x<1.0,"reverse walk crosses lower seam")
	check(absf(scene.player.position.y)<0.1,"descends to ground")
	# Independent module blocks physical rays.
	var cover: Dictionary = scene._ray(Vector3(15,0.6,5),Vector3(15,0.6,1),1)
	check(not cover.is_empty(),"cover blocks ray")
	check(scene.targets.size()==2,"targets reused by existing gun logic")
	print("MODULE_RANGE_CHECK ","PASS" if failures.is_empty() else "FAIL"," failures=",failures)
	quit(0 if failures.is_empty() else 1)
