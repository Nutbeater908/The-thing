## 一条肢体链在关卡里的运动学模拟 + 绘制 + 命中判定。
##
## 两个阶段：
##  - STRIKE：角度**直接由动作曲线驱动**（逐节延迟），速度可控，才有发力感
##  - RECOVER：弹簧把角度拉回静止姿态，松弛感留在这里
## 末端速度由位置差分得到，用于算伤害。
class_name LimbRig
extends Node2D

signal hit_landed(damage: float)

enum Phase { IDLE, STRIKE, RECOVER }

const REF_SPEED := 2500.0     ## 参考末端速度（一次完整下劈的典型值）
const REF_MASS := 8.0         ## 参考链质量（臂 4 + 爪 4）
const MIN_HIT_SPEED := 150.0  ## 低于这个速度不判定命中，避免贴着敌人白嫖
const COOLDOWN := 0.25
const ENEMY_RADIUS := 20.0
const SETTLE_EPS := 1.0       ## 角度和角速度都小于它就认为回位完成
## 关节盘：所有连接处共用的圆形贴图，盖住接缝
const JOINT_PATH := "res://art/tiles/joint_disc.png"
const JOINT_RADIUS := 16.0
static var _joint_texture: Texture2D
static var _joint_loaded := false

var chain: LimbChainBuilder.Chain
var motion: LimbMotion
var anchor := Vector2.ZERO          ## 躯干侧的附着点（本节点本地坐标）
## 两段贴图（大腿 / 小腿）与它们的枢轴点，来自新装配系统
var segment_textures: Array[Texture2D] = []
var segment_pivots: Array[Vector2] = []
var facing := 1.0
var show_debug := false

var _angles: Array[float] = []
var _vels: Array[float] = []
var _points: PackedVector2Array = PackedVector2Array()
var _phase: Phase = Phase.IDLE
var _clock := 0.0
var _cooldown := 0.0
var _tip_prev := Vector2.ZERO
var _tip_vel := Vector2.ZERO
var _mass := 0.0
var _ready_done := false
## 行走模式：没有绑定攻击键的肢体（腿）用程序摆动，而不是动作模组
var walk_mode := false
## 双腿错相位：远侧腿用 PI 让两条腿交替
var walk_phase_offset := 0.0
## 步态相位偏置（像素）：两腿错开半步
var _gait_bias := 0.0
## 瞄准模式：攻击肢体按鼠标方向摆基准角（双摇杆手感）
var use_aim := false
var aim_world := Vector2.ZERO

var _aim_base_deg := 0.0
## 发动动作时锁定的基准角：挥出去的过程中不跟着鼠标转
var _locked_base_deg := 0.0
var _walk_phase := 0.0
var _walk_amount := 0.0


func setup(p_chain: LimbChainBuilder.Chain, p_motion: LimbMotion, p_anchor: Vector2) -> void:
	chain = p_chain
	motion = p_motion
	anchor = p_anchor
	_mass = 0.0
	for s in chain.segments:
		_angles.append(0.0)
		_vels.append(0.0)
		_mass += s.organ.mass() if s.organ.has_method("mass") else float(s.organ.mass)
	_points.resize(chain.segments.size() + 1)
	_solve()
	_tip_prev = _points[_points.size() - 1]
	_ready_done = true


func trigger() -> void:
	if motion == null or chain == null or not chain.valid:
		return
	_phase = Phase.STRIKE
	_clock = 0.0
	# 从当前朝向发动
	_locked_base_deg = _aim_base_deg if use_aim else chain.base_angle_deg


func is_playing() -> bool:
	return _phase != Phase.IDLE


func _physics_process(delta: float) -> void:
	if not _ready_done or chain == null or chain.segments.is_empty():
		return
	if _cooldown > 0.0:
		_cooldown -= delta

	# 瞄准：待机时基准角跟着鼠标；出招中锁定在发动那一刻
	if use_aim:
		var to_aim := (aim_world - global_position) - anchor
		if to_aim.length_squared() > 1.0:
			_aim_base_deg = rad_to_deg(to_aim.angle())
		if _phase == Phase.IDLE:
			_locked_base_deg = _aim_base_deg

	match _phase:
		Phase.STRIKE:
			_clock += delta
			_drive_strike(delta)
			if _clock >= motion.duration:
				# 打击结束时角速度不清零，弹簧会带着残余速度猛冲过头
				for i in _vels.size():
					_vels[i] = 0.0
				_phase = Phase.RECOVER
		Phase.RECOVER:
			_step_recover(delta)
			if _settled():
				_phase = Phase.IDLE
		_:
			pass

	_solve()

	var tip: Vector2 = _points[_points.size() - 1]
	if delta > 0.0:
		_tip_vel = (tip - _tip_prev) / delta
	_tip_prev = tip

	_check_hits()
	queue_redraw()


## 打击阶段：直接写角度，逐节延迟制造鞭击感
func _drive_strike(delta: float) -> void:
	for i in _angles.size():
		# 每节用自己的时间轴：末节滞后于根节
		var local := maxf(0.0, _clock - i * motion.segment_delay)
		var one: Array[float] = motion.sample(local, _angles.size())
		var target := clampf(one[i], chain.segments[i].joint_min, chain.segments[i].joint_max)
		if delta > 0.0:
			_vels[i] = (target - _angles[i]) / delta
		_angles[i] = target


func _step_recover(delta: float) -> void:
	# 回位用弹簧：越重的链越迟钝
	var omega := clampf(motion.recover_omega * (10.0 / (5.0 + _mass)), 6.0, 24.0)
	var zeta := 0.85
	for i in _angles.size():
		var accel := omega * omega * (0.0 - _angles[i]) - 2.0 * zeta * omega * _vels[i]
		_vels[i] += accel * delta
		_angles[i] += _vels[i] * delta


func _settled() -> bool:
	for i in _angles.size():
		if absf(_angles[i]) > SETTLE_EPS or absf(_vels[i]) > SETTLE_EPS * 10.0:
			return false
	return true


## 前向运动学：从锚点逐节累加角度，求出每节端点
func _solve() -> void:
	var pos := anchor
	if _points.size() != _angles.size() + 1:
		_points.resize(_angles.size() + 1)
	_points[0] = pos
	# 基准角：瞄准模式用鼠标方向，否则用单元挂点方向
	var base := _locked_base_deg if use_aim else chain.base_angle_deg
	var horizontal := absf(base) < 45.0 or absf(base) > 135.0
	var ang := deg_to_rad(base)
	if not use_aim and horizontal and facing < 0.0:
		ang += PI
	for i in _angles.size():
		var seg: LimbChainBuilder.Segment = chain.segments[i]
		ang += deg_to_rad(_angles[i]) * facing
		# 朝向已经在基准角和逐节角度里处理过，这里不能再乘一次 facing
		pos += Vector2(cos(ang), sin(ang)) * seg.length
		_points[i + 1] = pos


## 腿：两骨 IK，脚踩在世界坐标的锚点上。
## 身体移动时脚相对身体后移，超出步幅才抬脚跨到前方重新踩下。
## 完全不依赖"相位"，所以反向走、静止都不会出错。
const LEG_BEND := 1.0
const STEP_THRESHOLD := 34.0   ## 脚离髋多远就换步
const STEP_AHEAD := 30.0       ## 换步时落在髋前方多远
const STEP_TIME := 0.16        ## 一步的时长
const STEP_LIFT := 14.0        ## 抬脚高度

var _foot := Vector2.ZERO      ## 当前脚的世界坐标
var _step_from := Vector2.ZERO
var _step_to := Vector2.ZERO
var _step_t := -1.0            ## <0 表示踩实
var _has_foot := false


func animate_walk(move_dir: float, speed: float, delta: float, grounded := true) -> void:
	if not walk_mode or _angles.size() < 2:
		return
	var hip := global_position + anchor

	# 离地时脚不踩点：腿跟着身体收起来，落地再重新踩
	if not grounded:
		_has_foot = false
		_step_t = -1.0
		var reach: float = chain.segments[0].length + chain.segments[1].length
		_solve_to_foot(anchor + Vector2(0, reach * 0.72))
		return

	var ground := _ground_below(hip)

	if not _has_foot:
		# 两腿错开半步：远侧腿从反方向起步，形成交替
		_gait_bias = cos(walk_phase_offset) * STEP_THRESHOLD
		_foot = Vector2(hip.x + _gait_bias, ground)
		_has_foot = true

	if _step_t < 0.0:
		# 踩实阶段：脚不动，身体往前走，脚相对后移
		if absf(_foot.x - hip.x) > STEP_THRESHOLD:
			# 步子要跨向**移动方向**，不是朝向（可以倒着走）
			var dir := move_dir if not is_zero_approx(move_dir) else facing
			_step_from = _foot
			_step_to = Vector2(hip.x + STEP_AHEAD * dir + _gait_bias, ground)
			_step_t = 0.0
	else:
		_step_t += delta
		var k := clampf(_step_t / STEP_TIME, 0.0, 1.0)
		_foot = _step_from.lerp(_step_to, k)
		_foot.y = minf(_step_from.y, _step_to.y) - sin(k * PI) * STEP_LIFT
		if k >= 1.0:
			_foot = Vector2(_step_to.x, ground)
			_step_t = -1.0

	_solve_to_foot(_foot - global_position)


## 从髋部向下打一条射线找地面；打不到就退回到脚底平面
func _ground_below(hip: Vector2) -> float:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(hip, hip + Vector2(0, 420))
	query.exclude = [get_parent().get_rid()] if get_parent() is CollisionObject2D else []
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return global_position.y
	return hit["position"].y


## 把目标脚位（本节点本地坐标）解成两节角度
func _solve_to_foot(target_local: Vector2) -> void:
	var upper: float = chain.segments[0].length
	var lower: float = chain.segments[1].length
	var points := LegIk.solve_points(anchor, target_local, upper, lower, LEG_BEND)
	var solved := LegIk.to_angles(points, chain.base_angle_deg)
	for i in mini(2, _angles.size()):
		_angles[i] = solved[i] / facing if not is_zero_approx(facing) else solved[i]


func _check_hits() -> void:
	if _phase != Phase.STRIKE:
		return
	if _clock < motion.hit_start:
		return
	if _cooldown > 0.0 or _tip_vel.length() < MIN_HIT_SPEED:
		return
	var tip: Vector2 = _points[_points.size() - 1]
	var world_tip := global_position + tip
	var last: LimbChainBuilder.Segment = chain.segments[chain.segments.size() - 1]
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if world_tip.distance_to(enemy.global_position) > last.tip_radius + ENEMY_RADIUS:
			continue
		var dmg := compute_damage(_tip_vel.length())
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg)
		_cooldown = COOLDOWN
		hit_landed.emit(dmg)
		return


## 伤害公式见设计稿第 5 节：末端基础伤害 × 速度系数 × 质量系数
## 不再叠加线性速度项，否则高速末端会指数级爆炸
func compute_damage(speed: float) -> float:
	var last: LimbChainBuilder.Segment = chain.segments[chain.segments.size() - 1]
	var impact := clampf(speed / REF_SPEED, 0.0, 2.0)
	var mass_factor := clampf(_mass / REF_MASS, 0.5, 2.5)
	return last.tip_damage * (1.0 + 1.2 * impact) * mass_factor


func _draw() -> void:
	if _points.size() < 2:
		return
	if _draw_segments():
		return
	for i in chain.segments.size():
		var seg: LimbChainBuilder.Segment = chain.segments[i]
		var a := _points[i]
		var b := _points[i + 1]
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var w0 := 9.0
		var w1 := 6.0
		var quad := PackedVector2Array([
			a + nrm * w0, b + nrm * w1, b - nrm * w1, a - nrm * w0,
		])
		draw_colored_polygon(quad, seg.organ.color)
		draw_line(a, b, Color(0, 0, 0, 0.55), 1.5)
	if _points.size() >= 2:
		var last: LimbChainBuilder.Segment = chain.segments[chain.segments.size() - 1]
		draw_circle(_points[_points.size() - 1], last.tip_radius, last.organ.color)
		draw_circle(_points[_points.size() - 1], last.tip_radius, Color(0, 0, 0, 0.6), false, 1.5)
	if show_debug:
		draw_circle(anchor, 3.0, Color(1, 1, 0))


## 用三段贴图渲染（大腿 / 小腿 / 脚）；数据不足时返回 false 走旧的胶囊画法
func _draw_segments() -> bool:
	if segment_textures.size() < 2 or segment_pivots.size() < 4:
		return false
	if _points.size() < 3:
		return false
	var hip: Vector2 = segment_pivots[0]
	var knee_u: Vector2 = segment_pivots[1]
	var knee_l: Vector2 = segment_pivots[2]
	var ankle_s: Vector2 = segment_pivots[3]
	var ankle_f: Vector2 = segment_pivots[4] if segment_pivots.size() > 4 else ankle_s

	# 大腿：hip→knee 为轴
	var a0 := (_points[1] - _points[0]).angle() - (knee_u - hip).angle()
	draw_set_transform(_points[0], a0, Vector2.ONE)
	draw_texture(segment_textures[0], -hip)

	# 小腿：knee→ankle 为轴
	var a1 := (_points[2] - _points[1]).angle() - (ankle_s - knee_l).angle()
	draw_set_transform(_points[1], a1, Vector2.ONE)
	draw_texture(segment_textures[1], -knee_l)

	# 脚：挂在小腿变换算出来的踝点，保持水平
	if segment_textures.size() >= 3:
		var ankle_world: Vector2 = _points[1] + (ankle_s - knee_l).rotated(a1)
		draw_set_transform(ankle_world, 0.0, Vector2.ONE)
		draw_texture(segment_textures[2], -ankle_f)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if show_debug:
		draw_circle(_points[1], 3.0, Color(1, 0.4, 0.4))
	return true


static func _joint() -> Texture2D:
	if not _joint_loaded:
		_joint_loaded = true
		if ResourceLoader.exists(JOINT_PATH):
			_joint_texture = load(JOINT_PATH) as Texture2D
	return _joint_texture
