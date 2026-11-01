extends Node2D
## Scene-authored UI; direct physical-key handling avoids changing the project's InputMap.
@onready var walker = $Walker
@onready var status: Label = $HUD/Panel/Box/Status
@onready var block: StaticBody2D = $Block
var held: Dictionary = {}

func _ready() -> void:
	set_block_enabled(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.physical_keycode == KEY_SPACE and event.pressed:
			walker.request_jump()
			get_viewport().set_input_as_handled()
		if event.physical_keycode in [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT]:
			held[event.physical_keycode] = event.pressed
			_update_intent()
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held.clear()
		if is_instance_valid(walker):
			walker.set_walk_intent(0.0)

func _update_intent() -> void:
	var right := bool(held.get(KEY_D, false)) or bool(held.get(KEY_RIGHT, false))
	var left := bool(held.get(KEY_A, false)) or bool(held.get(KEY_LEFT, false))
	walker.set_walk_intent(float(right) - float(left))

func _process(_delta: float) -> void:
	status.text = "%s | support %d/%d | swing %d | steps %d\nRejected %d | aborted %d | speed %.1f | jumps %d" % [walker.jump_phase, walker.support_count, walker.leg_count(), walker.swing_leg, walker.completed_steps.size(), walker.rejected_steps, walker.aborted_steps, walker.linear_velocity.x, walker.jump_count]

func _on_reset_pressed() -> void:
	held.clear()
	walker.reset_walker()

func set_block_enabled(enabled: bool) -> void:
	block.visible = enabled
	block.get_node("Shape").set_deferred("disabled", not enabled)

func _on_block_toggled(enabled: bool) -> void:
	set_block_enabled(enabled)
