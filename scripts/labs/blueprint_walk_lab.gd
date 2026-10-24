extends Node2D
## Standalone manual comparison. No InputMap/autoload/build/session integration.
const FIXTURES := [preload("res://resources/labs/blueprint_normal.tres"), preload("res://resources/labs/blueprint_moved_mount.tres"), preload("res://resources/labs/blueprint_mass_shift.tres")]
var walker
var selected: int = 0
var held: Dictionary = {}
var rejection: String = ""
@onready var status: Label = $HUD/Panel/Box/Status
@onready var selector: OptionButton = $HUD/Panel/Box/Selector

func _ready() -> void:
	for fixture in FIXTURES:
		selector.add_item(fixture.title)
	select_blueprint(0)

func select_blueprint(index: int) -> void:
	if index < 0 or index >= FIXTURES.size():
		return
	selected = index
	selector.select(index)
	replace_rig(FIXTURES[index])

func replace_rig(spec: Resource) -> void:
	# Detach/free whole previous body and Areas; never teleport an integrating rig.
	held.clear()
	if is_instance_valid(walker):
		remove_child(walker)
		walker.queue_free()
	walker = null
	var body = preload("res://scripts/labs/blueprint_walker.gd").new()
	var errors: Array = body.configure(spec)
	if not errors.is_empty():
		rejection = "REJECTED: " + "; ".join(errors)
		body.free()
		return
	rejection = ""
	body.name = "BlueprintWalker"
	body.position = Vector2(640, 464)
	walker = body
	add_child(body)

func _on_selected(index: int) -> void:
	select_blueprint(index)

func _on_reset_pressed() -> void:
	select_blueprint(selected)

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(walker):
		return
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
	if not is_instance_valid(walker):
		status.text = rejection
		return
	status.text = "Mass %.1f | local COM (%.2f, %.2f) | inertia %.1f\n%s | support %d/2 | steps %d | jumps %d | speed %.1f\nHips %s / %s | rejected %d | aborted %d" % [walker.mass, walker.center_of_mass.x, walker.center_of_mass.y, walker.inertia, walker.jump_phase, walker.support_count, walker.completed_steps.size(), walker.jump_count, walker.linear_velocity.x, walker.layout.legs[0].mount, walker.layout.legs[1].mount, walker.rejected_steps, walker.aborted_steps]
