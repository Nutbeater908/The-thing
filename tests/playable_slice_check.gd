extends SceneTree
## Isolated end-to-end demo session. No real autoload/save file is opened.
class MemoryState extends "res://scripts/run/run_state.gd":
	var saves := 0
	func _ready() -> void:
		pass
	func save_session() -> void:
		saves += 1
	func load_session() -> bool:
		return false
	func preset_names() -> Array[String]:
		return []

var errors: Array[String] = []
var frame := 0
var build
var room
var state

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value and not errors.has(label):
		errors.append(label)
		printerr("FAIL frame=", frame, " ", label)

func tick(count: int = 1) -> void:
	for _i in count:
		await physics_frame
		frame += 1

func state_bytes() -> PackedByteArray:
	return var_to_bytes({"organs": state.organs, "links": state.links, "backpack": state.backpack, "credits": state.credits, "meta": state.meta_credits, "progress": state.progress})

func _ep(organ, uid: StringName, type: int) -> AssemblyGrid.Endpoint:
	var e := AssemblyGrid.Endpoint.new()
	e.organ = organ
	e.port_uid = uid
	e.type = type
	return e

## 测试夹具：一套能过三链校验的手臂级身体（双腿 + 一爪）。
## 只写进隔离副本内存里的拼装盘，不碰任何真实存档或用户方案。
func _place_fixture_body() -> void:
	var grid = build.get_node("Margin/Root/Body/GridPanel/AssemblyGrid")
	var lib := OrganLibrary.catalog()
	grid.place(Vector2i(0, 0), lib[&"parasite"], 0, true)
	grid.place(Vector2i(1, 0), lib[&"brain"], 0, true)
	grid.place(Vector2i(0, 1), lib[&"heart"], 0, true)
	grid.place(Vector2i(2, 0), lib[&"leg"], 0, true)
	grid.place(Vector2i(3, 0), lib[&"leg"], 0, true)
	grid.place(Vector2i(4, 0), lib[&"claw"], 0, true)
	var organs: Array = grid.organs()
	check(organs.size() == 6, "fixture body placed")
	var parasite = organs[0]
	var brain = organs[1]
	var heart = organs[2]
	grid._try_link(_ep(parasite, &"nerve", OrganData.NERVE), _ep(brain, &"nerve_in", OrganData.NERVE))
	grid._try_link(_ep(heart, &"blood", OrganData.BLOOD), _ep(brain, &"blood", OrganData.BLOOD))
	for i in range(3, organs.size()):
		grid._try_link(_ep(brain, &"nerve_out", OrganData.NERVE), _ep(organs[i], &"nerve", OrganData.NERVE))
		grid._try_link(_ep(brain, &"blood", OrganData.BLOOD), _ep(organs[i], &"blood", OrganData.BLOOD))
	check(bool(grid.result()["alive"]), "fixture body passes three-chain validation")

func walk_to(x: float) -> void:
	var player = room.player
	var direction: float = signf(x - player.position.x)
	player.set_walk_intent(direction)
	for _i in 1800:
		if direction * (player.position.x - x) >= 0.0 or player.dead or room.finished:
			break
		# The only jump blocker is immediately after the ramp.
		if player.position.x > 1175.0 and player.position.x < 1220.0 and player.is_on_floor():
			player.request_jump()
		await tick()
	player.set_walk_intent(0.0)
	await tick(40)
	check(absf(player.position.x - x) < 25.0 or (room.finished and room.won), "native character traverses route")

func _run() -> void:
	check(root.get_child_count() == 0, "isolated no real autoload")
	state = MemoryState.new()
	state.name = "RunState"
	state.credits = 713
	state.meta_credits = 19
	state.progress = 0
	root.add_child(state)
	build = load("res://scenes/build/build_screen.tscn").instantiate()
	root.add_child(build)
	current_scene = build
	await tick(2)
	var build_id: int = build.get_instance_id()
	_place_fixture_body()
	await tick(2)
	var snapshot := state_bytes()
	var saves: int = state.saves
	var credits_before: int = state.credits
	build.get_node("Margin/Root/Body/StatusPanel/StatusBox/SliceButton").pressed.emit()
	room = current_scene
	check(room != build and room.scene_file_path == "res://scenes/arena/playable_slice.tscn", "native entry opens slice")
	check(build.get_parent() == room and not build.visible and build.process_mode == Node.PROCESS_MODE_DISABLED, "original hatchery is suspended")
	check(room.profile != null and room.profile.support_legs == 2 and room.profile.claws == 1, "slice reads the real assembly")
	check(is_equal_approx(float(room.player.tuning.get("walk_speed")), 150.0) and is_equal_approx(float(room.player.tuning.get("damage")), 12.0), "capabilities come from the assembly, not the scene default")
	check(is_equal_approx(room.player.hp, room.player.max_hp) and room.player.max_hp > 80.0, "assembly mass drives max hp")
	check(not room.try_finish(), "exit locked with authored enemies including dormant")
	await tick(90)
	var player = room.player
	var enemies: Array = room.enemies.get_children()
	check(enemies.size() == 3 and not enemies[0].is_physics_processing(), "three enemies start dormant")
	var start: Vector2 = player.position
	player.position = Vector2(enemies[0].position.x - 70.0, 549.0)
	var hp_before_activation: float = player.hp
	await tick(5)
	check(enemies[0].is_physics_processing() and player.hp < hp_before_activation, "proximity activates real enemy AI and damage")
	player.position = start
	player.external_velocity = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.vertical_speed = 0.0
	for target in enemies:
		target.set_physics_process(false)
	# Complete route with ordinary motor input; freeze enemies only during traversal measurement.
	for enemy in enemies:
		room.active[enemy.get_instance_id()] = true
	await walk_to(1320.0)
	check(player.jump_count > 0, "route actually includes physical jump")
	# Combat verifies direction and cooldown before killing the fixtures.
	var enemy = enemies[0]
	player.position = Vector2(enemy.position.x - 100.0, 549.0)
	player.velocity = Vector2.ZERO
	player.external_velocity = Vector2.ZERO
	await tick(2)
	player.set_walk_intent(-1.0)
	player.set_walk_intent(0.0)
	var hp: float = enemy.hp
	check(player.attack(), "attack accepted when ready")
	check(enemy.hp == hp, "attack cannot hit behind facing")
	check(not player.attack(), "miss still consumes attack cooldown")
	await tick(30)
	player.set_walk_intent(1.0)
	player.set_walk_intent(0.0)
	check(player.attack() and enemy.hp < hp, "front-facing attack damages enemy")
	var player_hp: float = player.hp
	player.take_hit(8.0, player.position + Vector2.RIGHT)
	player.take_hit(8.0, player.position + Vector2.RIGHT)
	check(is_equal_approx(player.hp, player_hp - 8.0), "invulnerability prevents immediate double damage")
	check(player.external_velocity.length() > 0.0, "damage creates native knockback")
	await tick(60)
	for target in enemies:
		player.position = Vector2(target.position.x - 100.0, 549.0)
		player.velocity = Vector2.ZERO
		player.external_velocity = Vector2.ZERO
		player.set_walk_intent(1.0)
		player.set_walk_intent(0.0)
		await tick(2)
		for _i in 10:
			if target.dead:
				break
			player.attack()
			await tick(30)
		check(target.dead and target.is_in_group("corpses"), "combat creates lootable corpse")
	check(not room.try_finish(), "organ acquisition required after combat")
	var elite = enemies[2]
	player.position = Vector2(elite.position.x, 549.0)
	player.velocity = Vector2.ZERO
	await tick(3)
	var loot_before: int = elite.loot.size()
	# A full bag must not destroy corpse loot.
	var parasite: OrganData = OrganLibrary.catalog()[&"parasite"]
	for _i in 9:
		room.pack.add_organ(parasite)
	check(not room.interact() and elite.loot.size() == loot_before, "full pack leaves corpse loot intact")
	room.pack.restore([])
	check(room.interact() and room.pack.snapshot().size() == 1 and elite.loot.size() == loot_before - 1, "real organ acquired atomically")
	for _i in 4:
		room.interact()
	var acquired: int = room.pack.snapshot().size()
	check(acquired >= 1 and acquired <= loot_before and acquired + elite.loot.size() == loot_before, "corpse organ conservation including bag capacity")
	var corpse_left: int = elite.loot.size()
	room.interact()
	check(room.pack.snapshot().size() == acquired and elite.loot.size() == corpse_left, "repeated loot cannot duplicate organs")
	await walk_to(2760.0)
	await tick(3)
	check(room.finished and room.won, "native exit overlap completes slice")
	check(not room.try_finish(), "completion latched once")
	# 胜利结算：进度、代币、胃一次性写入，且只写一次
	check(state.progress == 1, "victory advances run progress")
	check(state.saves == saves + 1, "victory writes exactly one save")
	check(state.credits > credits_before and room.reward_total > 0, "victory awards credits")
	check(state.backpack.size() == room.pack.snapshot().size(), "looted organs move into the run backpack")
	var post_victory := state_bytes()
	check(post_victory != snapshot, "settlement changes run state on purpose")
	room.get_node("HUD/Result/Box/Return").pressed.emit()
	await tick(3)
	check(current_scene == build and build.get_instance_id() == build_id and build.visible, "victory returns exact hatchery instance")
	check(state_bytes() == post_victory and state.saves == saves + 1, "returning does not write again")
	# Failure and retry rebuild slice only, while the exact hatchery remains suspended.
	build._on_slice()
	room = current_scene
	await tick(90)
	check(room.level == 2, "next entry is the following level")
	var old_id: int = room.get_instance_id()
	room.player.take_hit(999.0, room.player.position + Vector2.RIGHT)
	check(room.finished and not room.won and room.player.dead, "fatal hit shows failure")
	check(not room.player.attack(), "dead player cannot attack")
	check(state_bytes() == post_victory and state.saves == saves + 1, "death writes nothing")
	room.get_node("HUD/Result/Box/Retry").pressed.emit()
	await tick(5)
	room = current_scene
	check(room.get_instance_id() != old_id and not room.finished and not room.player.dead and room.pack.is_empty(), "retry resets player enemies and local inventory")
	check(room.profile != null and room.profile.support_legs == 2 and is_equal_approx(room.player.max_hp, room.profile.max_hp), "retry reuses the entry capability snapshot")
	check(room.level == 2, "retry stays on the same level")
	check(build.get_parent() == room and build.get_instance_id() == build_id, "retry preserves hatchery instance")
	room.get_node("HUD/Margin/Box/Row/Return").pressed.emit()
	await tick(3)
	check(current_scene == build and state_bytes() == post_victory and state.saves == saves + 1, "abort after retry keeps the post-victory state")
	# 已通关后按「出发」应当开新一轮，而不是进入不存在的关卡
	state.progress = EconomyTuning.get_tuning().total_levels
	build._on_slice()
	await tick(3)
	check(current_scene == build, "completed run does not enter another level")
	check(state.progress == 0 and state.organs.is_empty() and state.backpack.is_empty(), "completed run resets progress, assembly and backpack")
	check(state.meta_credits == 19, "new run keeps meta credits")
	print("PLAYABLE_SLICE_CHECK ", "PASS" if errors.is_empty() else "FAIL", " frames=", frame, " failures=", errors, " writes_during_run=", state.saves - saves)
	build.free()
	state.free()
	quit(0 if errors.is_empty() else 1)
