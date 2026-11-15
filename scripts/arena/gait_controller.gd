## 双腿步态协调器。
##
## 所有坐标都在「朝向空间」：以髋点为原点，x 正 = 角色前方，y 正 = 向下。
## 这样机体镜像时只需给渲染节点设负 scale，步态逻辑不用改。
class_name GaitController
extends RefCounted

enum State { BOTH_GROUNDED, NEAR_SWING, FAR_SWING, AIRBORNE, LANDING }

var state := State.BOTH_GROUNDED
var near_offset := Vector2.ZERO   ## 近侧脚相对髋点（朝向空间）
var far_offset := Vector2.ZERO    ## 远侧脚相对髋点
var stride_length := 60.0         ## 步长（慢速时的下限，实际按速度动态算）
var step_height := 48.0           ## 抬脚高度
var step_duration := 0.38         ## 单步时长
var ground_probe: PhysicsDirectSpaceState2D = null
var collision_mask := 256        ## 地形所在层（playable_slice 的地形是 layer 9）
var excluded_body: CollisionObject2D = null
var stand_height := 0.0           ## 髋点离地高度（射线打空时的兜底）
var air_leg_ratio := 0.6          ## 空中收腿比例（脚收到站立高度的多少）

var _swing_timer := 0.0
var _swing_start := Vector2.ZERO
var _swing_target := Vector2.ZERO
var _landing_from := Vector2.ZERO
var _hip := Vector2.ZERO
var _facing := 1.0
var _fwd_vel := 0.0
var _has_hip := false
var _leg_tuck := 1.0     ## 腿伸展比例：1.0 = 站直，air_leg_ratio = 收起


func init_stance(hip_world: Vector2, height: float) -> void:
	stand_height = height
	near_offset = Vector2(0.0, height)
	far_offset = Vector2(0.0, height)
	state = State.BOTH_GROUNDED
	_hip = hip_world
	_has_hip = true


## 每帧更新。fwd_vel 是朝前的速度（朝后走为负）。返回两脚的相对偏移。
func update(delta: float, hip: Vector2, fwd_vel: float, facing: float, grounded: bool) -> Dictionary:
	_facing = facing if not is_zero_approx(facing) else 1.0
	_fwd_vel = fwd_vel

	# 收腿比例平滑过渡：起跳不会瞬间从弯曲跳到收起
	var target_tuck := 1.0 if grounded else air_leg_ratio
	_leg_tuck = move_toward(_leg_tuck, target_tuck, 6.0 * delta)

	if not grounded:
		# 空中：收腿，两条腿略微错开，避免完全重合
		state = State.AIRBORNE
		var air_h := stand_height * _leg_tuck
		near_offset = Vector2(-8.0, air_h)
		far_offset = Vector2(7.0, air_h * 1.08)
		_hip = hip
		return _result()

	# 落地过渡：腿快速伸到地面（脚要先着地），身体下沉缓冲在 slice_player 里做
	if state == State.LANDING:
		_swing_timer += delta
		var t := clampf(_swing_timer / 0.06, 0.0, 1.0)
		var gy := _ground_offset(0.0)
		var target := Vector2(0.0, gy)
		near_offset = _landing_from.lerp(target, t)
		far_offset = near_offset
		if t >= 1.0:
			state = State.BOTH_GROUNDED
			_swing_timer = 0.0
		_hip = hip
		_has_hip = true
		return _result()

	# 落地：重新探地
	if state == State.AIRBORNE:
		state = State.LANDING
		_swing_timer = 0.0
		_landing_from = near_offset

	# 支撑脚钉在世界里：髋点移动会让它相对后移（这是走路的来源）
	if _has_hip:
		var dx_local := (hip.x - _hip.x) * _facing
		if state != State.NEAR_SWING:
			near_offset.x -= dx_local
		if state != State.FAR_SWING:
			far_offset.x -= dx_local
	_hip = hip
	_has_hip = true

	# 支撑脚每帧重新贴地：髋点上下移动（下蹲/上坡）时，脚跟着重新探测地面
	if state == State.BOTH_GROUNDED:
		near_offset.y = _ground_offset(near_offset.x)
		far_offset.y = _ground_offset(far_offset.x)
	elif state == State.NEAR_SWING:
		far_offset.y = _ground_offset(far_offset.x)
	elif state == State.FAR_SWING:
		near_offset.y = _ground_offset(near_offset.x)

	# 静止：把还在半空的腿放下（加速收尾）
	if absf(fwd_vel) < 5.0:
		if state == State.NEAR_SWING:
			_step_swing(delta * 4.0, true)
		elif state == State.FAR_SWING:
			_step_swing(delta * 4.0, false)
		return _result()

	match state:
		State.BOTH_GROUNDED:
			# 步幅跟随速度：摆动期间支撑脚正好后移到触发点，节奏才不会断
			var half := _step_advance() * 0.5
			var dir := signf(fwd_vel)
			var near_back := near_offset.x * dir    # 负数 = 在身后
			var far_back := far_offset.x * dir
			if near_back <= -half and near_back <= far_back:
				_start_swing(true, fwd_vel)
			elif far_back <= -half:
				_start_swing(false, fwd_vel)
		State.NEAR_SWING:
			_step_swing(delta, true)
		State.FAR_SWING:
			_step_swing(delta, false)

	return _result()


func _result() -> Dictionary:
	return {"near": near_offset, "far": far_offset}


## 一步里身体前进的距离：摆动时长 × 速度。
## 摆动脚落在这个距离的一半，支撑脚同期后移一整步，正好回到触发点。
func _step_advance() -> float:
	return maxf(absf(_fwd_vel) * step_duration, stride_length * 0.5)


func _start_swing(near_leg: bool, fwd_vel: float) -> void:
	var dir := signf(fwd_vel) if absf(fwd_vel) >= 5.0 else 1.0
	var target_x := dir * _step_advance() * 0.5
	var gy := _ground_offset(target_x)
	var target := Vector2(target_x, gy)
	if near_leg:
		state = State.NEAR_SWING
		_swing_start = near_offset
		_swing_target = target
	else:
		state = State.FAR_SWING
		_swing_start = far_offset
		_swing_target = target
	_swing_timer = 0.0


func _step_swing(step_delta: float, near_leg: bool) -> void:
	_swing_timer += step_delta
	var t := minf(_swing_timer / step_duration, 1.0)
	# 摆动脚每帧重新贴地：髋点高度变化（下蹲/起跳）时脚跟着修正，不会陷地
	var x := lerpf(_swing_start.x, _swing_target.x, t)
	var gy := _ground_offset(x)
	var y := gy - step_height * sin(t * PI)
	var pos := Vector2(x, y)
	if t >= 1.0:
		pos = Vector2(_swing_target.x, _ground_offset(_swing_target.x))
		state = State.BOTH_GROUNDED
		_swing_timer = 0.0
	if near_leg:
		near_offset = pos
	else:
		far_offset = pos


func _swing_lerp(from: Vector2, to: Vector2, t: float) -> Vector2:
	var x := lerpf(from.x, to.x, t)
	var y := lerpf(from.y, to.y, t)
	# 只有摆动中段抬脚，两端贴地
	return Vector2(x, y - step_height * sin(t * PI))


## 在朝向空间 x 偏移处探地面，返回相对髋点的 y 偏移
func _ground_offset(offset_x: float) -> float:
	if ground_probe == null:
		return stand_height
	var wx := _hip.x + offset_x * _facing
	var query := PhysicsRayQueryParameters2D.create(Vector2(wx, _hip.y), Vector2(wx, _hip.y + 400.0))
	query.collision_mask = collision_mask
	if excluded_body != null:
		query.exclude = [excluded_body.get_rid()]
	var hit := ground_probe.intersect_ray(query)
	if hit.is_empty():
		return stand_height
	return hit["position"].y - _hip.y
