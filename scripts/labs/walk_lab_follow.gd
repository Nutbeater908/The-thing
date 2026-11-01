extends "res://scripts/labs/procedural_walk_lab.gd"
## Generic walk-lab camera follow. Controls, HUD and reset stay in the base lab.
@onready var _camera: Camera2D = $Camera2D

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(walker):
		_camera.position.x = walker.position.x
