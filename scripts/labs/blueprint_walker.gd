extends "res://scripts/labs/procedural_walker.gd"
## Geometry/mass adapter only. All motion, IK, sweeps, hit poses, support and jumps
## are inherited unchanged from the verified procedural controller.
var blueprint: Resource
var layout: Dictionary

func configure(spec: Resource) -> Array:
	blueprint = spec
	layout = spec.compile()
	if not layout.errors.is_empty():
		return layout.errors
	tuning = preload("res://resources/labs/procedural_walk.tres").duplicate()
	# One length authority: the explicit motion resource, not cells or gait defaults.
	tuning.upper_length = layout.legs[0].motion.upper_length
	tuning.lower_length = layout.legs[0].motion.lower_length
	collision_layer = 512
	collision_mask = 256
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	linear_damp = 0.0
	angular_damp = 0.0
	for index in range(layout.fixed.size()):
		var cell: Dictionary = layout.fixed[index]
		var collider := CollisionShape2D.new()
		collider.name = "Cell%d" % index
		collider.position = cell.position
		collider.set_meta("organ_index", cell.organ)
		collider.set_meta("grid_cell", cell.grid)
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2.ONE * spec.cell_size
		collider.shape = rectangle
		add_child(collider)
	# Fixed limb structure is authored once; organ-cell colliders remain data-instanced.
	add_child(preload("res://scenes/labs/leg_hitboxes.tscn").instantiate())
	return []

func _ready() -> void:
	super._ready()
	mass = layout.mass
	inertia = layout.inertia
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = layout.com

func _hip(pose: Transform2D, leg: int) -> Vector2:
	return pose * layout.legs[leg].mount

func _rest_foot_x(pose: Transform2D, leg: int) -> float:
	# Moving a mount moves that leg's actual neutral workspace, not just its drawing.
	return _hip(pose, leg).x + (-1.0 if leg == 0 else 1.0) * (tuning.rest_foot_spacing - tuning.hip_half_spacing)

func _bend_direction() -> float:
	return float(layout.legs[0].motion.bend)

func _draw() -> void:
	for cell in layout.get("fixed", []):
		var rect := Rect2(cell.position - Vector2.ONE * blueprint.cell_size * 0.5, Vector2.ONE * blueprint.cell_size)
		draw_rect(rect, cell.color)
		draw_rect(rect, Color(0.1, 0.12, 0.16), false, 1.0)
	if layout.has("com"):
		draw_circle(layout.com, 3.0, Color.MAGENTA)
		for leg in layout.legs:
			draw_circle(leg.mount, 4.0, Color.WHITE)
	super._draw()
