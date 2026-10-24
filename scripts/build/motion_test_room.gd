extends Node2D
## Temporary scene owner only. RunState is never read, modified, or used as a scene store.
var suspended_build: Control
var _previous_process_mode: int
var held: Dictionary = {}
@onready var walker = $Walker
@onready var status: Label = $HUD/Panel/Box/Status

func prepare(spec: Resource) -> Array:
	return $Walker.configure(spec)

func enter_from(build: Control) -> void:
	suspended_build = build
	_previous_process_mode = build.process_mode
	var tree := build.get_tree()
	build.get_parent().remove_child(build)
	build.process_mode = Node.PROCESS_MODE_DISABLED
	build.hide()
	add_child(build)
	tree.root.add_child(self)
	tree.current_scene = self

func _ready() -> void:
	$HUD/Panel/Box/Return.pressed.connect(return_to_build)

func return_to_build() -> void:
	if not is_instance_valid(suspended_build):
		return
	var tree := get_tree()
	var build := suspended_build
	suspended_build = null
	walker.set_walk_intent(0.0)
	held.clear()
	remove_child(build)
	tree.root.add_child(build)
	build.process_mode = _previous_process_mode
	build.show()
	tree.current_scene = build
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.physical_keycode == KEY_SPACE and event.pressed:
			walker.request_jump()
			get_viewport().set_input_as_handled()
		if event.physical_keycode in [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT]:
			held[event.physical_keycode] = event.pressed
			var right := bool(held.get(KEY_D, false)) or bool(held.get(KEY_RIGHT, false))
			var left := bool(held.get(KEY_A, false)) or bool(held.get(KEY_LEFT, false))
			walker.set_walk_intent(float(right) - float(left))
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held.clear()
		if is_instance_valid(walker):
			walker.set_walk_intent(0.0)

func _process(_delta: float) -> void:
	$Camera2D.position.x = walker.position.x
	status.text = "参考质量 %.1f · 重心 %s\n%s · 支撑 %d/2 · 步数 %d · 跳跃 %d\n拒绝步态 %d · 姿态安全失败 %d" % [walker.mass, walker.center_of_mass, walker.jump_phase, walker.support_count, walker.completed_steps.size(), walker.jump_count, walker.rejected_steps, walker.pose_safety_failures]
