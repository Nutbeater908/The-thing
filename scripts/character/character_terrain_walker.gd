extends CharacterBody2D
## Movement/collision are native. External velocity survives held walk input.
@export var tuning: Resource
var walk_intent: float = 0.0
var motor_speed: float = 0.0
var vertical_speed: float = 0.0
var external_velocity := Vector2.ZERO
var jump_requested := false
var jump_count := 0
var snap_suppressed := false
## 外部可锁定水平驱动：锁定后不再响应 walk_intent，保持当前水平速度。
## 用于「空中不能改变速度」这类规则；默认关闭，不影响其他使用者。
var motor_locked := false
var air_control_enabled := false
var air_acceleration := 0.0
var air_speed_limit := 0.0
@onready var _snap_length: float = floor_snap_length

func set_walk_intent(value: float) -> void:
	walk_intent = clampf(value, -1.0, 1.0)

func request_jump() -> bool:
	if not is_on_floor() or jump_requested:
		return false
	jump_requested = true
	return true

func add_knockback(delta_velocity: Vector2) -> void:
	if not delta_velocity.is_finite():
		return
	external_velocity = (external_velocity + delta_velocity).limit_length(tuning.max_knockback)
	if delta_velocity.y < 0.0:
		snap_suppressed = true

func _apply_air_motor(delta: float) -> void:
	if is_zero_approx(walk_intent) or air_acceleration <= 0.0:
		return
	var target := walk_intent * air_speed_limit
	# 同向已有更高惯性速度时不截速；反向输入仍能逐渐制动。
	if motor_speed * signf(target) < absf(target):
		motor_speed = move_toward(motor_speed, target, air_acceleration * delta)

func _physics_process(delta: float) -> void:
	var launching := jump_requested and is_on_floor()
	jump_requested = false
	if launching:
		vertical_speed = -tuning.jump_speed
		jump_count += 1
		snap_suppressed = true
	elif is_on_floor() and not snap_suppressed:
		vertical_speed = 0.0
	else:
		vertical_speed += get_gravity().y * delta
	if not motor_locked:
		if air_control_enabled and (not is_on_floor() or launching):
			_apply_air_motor(delta)
		else:
			var rate: float = tuning.braking if walk_intent == 0.0 else tuning.acceleration
			motor_speed = move_toward(motor_speed, walk_intent * tuning.walk_speed, rate * delta)
	# The previous floor result must not cancel jump or upward knockback at launch.
	if snap_suppressed and not is_on_floor() and vertical_speed + external_velocity.y >= 0.0:
		snap_suppressed = false
	floor_snap_length = 0.0 if snap_suppressed else _snap_length
	velocity = Vector2(motor_speed, vertical_speed) + external_velocity
	var was_grounded := is_on_floor()
	move_and_slide()
	# Use the engine's own snap for seam classification, never during an upward launch.
	if was_grounded and not snap_suppressed and not is_on_floor():
		apply_floor_snap()
	if is_on_floor() and snap_suppressed and velocity.y >= 0.0:
		# A tiny or cancelled upward hit may never separate from the floor.
		snap_suppressed = false
		floor_snap_length = _snap_length
	if is_on_floor() and velocity.y >= 0.0 and not snap_suppressed:
		vertical_speed = 0.0
		external_velocity.y = minf(0.0, external_velocity.y)
	if is_on_ceiling():
		vertical_speed = maxf(0.0, vertical_speed)
		external_velocity.y = maxf(0.0, external_velocity.y)
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if absf(normal.x) > 0.9:
			if external_velocity.dot(normal) < 0.0:
				external_velocity = external_velocity.slide(normal)
			if motor_speed * normal.x < 0.0:
				motor_speed = 0.0
	external_velocity = external_velocity.move_toward(Vector2.ZERO, tuning.knockback_decay * delta)
