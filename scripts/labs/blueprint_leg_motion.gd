extends Resource
## Explicit locomotion definition. No gameplay stats or inferred ports/cell extrema.
## Optional family reference metadata is checked only by the hatchery test bridge.
@export var reference_cells: Array[Vector2i] = []
@export var reference_cell_size: float = 0.0
@export var organ: Resource
@export var mount: Vector2 = Vector2.ZERO # organ-local cells, relative to root cell center
@export var direction: Vector2 = Vector2.DOWN
@export var upper_length: float = 46.0
@export var lower_length: float = 46.0
@export var bend: int = 1
