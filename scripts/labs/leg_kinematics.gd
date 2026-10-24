extends RefCounted
## Scene-free triangle authority for predictive capsule queries and physical angle targets.
## Point conversion retains projection/sqrt; angle conversion retains the legacy acos
## order (including DOWN-axis convention, fixed branch, margin and reach tolerance).
static func _triangle(delta: Vector2, upper: float, lower: float, margin: float, angles: bool) -> PackedFloat64Array:
	var distance := clampf(delta.length(), absf(upper - lower) + margin, upper + lower - margin)
	if angles:
		var spread := acos(clampf((upper * upper + distance * distance - lower * lower) / (2.0 * upper * distance), -1.0, 1.0))
		var knee := PI - acos(clampf((upper * upper + lower * lower - distance * distance) / (2.0 * upper * lower), -1.0, 1.0))
		return PackedFloat64Array([distance, spread, knee])
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	return PackedFloat64Array([distance, along, height])

## Angles rotate the local DOWN axis; fixed forward-knee branch. Public API unchanged.
static func solve(hip: Vector2, foot: Vector2, upper: float, lower: float) -> Dictionary:
	var delta := foot - hip
	var triangle := _triangle(delta, upper, lower, 0.01, true)
	return {"hip": atan2(-delta.x, delta.y) - triangle[1], "knee": triangle[2], "distance": triangle[0], "reachable": absf(triangle[0] - delta.length()) < 0.02}

## World knee/foot points; caller owns the reach margin and bend branch.
static func solve_points(hip: Vector2, target: Vector2, upper: float, lower: float, margin: float, bend: float = 1.0) -> Array[Vector2]:
	var delta := target - hip
	var triangle := _triangle(delta, upper, lower, margin, false)
	var axis := delta.normalized() if delta.length_squared() > 0.0 else Vector2.DOWN
	return [hip + axis * triangle[1] + Vector2(axis.y, -axis.x) * triangle[2] * bend, hip + axis * triangle[0]]

static func torque(target: float, angle: float, velocity: float, kp: float, kd: float, cap: float) -> float:
	return clampf(kp * wrapf(target - angle, -PI, PI) - kd * velocity, -cap, cap)

## Passive unilateral spring/damper outside the anatomical angle interval.
## Finite, capped torque: compliant stops, NOT an exact solver hard constraint.
static func stop_torque(angle: float, velocity: float, lower: float, upper: float, kp: float, kd: float, cap: float, delta: float, inverse_inertia_sum: float) -> float:
	angle = wrapf(angle, -PI, PI)
	# Backward-Euler spring/damper avoids explicit high-stiffness torque chatter.
	var denominator := 1.0 + (kd * delta + kp * delta * delta) * inverse_inertia_sum
	if angle < lower:
		return clampf((kp * (lower - angle) - (kd + kp * delta) * velocity) / denominator, 0.0, cap)
	if angle > upper:
		return clampf((kp * (upper - angle) - (kd + kp * delta) * velocity) / denominator, -cap, 0.0)
	return 0.0

