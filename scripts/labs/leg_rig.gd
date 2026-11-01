class_name LegRig
extends Resource
## One leg's body-local geometry. Pixels, never derived from organ cells at runtime.
## Empty tuning.legs falls back to two legs synthesized from the legacy scalar fields.
@export var mount: Vector2 = Vector2.ZERO
@export var rest_foot_offset: float = 0.0
@export var upper_length: float = 46.0
@export var lower_length: float = 46.0
@export var bend: float = 1.0
