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
	# One length authority: each explicit motion resource, not cells or gait defaults.
	var specs: Array[LegRig] = []
	for i in layout.legs.size():
		var motion = layout.legs[i].motion
		var rig := LegRig.new()
		rig.mount = layout.legs[i].mount
		# Keep the verified neutral foot offset relative to each hip.
		var side := -1.0 if i == 0 else (1.0 if i == layout.legs.size() - 1 else 0.0)
		rig.rest_foot_offset = rig.mount.x + side * (tuning.rest_foot_spacing - tuning.hip_half_spacing)
		rig.upper_length = motion.upper_length
		rig.lower_length = motion.lower_length
		rig.bend = float(motion.bend)
		specs.append(rig)
	tuning.upper_length = layout.legs[0].motion.upper_length
	tuning.lower_length = layout.legs[0].motion.lower_length
	tuning.legs = specs
	# One leg cannot alternate support; the explicit gait follows the compiled leg count.
	tuning.gait = 1 if specs.size() == 1 else 0
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
	# Hit rigs are instanced per leg from the shared single-leg scene.
	_refresh_rig()
	return []

func _ready() -> void:
	super._ready()
	mass = layout.mass
	inertia = layout.inertia
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = layout.com

func _bend_direction(leg: int = 0) -> float:
	# Read layout directly so a live motion-resource edit still reaches the solver.
	return float(layout.legs[leg].motion.bend)

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
