extends Resource
## Deliberately not an alive/link validator. Anchors are root CELL CENTERS.
## Legs' OrganData cells contribute reference-pose virtual mass, not torso colliders.
@export var title: String = ""
@export var cell_size: float = 16.0
## Pure translation of the authored cell-center frame; never resizes/reorders organs.
@export var frame_origin: Vector2 = Vector2.ZERO
@export var organs: Array[Dictionary] = [] # {data: OrganData, anchor: Vector2i, rotation: int, motion?: Resource}

func compile() -> Dictionary:
	var errors: Array[String] = []
	var fixed: Array[Dictionary] = []
	var legs: Array[Dictionary] = []
	var occupied := {}
	var total := 0.0
	var weighted := Vector2.ZERO
	var samples: Array[Dictionary] = []
	if not is_finite(cell_size) or cell_size <= 0.0:
		return {"errors": ["Invalid cell size"]}
	for index in range(organs.size()):
		var entry := organs[index]
		var data = entry.get("data")
		if not data is OrganData or not entry.get("anchor") is Vector2i or not entry.get("rotation") is int:
			errors.append("Invalid organ/anchor/rotation at %d" % index)
			continue
		var rotation: int = entry.rotation
		if rotation < 0 or rotation > 3 or data.cells.is_empty() or not is_finite(data.mass_per_cell) or data.mass_per_cell <= 0.0 or data.scale_factor != 1.0:
			errors.append("Invalid mass/cells/rotation/scale at %d" % index)
			continue
		if data.limb not in [OrganData.Limb.NONE, OrganData.Limb.LEG]:
			errors.append("Only fixed organs and downward walking legs supported")
			continue
		var is_leg: bool = data.limb == OrganData.Limb.LEG
		for cell in data.rotated_cells(rotation):
			var grid: Vector2i = entry.anchor + cell
			if occupied.has(grid):
				errors.append("Overlapping reference cells at %s" % grid)
			occupied[grid] = index
			var point := (Vector2(grid) - frame_origin) * cell_size
			total += data.mass_per_cell
			weighted += point * data.mass_per_cell
			samples.append({"position": point, "mass": data.mass_per_cell})
			if not is_leg:
				fixed.append({"grid": grid, "position": point, "organ": index, "color": data.color})
		if is_leg:
			var motion = entry.get("motion")
			if motion == null or motion.get_script() != preload("res://scripts/labs/blueprint_leg_motion.gd"):
				errors.append("Missing explicit leg motion definition")
				continue
			if motion.organ != data or not motion.mount.is_finite() or not motion.direction.is_finite() or not is_finite(motion.upper_length) or not is_finite(motion.lower_length) or minf(motion.upper_length, motion.lower_length) <= 2.0 or motion.bend not in [-1, 1]:
				errors.append("Invalid explicit leg motion data")
				continue
			var turn := rotation * PI / 2.0
			var direction: Vector2 = motion.direction.rotated(turn)
			if not direction.is_equal_approx(Vector2.DOWN):
				errors.append("Unsupported leg direction: downward only")
				continue
			var mount: Vector2 = Vector2(entry.anchor) + motion.mount.rotated(turn)
			legs.append({"mount": (mount - frame_origin) * cell_size, "motion": motion, "organ": index})
	if legs.is_empty() or legs.size() > 6:
		errors.append("One to six supported downward legs required")
	if fixed.is_empty():
		errors.append("No fixed torso cells")
	for leg in legs:
		var attached := false
		for cell in fixed:
			# Downward mount is explicitly on the LOWER EDGE of a real fixed cell.
			if leg.mount.is_equal_approx(cell.position + Vector2.DOWN * cell_size * 0.5):
				attached = true
		if not attached:
			errors.append("Leg mount must meet a fixed cell lower-edge center")
	if legs.size() >= 2:
		for i in range(1, legs.size()):
			if legs[i - 1].mount.x >= legs[i].mount.x or not is_equal_approx(legs[i - 1].mount.y, legs[i].mount.y):
				errors.append("Supported mounts must be ordered left/right at equal height")
				break
		var a = legs[0].motion
		for i in range(1, legs.size()):
			var b = legs[i].motion
			if a.upper_length != b.upper_length or a.lower_length != b.lower_length or a.bend != b.bend:
				errors.append("This adapter supports one shared bone pair and bend branch only")
				break
	# A disconnected fixed component would unrealistically become a welded torso.
	if not fixed.is_empty():
		var connected := {fixed[0].grid: true}
		for _pass in range(fixed.size()):
			for cell in fixed:
				for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if connected.has(cell.grid + delta):
						connected[cell.grid] = true
		if connected.size() != fixed.size():
			errors.append("Disconnected fixed torso cells")
	if total <= 0.0 or not is_finite(total) or not weighted.is_finite():
		errors.append("Invalid aggregate mass")
	if not errors.is_empty():
		return {"errors": errors}
	var com := weighted / total
	var moment := 0.0
	for sample in samples:
		moment += sample.mass * (sample.position.distance_squared_to(com) + cell_size * cell_size / 6.0)
	if not com.is_finite() or not is_finite(moment) or moment <= 0.0:
		return {"errors": ["Invalid mass moment"]}
	return {"errors": errors, "fixed": fixed, "legs": legs, "mass": total, "com": com, "inertia": moment}
