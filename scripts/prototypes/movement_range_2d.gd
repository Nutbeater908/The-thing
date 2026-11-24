## Reuses assembled player and native 2D movement; no weapons, enemies or save settlement.
extends "res://scripts/arena/playable_slice.gd"

var checkpoints: Array[Marker2D] = []
var checkpoint_index := 0

func _ready() -> void:
	horizontal_shooting_trial = true
	# Replace only the test scene's old floor with the dedicated static terrain scene.
	for label in ["Terrain", "GroundExtension", "JumpBlock"]:
		var old := get_node(label)
		remove_child(old)
		old.queue_free()
	var ground: Node2D = load("res://scenes/prototypes/movement_terrain_2d.tscn").instantiate()
	ground.name = "Terrain"
	add_child(ground)
	for marker in ground.get_node("Checkpoints").get_children():
		checkpoints.append(marker)
	super._ready()
	respawn_at(0)

func _setup_shooting_trial() -> void:
	# Suppress combat but retain the established return/HUD and dynamic camera.
	enemies.hide()
	for enemy in enemies.get_children():
		enemy.set_physics_process(false)
		enemy.collision_layer = 0
		enemy.collision_mask = 0
		enemy.remove_from_group("enemies")
	$Exit.hide()
	$HUD/Margin/Box/Row/PackToggle.hide()
	$HUD/Margin/Box/Title.text = "大型二维移动测试场 / 长约 22000px"
	$HUD/Margin/Box/Instructions.text = "A/D 移动 · 空格跳跃 · Shift 观察 · F3 碰撞 · [ / ] 切换区段 · R 复位 · Esc 返回"
	body_label.text = "只测试移动 · " + String(player.air_mobility_status.get("reason", "未接入装配能力"))
	$HUD/Margin/Box/Status.show()

func _physics_process(_delta: float) -> void:
	if player.global_position.y > 1600.0:
		respawn_at(checkpoint_index)
	$HUD/Margin/Box/Status.text = "区段 %d/%d：%s | X %.0f | 速度 %.0f | %s | 跑姿抬脚 %.0fpx" % [checkpoint_index+1,checkpoints.size(),checkpoints[checkpoint_index].name,player.position.x,absf(player.velocity.x),"跑" if player._gait != null and player._gait.running else "走",player.run_step_height]

func respawn_at(index: int) -> void:
	checkpoint_index = wrapi(index,0,checkpoints.size())
	player.global_position = checkpoints[checkpoint_index].global_position
	player.velocity = Vector2.ZERO
	player.motor_speed = 0.0
	player.vertical_speed = 0.0
	player.external_velocity = Vector2.ZERO
	player.jump_requested = false
	player.snap_suppressed = false
	player.motor_locked = false
	player._jump_phase = player.JumpPhase.NONE
	player._body_offset_y = 0.0
	player._apply_crouch_shape()
	if player._gait != null:
		player._gait.init_stance(player.global_position,player._gait.stand_height)
		player._gait._has_hip = false
	player.queue_redraw()
	notice.text = "复位至：" + String(checkpoints[checkpoint_index].name)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		return # No gun in this scene.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				return_to_build()
				return
			KEY_R:
				respawn_at(checkpoint_index)
				return
			KEY_BRACKETLEFT:
				respawn_at(checkpoint_index-1)
				return
			KEY_BRACKETRIGHT:
				respawn_at(checkpoint_index+1)
				return
			KEY_J, KEY_K, KEY_E, KEY_TAB:
				return
	super._unhandled_input(event)

func return_to_build() -> void:
	if leaving or not is_instance_valid(suspended_build):
		return
	leaving = true
	var build := suspended_build
	suspended_build = null
	remove_child(build)
	get_tree().root.add_child(build)
	build.process_mode = previous_process_mode
	build.show()
	get_tree().current_scene = build
	build.on_run_finished("移动试验结束，原装配保留。")
	queue_free()
