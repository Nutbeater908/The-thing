## 双腿步态协调器。坐标相对髋点：X 正为机体前方，Y 正向下。
class_name GaitController
extends RefCounted

enum State { BOTH_GROUNDED, NEAR_SWING, FAR_SWING, AIRBORNE }

var state := State.BOTH_GROUNDED
var near_offset := Vector2.ZERO
var far_offset := Vector2.ZERO
var stride_length := 60.0
var step_height := 48.0
var step_duration := 0.38 ## 从速度估算步幅用，不再决定每步摆动时长。
var leg_reach := 0.0  ## 髋到踝的充分伸直距离；0 表示没有几何约束的试验。
var sole_offset := 0.0
var ground_probe: PhysicsDirectSpaceState2D = null
var collision_mask := 256
var excluded_body: CollisionObject2D = null
var stand_height := 0.0

var run_enter_speed := 250.0
var run_exit_speed := 220.0
var run_max_steps_per_second := 3.8
var run_step_height := 48.0
var running := false
const RUN_CONTACT := 0.43
const RUN_BLEND_TIME := 0.13
const AIR_SETTLE_TIME := 0.12
const AIR_MID_SHORTEN := 10.0
const AIR_LAND_LEAD := 0.13
var _run_phase := 0.0
var _run_blend := 0.0
var _run_from_near := Vector2.ZERO
var _run_from_far := Vector2.ZERO
var _air_elapsed := 0.0
var _air_from_near := Vector2.ZERO
var _air_from_far := Vector2.ZERO
var _air_landing_blend := 0.0

var _swing_progress := 0.0
var _swing_start_lift := 0.0
var _finishing_run_step := false
var _swing_distance := 1.0
var _swing_start_x := 0.0
var _swing_target_x := 0.0
var _hip := Vector2.ZERO
var _facing := 1.0
var _has_hip := false

func init_stance(hip_world: Vector2, height: float) -> void:
	stand_height = height
	near_offset = Vector2(0.0, height)
	far_offset = Vector2(0.0, height)
	state = State.BOTH_GROUNDED
	running = false
	_run_blend = 0.0
	_finishing_run_step = false
	_swing_progress = 0.0
	_hip = hip_world
	_has_hip = true

## fwd_vel 为实际运动速度在朝向空间的分量；用帧间位移积分摆动进度。
func update(delta: float, hip: Vector2, fwd_vel: float, facing: float, grounded: bool, plant_only := false, vertical_speed := 0.0) -> Dictionary:
	var next_facing := -1.0 if facing < 0.0 else 1.0
	if not grounded:
		if state != State.AIRBORNE:
			_air_from_near = near_offset
			_air_from_far = far_offset
			_air_elapsed = 0.0
			_air_landing_blend = 0.0
			_run_blend = 0.0
			_run_phase = 0.0
			running = false
		else:
			_air_elapsed += delta
		state = State.AIRBORNE
		_facing = next_facing
		_hip = hip
		_update_air_pose(delta, vertical_speed)
		return _result()

	var landed := state == State.AIRBORNE
	if landed:
		state = State.BOTH_GROUNDED
		_swing_progress = 0.0
	elif next_facing != _facing:
		# 地上转身时保持支撑点的世界位置，不把支撑脚甩到另一边。
		near_offset.x = -near_offset.x
		far_offset.x = -far_offset.x
		_swing_start_x = -_swing_start_x
		_swing_target_x = -_swing_target_x
	_facing = next_facing
	var dx := (hip.x - _hip.x) * _facing if _has_hip and not landed else 0.0
	_hip = hip
	_has_hip = true

	var speed := absf(fwd_vel)
	var wants_run := not landed and not plant_only and absf(dx) > 0.0001 and speed >= (run_exit_speed if running else run_enter_speed)
	if wants_run:
		if not running:
			_run_from_near = near_offset
			_run_from_far = far_offset
			_run_blend = 0.0
			_run_phase = 0.0 if near_offset.x * signf(dx) >= far_offset.x * signf(dx) else 0.5
		running = true
		state = State.BOTH_GROUNDED
		_update_run_pose(delta, dx, speed)
		return _result()
	if running:
		running = false
		_run_blend = 0.0
		# Finish the raised foot with the walking controller instead of snapping it down.
		var near_lift := _ground_offset(near_offset.x) - near_offset.y
		var far_lift := _ground_offset(far_offset.x) - far_offset.y
		if not plant_only and maxf(near_lift, far_lift) > 1.0:
			var swing_near := near_lift >= far_lift
			var foot := near_offset if swing_near else far_offset
			_start_swing(swing_near, signf(fwd_vel), stride_length, stride_length)
			_swing_start_x = foot.x
			_swing_start_lift = maxf(near_lift, far_lift)
			_finishing_run_step = true

	if state != State.NEAR_SWING:
		near_offset.x -= dx
		near_offset.y = _ground_offset(near_offset.x)
	if state != State.FAR_SWING:
		far_offset.x -= dx
		far_offset.y = _ground_offset(far_offset.x)
	if landed or plant_only:
		# 落地或蹬地须优先保证支撑可达；过远的脚向髋点收回必要距离。
		if state != State.NEAR_SWING:
			near_offset = _reachable_support(near_offset)
		if state != State.FAR_SWING:
			far_offset = _reachable_support(far_offset)
	if landed:
		return _result() # 触地当帧两脚贴地，不在同帧重新抬腿。

	var moving := not plant_only and absf(fwd_vel) >= 5.0 and absf(dx) > 0.0001
	if state == State.NEAR_SWING or state == State.FAR_SWING:
		var swing_near := state == State.NEAR_SWING
		var advance := delta / 0.10 if _finishing_run_step or not moving else absf(dx) / _swing_distance
		if moving and not _finishing_run_step:
			var support := far_offset if swing_near else near_offset
			# 突然加速或坡面收窄可达区时宁可提早落脚。
			if support.x * signf(dx) < 0.0 and absf(support.x) + absf(dx) >= _available_x(support.y):
				advance = 1.0
		_step_swing(advance, swing_near)
		return _result()
	if not moving:
		return _result()

	var dir := signf(dx)
	var reach := minf(_available_x(near_offset.y), _available_x(far_offset.y))
	var distance := minf(maxf(absf(fwd_vel) * step_duration, stride_length * 0.5), minf(stride_length * 1.3, reach * 0.8))
	if distance <= 1.0:
		return _result()
	var near_back := near_offset.x * dir
	var far_back := far_offset.x * dir
	if minf(near_back, far_back) <= -distance * 0.5:
		var swing_near := near_back <= far_back
		var support := far_offset if swing_near else near_offset
		var support_remaining := _available_x(support.y) + support.x * dir - absf(dx) * 2.0
		_start_swing(swing_near, dir, distance, support_remaining)
	return _result()

func _result() -> Dictionary:
	return {"near": near_offset, "far": far_offset}

func _available_x(foot_y: float) -> float:
	if leg_reach <= 0.0:
		return INF
	var reach := leg_reach * 0.985
	return sqrt(maxf(0.0, reach * reach - pow(foot_y - sole_offset, 2.0)))

func _reachable_support(foot: Vector2) -> Vector2:
	var limit := _available_x(foot.y)
	if absf(foot.x) <= limit:
		return foot
	var x := clampf(foot.x, -limit, limit)
	var y := _ground_offset(x)
	# 如果缩回后踩到不同高度，用髋下作为最终检查点。
	if absf(x) > _available_x(y):
		return Vector2(0.0, _ground_offset(0.0))
	return Vector2(x, y)

func _start_swing(near_leg: bool, dir: float, distance: float, support_remaining: float) -> void:
	state = State.NEAR_SWING if near_leg else State.FAR_SWING
	_swing_start_x = near_offset.x if near_leg else far_offset.x
	_swing_distance = maxf(1.0, minf(distance, support_remaining))
	var target_x := dir * distance * 0.5
	var available := _available_x(_ground_offset(target_x))
	_swing_target_x = clampf(target_x, -available, available)
	_swing_progress = 0.0
	_swing_start_lift = 0.0
	_finishing_run_step = false

func _step_swing(advance: float, near_leg: bool) -> void:
	_swing_progress = minf(_swing_progress + advance, 1.0)
	var x := lerpf(_swing_start_x, _swing_target_x, _swing_progress)
	var lift := 0.0
	if _swing_progress < 1.0:
		lift = _swing_start_lift * (1.0 - _swing_progress) if _finishing_run_step else step_height * sin(_swing_progress * PI)
	var foot := Vector2(x, _ground_offset(x) - lift)
	if near_leg:
		near_offset = foot
	else:
		far_offset = foot
	if _swing_progress >= 1.0:
		state = State.BOTH_GROUNDED

func _update_run_pose(delta: float, dx: float, speed: float) -> void:
	var steps := minf(run_max_steps_per_second, speed / (stride_length * 1.7))
	var cycle_per_second := maxf(0.1, steps * 0.5)
	_run_phase = fposmod(_run_phase + delta * cycle_per_second, 1.0)
	# For an attainable stride, the support foot cancels the body's horizontal travel.
	# At the reach limit, favour a slower cadence over perfect pinning.
	var half_stride := minf(speed / cycle_per_second * RUN_CONTACT * 0.5, _available_x(_ground_offset(0.0)) * 0.94)
	var near := _run_foot(_run_phase, half_stride, signf(dx))
	var far := _run_foot(fposmod(_run_phase + 0.5, 1.0), half_stride, signf(dx))
	_run_blend = minf(1.0, _run_blend + delta / RUN_BLEND_TIME)
	var blend := smoothstep(0.0, 1.0, _run_blend)
	near_offset = _run_from_near.lerp(near, blend)
	far_offset = _run_from_far.lerp(far, blend)

func _run_foot(phase: float, extent: float, dir: float) -> Vector2:
	if phase < RUN_CONTACT:
		var planted_x := dir * lerpf(extent, -extent, phase / RUN_CONTACT)
		return _reachable_support(Vector2(planted_x, _ground_offset(planted_x)))
	var progress := (phase - RUN_CONTACT) / (1.0 - RUN_CONTACT)
	var x := dir * lerpf(-extent, extent, smoothstep(0.0, 1.0, progress))
	return Vector2(x, _ground_offset(x) - run_step_height * sin(progress * PI))

func _update_air_pose(delta: float, vertical_speed: float) -> void:
	var landing_target := 0.0
	if vertical_speed > 0.0:
		var hit := _probe_floor(0.0)
		if not hit.is_empty():
			var floor_distance: float = hit["position"].y - _hip.y - stand_height
			var t := maxf(0.0, floor_distance) / vertical_speed
			landing_target = 1.0 - smoothstep(0.0, AIR_LAND_LEAD, t)
	_air_landing_blend = move_toward(_air_landing_blend, landing_target, delta / 0.06)
	var settle := smoothstep(0.0, AIR_SETTLE_TIME, _air_elapsed)
	near_offset = _air_foot(_air_from_near, settle)
	far_offset = _air_foot(_air_from_far, settle)

func _air_foot(launch: Vector2, settle: float) -> Vector2:
	var middle := Vector2(0.0, stand_height - AIR_MID_SHORTEN)
	var foot := launch.lerp(middle, settle).lerp(Vector2(middle.x, stand_height), _air_landing_blend)
	if _air_landing_blend > 0.0:
		var hit := _probe_floor(foot.x)
		if not hit.is_empty():
			foot.y = minf(foot.y, hit["position"].y - _hip.y)
	return foot

## 在朝向空间 x 偏移处探地面，返回相对髋点的 y 偏移。
func _ground_offset(offset_x: float) -> float:
	var hit := _probe_floor(offset_x)
	return stand_height if hit.is_empty() else hit["position"].y - _hip.y

func _probe_floor(offset_x: float) -> Dictionary:
	if ground_probe == null:
		return {}
	var wx := _hip.x + offset_x * _facing
	var query := PhysicsRayQueryParameters2D.create(Vector2(wx, _hip.y), Vector2(wx, _hip.y + 400.0))
	query.collision_mask = collision_mask
	if excluded_body != null:
		query.exclude = [excluded_body.get_rid()]
	return ground_probe.intersect_ray(query)
