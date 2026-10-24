## 关卡原型：把 RunState 里的蓝图变成一只物理生物。
extends Node2D

@onready var _camera: Camera2D = $Camera2D
@onready var _exit: Area2D = $Exit

var _body: CreatureBody
var _finished := false
var _corpse: Enemy = null


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.10, 0.09, 0.12))

	var run_state := get_node_or_null("/root/RunState")
	if run_state == null:
		push_error("RunState autoload 未加载")
		return

	_body = CreatureBody.new()
	_body.position = $Spawn.position
	add_child(_body)
	_body.setup(run_state.organs, run_state.links)
	_body.died.connect(_on_creature_died)
	_exit.body_entered.connect(_on_exit_entered)

	_spawn_enemies(run_state.progress + 1)


## 硬编码的三关配置，仅用于验证多关卡链路
func _spawn_enemies(level: int) -> void:
	var types := {
		&"grunt": load("res://resources/enemies/grunt.tres"),
		&"elite": load("res://resources/enemies/elite.tres"),
	}

	var plan: Array = []
	match level:
		1:
			plan = [[&"grunt", 700.0]]
		2:
			plan = [[&"grunt", 700.0], [&"grunt", 900.0], [&"elite", 1100.0]]
		_:
			plan = [[&"grunt", 700.0], [&"grunt", 900.0], [&"elite", 1100.0], [&"elite", 1300.0]]

	for entry in plan:
		var enemy := Enemy.new()
		enemy.data = types[entry[0]]
		enemy.position = Vector2(entry[1], 530.0)
		add_child(enemy)


## 到达出口：保留存活器官与损伤，按原价一半发放奖励
func _on_exit_entered(body) -> void:
	if _finished or body != _body:
		return
	_finished = true

	var run_state := get_node_or_null("/root/RunState")
	if run_state != null:
		run_state.organs = _body.export_organs()
		run_state.progress += 1
		run_state.earn(_clear_reward(run_state.organs))

		# 通关最后一关：100% 折算局外代币，本轮结束
		if run_state.is_run_complete():
			run_state.bank_progress()
			run_state.reset_run()

	get_tree().change_scene_to_file("res://scenes/build/build_screen.tscn")


## 打开搜刮界面
func _open_corpse(corpse: Enemy) -> void:
	var window := LootWindow.new()
	add_child(window)
	window.setup(corpse)


func _clear_reward(organs: Array) -> int:
	var lib := OrganLibrary.catalog()
	var total := 0
	for entry in organs:
		var data: OrganData = lib.get(entry["id"])
		if data != null:
			total += floori(data.cost * EconomyTuning.get_tuning().clear_reward_rate)
	return total


func _on_creature_died() -> void:
	var run_state := get_node_or_null("/root/RunState")
	if run_state != null:
		run_state.bank_progress()
		run_state.reset_run()

	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file("res://scenes/build/build_screen.tscn")


func _process(_delta: float) -> void:
	if _body != null:
		_camera.global_position = _body.global_position
	_update_corpse()


## 找最近的可搜刮尸体并高亮
func _update_corpse() -> void:
	if _body == null:
		return

	var best: Enemy = null
	var best_dist := 100.0
	for node in get_tree().get_nodes_in_group("corpses"):
		var d: float = _body.global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node

	if best == _corpse:
		return

	if _corpse != null and is_instance_valid(_corpse):
		_corpse.set_highlighted(false)
	_corpse = best
	if _corpse != null:
		_corpse.set_highlighted(true)


func _unhandled_input(event: InputEvent) -> void:
	if _corpse == null or not is_instance_valid(_corpse):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_open_corpse(_corpse)


## 背景刻度线：给移动速度提供参照
func _draw() -> void:
	var top := -500.0
	var bottom := 700.0
	for x in range(-1200, 2401, 100):
		var major := x % 500 == 0
		var color := Color(0.19, 0.18, 0.22) if major else Color(0.13, 0.12, 0.15)
		draw_line(Vector2(x, top), Vector2(x, bottom), color, 2.0 if major else 1.0)
