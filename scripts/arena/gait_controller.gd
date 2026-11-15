## 双腿步态协调器：管理支撑/摆动交替，不用固定偏移造假。
class_name GaitController
extends RefCounted

enum Leg { NEAR, FAR }
enum State { BOTH_GROUNDED, NEAR_SWING, FAR_SWING, AIRBORNE }

var state := State.BOTH_GROUNDED
var near_foot := Vector2.ZERO   ## 近侧脚的世界位置
var far_foot := Vector2.ZERO    ## 远侧脚的世界位置
var stride_length := 60.0       ## 步长
var step_height := 20.0         ## 抬脚高度
var step_duration := 0.25       ## 单步时长
var ground_probe: PhysicsDirectSpaceState2D = null  ## 地面探测
var collision_mask := 1         ## 地形层

var _swing_timer := 0.0
var _swing_start := Vector2.ZERO
var _swing_target := Vector2.ZERO


## 初始化双脚位置（站立时两脚在髋点下方）
func init_stance(hip_world: Vector2, leg_length: float) -> void:
	var ground_y := hip_world.y + leg_length
	near_foot = Vector2(hip_world.x, ground_y)
	far_foot = Vector2(hip_world.x, ground_y)
	state = State.BOTH_GROUNDED


## 每帧更新，返回当前两脚的目标位置
func update(delta: float, hip_world: Vector2, velocity: Vector2, is_grounded: bool) -> Dictionary:
	if not is_grounded:
		state = State.AIRBORNE
		return {"near": near_foot, "far": far_foot}
	
	# 落地后恢复支撑
	if state == State.AIRBORNE:
		state = State.BOTH_GROUNDED
		_swing_timer = 0.0
		# 重新探测双脚位置
		near_foot = _probe_ground(Vector2(hip_world.x, hip_world.y + 200.0))
		far_foot = near_foot
	
	# 静止时不换步
	if absf(velocity.x) < 5.0:
		return {"near": near_foot, "far": far_foot}
	
	# 支撑腿跟随髋点水平移动
	var hip_x := hip_world.x
	match state:
		State.BOTH_GROUNDED:
			# 选择离髋较远的那只脚开始迈步
			var near_dist := absf(near_foot.x - hip_x)
			var far_dist := absf(far_foot.x - hip_x)
			if near_dist > stride_length * 0.6:
				_start_swing(Leg.NEAR, hip_world, velocity)
			elif far_dist > stride_length * 0.6:
				_start_swing(Leg.FAR, hip_world, velocity)
		
		State.NEAR_SWING:
			_swing_timer += delta
			var t := minf(_swing_timer / step_duration, 1.0)
			near_foot = _swing_lerp(_swing_start, _swing_target, t)
			if t >= 1.0:
				state = State.BOTH_GROUNDED
				_swing_timer = 0.0
			# 支撑腿跟随
			far_foot.x = hip_x
		
		State.FAR_SWING:
			_swing_timer += delta
			var t := minf(_swing_timer / step_duration, 1.0)
			far_foot = _swing_lerp(_swing_start, _swing_target, t)
			if t >= 1.0:
				state = State.BOTH_GROUNDED
				_swing_timer = 0.0
			# 支撑腿跟随
			near_foot.x = hip_x
	
	return {"near": near_foot, "far": far_foot}


func _start_swing(which: Leg, hip_world: Vector2, velocity: Vector2) -> void:
	var target_x := hip_world.x + signf(velocity.x) * stride_length * 0.5
	var target := _probe_ground(Vector2(target_x, hip_world.y + 200.0))
	
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


## 射线探测地面
func _probe_ground(from: Vector2) -> Vector2:
	if ground_probe == null:
		return from
	
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, 300.0))
	query.collision_mask = collision_mask
	var result := ground_probe.intersect_ray(query)
	
	if result.is_empty():
		return from
	return result["position"]
