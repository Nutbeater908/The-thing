## 双腿步态协调器：管理支撑/摆动交替，不用固定偏移造假。
class_name GaitController
extends RefCounted

enum Leg { NEAR, FAR }
enum State { BOTH_GROUNDED, NEAR_SWING, FAR_SWING, AIRBORNE }

var state := State.BOTH_GROUNDED
var near_foot := Vector2.ZERO   ## 近侧脚的世界位置
var far_foot := Vector2.ZERO    ## 远侧脚的世界位置
var stride_length := 60.0       ## 步长
var step_height := 26.0         ## 抬脚高度（相对新站姿高度重算）
var step_duration := 0.22       ## 单步时长（快一点才有动感）
var ground_probe: PhysicsDirectSpaceState2D = null  ## 地面探测
var collision_mask := 1         ## 地形层
var excluded_body: CollisionObject2D = null  ## 打射线时排除自己
var leg_length := 0.0           ## 髋→脚底 的站立高度，用于射线打空时的兜底

var _swing_timer := 0.0
var _swing_start := Vector2.ZERO
var _swing_target := Vector2.ZERO
var _hip_y := 0.0


## 初始化双脚位置（站立时两脚在髋点下方）
func init_stance(hip_world: Vector2, stand_height: float) -> void:
	leg_length = stand_height
	var ground_y := hip_world.y + stand_height
	near_foot = Vector2(hip_world.x, ground_y)
	far_foot = Vector2(hip_world.x, ground_y)
	state = State.BOTH_GROUNDED
	_hip_y = hip_world.y


## 每帧更新，返回当前两脚的目标位置
func update(delta: float, hip_world: Vector2, velocity: Vector2, is_grounded: bool) -> Dictionary:
	_hip_y = hip_world.y
	
	if not is_grounded:
		state = State.AIRBORNE
		return {"near": near_foot, "far": far_foot}
	
	# 落地后恢复支撑，重新探测地面
	if state == State.AIRBORNE:
		state = State.BOTH_GROUNDED
		_swing_timer = 0.0
		near_foot = _probe_ground(Vector2(hip_world.x, 0.0), hip_world.y)
		far_foot = near_foot
	
	# 静止时不换步
	if absf(velocity.x) < 5.0:
		return {"near": near_foot, "far": far_foot}
	
	# 支撑腿完全锁定（真实走路时支撑脚钉在地面）
	var hip_x := hip_world.x
	match state:
		State.BOTH_GROUNDED:
			# 只检测：哪只脚离髋点更远就迈哪只
			var near_dist := absf(near_foot.x - hip_x)
			var far_dist := absf(far_foot.x - hip_x)
			if near_dist >= stride_length * 0.5 and near_dist >= far_dist:
				_start_swing(Leg.NEAR, hip_world, velocity)
			elif far_dist >= stride_length * 0.5:
				_start_swing(Leg.FAR, hip_world, velocity)
		
		State.NEAR_SWING:
			_swing_timer += delta
			var t := minf(_swing_timer / step_duration, 1.0)
			near_foot = _swing_lerp(_swing_start, _swing_target, t)
			if t >= 1.0:
				near_foot = _swing_target
				state = State.BOTH_GROUNDED
				_swing_timer = 0.0
		
		State.FAR_SWING:
			_swing_timer += delta
			var t := minf(_swing_timer / step_duration, 1.0)
			far_foot = _swing_lerp(_swing_start, _swing_target, t)
			if t >= 1.0:
				far_foot = _swing_target
				state = State.BOTH_GROUNDED
				_swing_timer = 0.0
	
	return {"near": near_foot, "far": far_foot}


func _start_swing(which: Leg, hip_world: Vector2, velocity: Vector2) -> void:
	# 落脚点：向移动方向迈出，从髋点高度向下探测地面
	var move_dir := signf(velocity.x) if absf(velocity.x) > 5.0 else 1.0
	var target_x := hip_world.x + move_dir * stride_length * 0.6
	var target := _probe_ground(Vector2(target_x, 0.0), hip_world.y)
	
	if which == Leg.NEAR:
		state = State.NEAR_SWING
		_swing_start = near_foot
		_swing_target = target
	else:
		state = State.FAR_SWING
		_swing_start = far_foot
		_swing_target = target
	
	_swing_timer = 0.0


func _swing_lerp(start: Vector2, target: Vector2, t: float) -> Vector2:
	var x := lerpf(start.x, target.x, t)
	var y := lerpf(start.y, target.y, t)
	# 抛物线抬脚
	var lift := step_height * sin(t * PI)
	return Vector2(x, y - lift)


## 射线探测地面（从髋点高度向下打，避免起点已在地面之下）
func _probe_ground(from: Vector2, hip_y := 0.0) -> Vector2:
	# 兜底：按站立高度推地面，绝不能返回 y=0
	var fallback := Vector2(from.x, (hip_y if hip_y != 0.0 else from.y) + leg_length)
	
	if ground_probe == null:
		return fallback
	
	var origin := Vector2(from.x, hip_y if hip_y != 0.0 else from.y)
	var query := PhysicsRayQueryParameters2D.create(origin, origin + Vector2(0.0, 400.0))
	query.collision_mask = collision_mask
	if excluded_body != null:
		query.exclude = [excluded_body.get_rid()]
	var result := ground_probe.intersect_ray(query)
	
	if result.is_empty():
		return fallback
	return Vector2(from.x, result["position"].y)
