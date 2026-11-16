extends "res://scripts/character/character_terrain_walker.gd"
## Combat wrapper only; the shared native walker owns all movement and floor handling.
signal died
signal attacked(hits: int)
signal hurt

var hp: float = 0.0
var max_hp: float:
	get:
		return float(tuning.max_hp)
var dead := false
var facing: float = 1.0
var _attack_timer := 0.0
var _invulnerability_timer := 0.0
var _flash_timer := 0.0

@onready var _body: Polygon2D = $Visual
@onready var _attack_visual: Polygon2D = $AttackVisual

var _rigs: Array[LimbRig] = []
var _rigs_by_action := {}
var _layout = null
var _assembly_body = null
var _gait: GaitController = null
var _leg_spec: LegGeometry.Spec = null
## 按 H 切换：默认只显示肉膜，不显示器官
var show_organs := false

const FLESH_PATH := "res://art/tiles/flesh_tile.png"
## 腿部关节方向：-1 = 反关节（膝后折），+1 = 正关节（膝前弯）
## 当前素材按反关节设计。正关节与配套步态暂记在 docs/步态备忘.md
const LEG_BEND := -1.0
const SCAR_PATH := "res://art/tiles/scar_tile.png"
const SEAM_COLOR := Color(0.227, 0.165, 0.180)     ## #3A2A2E 缝线
const STITCH_COLOR := Color(0.788, 0.706, 0.667)   ## #C9B4AC 针脚
## 贴图边长（世界像素）。比大多数躯干大，让一具身体基本只落在一张贴图内
const FLESH_TILE := 256.0
## 疤痕贴图：比皮肤小得多，让缝合痕迹散布在躯干各处而不只在边缘
const SCAR_TILE := 168.0
var _flesh_offset := Vector2.ZERO
var _scar_offset := Vector2.ZERO
static var _flesh_texture: Texture2D
static var _flesh_loaded := false
static var _scar_texture: Texture2D
static var _scar_loaded := false

# ---------------------------------------------------------------- 跳跃

enum JumpPhase { NONE, CROUCH, AIRBORNE, LAND, RECOVER }

const CROUCH_TIME := 0.20      ## 蓄力时长
const CROUCH_DEPTH := 20.0     ## 蓄力下沉（受腿长余量限制，最大 22）
const LAND_TIME := 0.18        ## 落地缓冲时长
const LAND_DEPTH := 20.0       ## 落地下沉（同上，超过 22 会让 IK 夹死）
const RECOVER_TIME := 0.14     ## 回正时长
const AIR_RISE_SPEED := 320.0  ## 起跳后机体回正速度（太快会跳帧）

var _jump_phase: JumpPhase = JumpPhase.NONE
var _jump_timer := 0.0
var _body_offset_y := 0.0      ## 正值 = 机体下沉
var _launch_motor_speed := 0.0
var _shape_node: CollisionShape2D = null
var _torso_shape: CollisionShape2D = null
var _torso_base_y := 0.0
var _base_shape_height := 100.0
var _base_shape_center := -50.0

# ---------------------------------------------------------------- 运动能力
# 现在是默认值；以后接机体属性时按机体覆盖这几项即可。
# 例如重型机体把 ability_turn_in_air 设为 false，或开启 ability_air_mobility。
var ability_turn_while_crouching := false   ## 蓄力时能否转身
var ability_turn_in_air := true             ## 空中能否转身
var ability_move_in_air := false            ## 空中能否改变速度
var ability_air_mobility := false           ## 预留：空中机动/冲刺


func _ready() -> void:
	hp = max_hp
	add_to_group("creature")
	_attack_visual.hide()
	# 碰撞体要随蹲下变矮，必须独占一份，不能改到共享的 sub_resource
	_shape_node = get_node_or_null("Shape") as CollisionShape2D
	if _shape_node != null and _shape_node.shape != null:
		_shape_node.shape = _shape_node.shape.duplicate()
		_base_shape_height = _shape_node.shape.height
		_base_shape_center = _shape_node.position.y
	# 机身矩形：新装配系统的机身尺寸各异，进入关卡时按 bounds 生成
	_torso_shape = CollisionShape2D.new()
	_torso_shape.name = "TorsoShape"
	add_child(_torso_shape)


## 按装配生成的机体尺寸搭移动碰撞：
## - 腿根胶囊：髋点到脚底的范围，保证整机不穿地面（不跟迈步动画）
## - 机身矩形：根部件（机身）的实际范围
func _build_movement_shapes(body) -> void:
	if body == null or body.root_index < 0:
		return
	var root: AssemblyBridge.Placed = body.parts[body.root_index]
	
	# 机身矩形：根部件的位置与尺寸
	var rect := RectangleShape2D.new()
	rect.size = root.data.size
	_torso_shape.shape = rect
	_torso_shape.position = root.position + root.data.size * 0.5
	_torso_base_y = _torso_shape.position.y
	
	# 腿根胶囊：从髋点到脚底
	var hip := AssemblyBridge.socket_of(body, &"hip")
	var leg_h := maxf(-hip.y, 44.0)
	var capsule := _shape_node.shape as CapsuleShape2D
	if capsule != null:
		capsule.height = leg_h
		capsule.radius = 20.0
	_base_shape_height = leg_h
	_shape_node.position = Vector2(body.bounds.size.x * 0.5 - root.position.x, -leg_h * 0.5)
	_base_shape_center = _shape_node.position.y


## 蹲下时碰撞体真的变矮（底部保持贴地），这样低矮通道能钻过去
func _apply_crouch_shape() -> void:
	# 腿根胶囊变矮
	if _shape_node != null and _shape_node.shape != null:
		var h: float = maxf(_base_shape_height - _body_offset_y, 44.0)
		var capsule := _shape_node.shape as CapsuleShape2D
		if capsule != null:
			capsule.height = h
		_shape_node.position.y = -h * 0.5
	# 机身矩形跟着下沉
	if _torso_shape != null:
		_torso_shape.position.y = _torso_base_y + _body_offset_y


## 把拼装算出的能力灌进本实例。
## tuning 先复制再改：场景里的 Tuning 是共享子资源，不能就地写脏。
func apply_profile(profile: SliceBodyProfile) -> void:
	if profile == null:
		return
	var copy: Resource = tuning.duplicate()
	copy.set("walk_speed", profile.walk_speed)
	copy.set("acceleration", profile.acceleration)
	copy.set("jump_speed", profile.jump_speed)
	copy.set("max_hp", profile.max_hp)
	copy.set("damage", profile.damage)
	copy.set("attack_range", profile.attack_range)
	copy.set("attack_cooldown", profile.attack_cooldown)
	tuning = copy
	hp = max_hp


func set_walk_intent(value: float) -> void:
	if dead:
		super.set_walk_intent(0.0)
		return
	# 蓄力、落地缓冲期间锁移动（有重量感）
	if _jump_phase in [JumpPhase.CROUCH, JumpPhase.LAND, JumpPhase.RECOVER]:
		super.set_walk_intent(0.0)
		return
	super.set_walk_intent(value)


## 朝向由鼠标决定，和移动方向解耦（双摇杆手感：可以倒着走）
func _update_facing_from_mouse() -> void:
	# 能力开关：某些机体蓄力时或空中不能转身
	if _jump_phase == JumpPhase.CROUCH and not ability_turn_while_crouching:
		return
	if _jump_phase == JumpPhase.AIRBORNE and not ability_turn_in_air:
		return
	var mouse := get_global_mouse_position()
	var new_facing := 1.0 if mouse.x >= global_position.x else -1.0
	if not is_equal_approx(new_facing, facing):
		facing = new_facing
		queue_redraw()   # 躯干镜像靠重绘，不重绘就永远停在上一个朝向


## 跳跃：按下后先蓄力，蓄力结束才真正离地
func request_jump() -> bool:
	if dead or _jump_phase != JumpPhase.NONE or not is_on_floor():
		return false
	_jump_phase = JumpPhase.CROUCH
	_jump_timer = 0.0
	return true


## 跳跃状态机：蓄力 → 起跳 → 空中 → 落地缓冲 → 回正
func _update_jump(delta: float) -> void:
	var prev_offset := _body_offset_y
	match _jump_phase:
		JumpPhase.CROUCH:
			_jump_timer += delta
			var t := clampf(_jump_timer / CROUCH_TIME, 0.0, 1.0)
			# 快速下蹲（ease-out），像压液压杆
			_body_offset_y = CROUCH_DEPTH * (1.0 - pow(1.0 - t, 2.0))
			if t >= 1.0:
				_launch_motor_speed = motor_speed
				if super.request_jump():
					_jump_phase = JumpPhase.AIRBORNE
					_jump_timer = 0.0
				else:
					# 起跳失败（例如已离地），回到常态
					_jump_phase = JumpPhase.NONE
					_body_offset_y = 0.0
		
		JumpPhase.AIRBORNE:
			_jump_timer += delta
			# 蹬地后机体回正：慢一点，和收腿同时进行才连贯
			_body_offset_y = move_toward(_body_offset_y, 0.0, AIR_RISE_SPEED * delta)
			# 空中不能改变速度
			if not ability_move_in_air:
				motor_locked = true
				motor_speed = _launch_motor_speed
			if is_on_floor() and _jump_timer > 0.06:
				_jump_phase = JumpPhase.LAND
				_jump_timer = 0.0
				motor_locked = false
		
		JumpPhase.LAND:
			_jump_timer += delta
			var t := clampf(_jump_timer / LAND_TIME, 0.0, 1.0)
			# 先沉到底再回升：sin 曲线，中段最深
			_body_offset_y = LAND_DEPTH * sin(t * PI)
			if t >= 1.0:
				_jump_phase = JumpPhase.RECOVER
				_jump_timer = 0.0
		
		JumpPhase.RECOVER:
			_jump_timer += delta
			# 线性回正，避免 lerp 的指数衰减造成的突兀收尾
			_body_offset_y = move_toward(_body_offset_y, 0.0, LAND_DEPTH / RECOVER_TIME * delta)
			if is_zero_approx(_body_offset_y):
				_jump_phase = JumpPhase.NONE
				_body_offset_y = 0.0
		
		_:
			pass
	
	# 兜底：不在空中时确保解除锁定
	if _jump_phase != JumpPhase.AIRBORNE:
		motor_locked = false
	
	# 机体下沉靠重绘生效，不重绘只有腿在动、躯干不动
	if not is_equal_approx(prev_offset, _body_offset_y):
		queue_redraw()
		_apply_crouch_shape()   # 碰撞体同步变矮，蹲下是真实状态


func _physics_process(delta: float) -> void:
	if dead:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_invulnerability_timer = maxf(0.0, _invulnerability_timer - delta)
	_flash_timer = maxf(0.0, _flash_timer - delta)
	_attack_visual.visible = _flash_timer > 0.0
	if _invulnerability_timer <= 0.0:
		_body.modulate = Color.WHITE
	_update_jump(delta)
	super._physics_process(delta)
	_update_facing_from_mouse()
	_poll_limb_actions()
	_animate_walk(delta)


## 每帧同步朝向；腿由步态协调器驱动，手臂指向鼠标
func _animate_walk(delta: float) -> void:
	if dead:
		return
	var mouse := get_global_mouse_position()
	var grounded := is_on_floor()
	
	# 步态协调器更新双脚位置
	if _gait != null and _leg_spec != null:
		# direct_space_state 只在物理帧内有效，所以每帧这里刷新
		_gait.ground_probe = get_world_2d().direct_space_state
		var hip_local := Vector2.ZERO
		for part in _assembly_body.parts:
			if part.data.category == PartData.Category.LOCOMOTION:
				hip_local = part.position
				if part.data.anchor != null:
					hip_local += part.data.anchor.offset
				break
		# 跳跃时髋点跟着机体一起下沉，脚点仍在地面 → 膝盖自动弯曲
		hip_local.y += _body_offset_y
		
		# 速度换算到朝向空间（朝前为正）
		var fwd_vel := velocity.x * facing
		var feet := _gait.update(delta, to_global(hip_local), fwd_vel, facing, grounded)
		
		# gait 输出的是相对髋点的「到脚底」距离，IK 的终点是踝点，要减去脚掌厚度
		var foot_h: float = _leg_spec.foot_offset.y
		var near_target: Vector2 = hip_local + feet["near"]
		var far_target: Vector2 = hip_local + feet["far"]
		near_target.y -= foot_h
		far_target.y -= foot_h
		
		# 反关节（膝后折）。贴图结构就是这么设计的，不随朝向改变
		var near_pts := LegIk.solve_points(hip_local, near_target, _leg_spec.upper_length, _leg_spec.lower_length, LEG_BEND)
		var far_pts := LegIk.solve_points(hip_local, far_target, _leg_spec.upper_length, _leg_spec.lower_length, LEG_BEND)
		
		var leg_idx := 0
		for rig in _rigs:
			if rig.walk_mode:
				rig.facing = facing
				if leg_idx == 0:
					rig._points = near_pts
				elif leg_idx == 1:
					rig._points = far_pts
				leg_idx += 1
				# 直接调用新系统的驱动，不走旧的 animate_walk
				rig.animate_walk(0.0, 0.0, delta, grounded)
	else:
		# 旧系统回退
		var speed := absf(velocity.x)
		var move_dir := signf(velocity.x)
		for rig in _rigs:
			rig.facing = facing
			if rig.walk_mode:
				rig.animate_walk(move_dir, speed, delta, grounded)
	
	# 非腿肢体指向鼠标
	for rig in _rigs:
		if not rig.walk_mode:
			rig.facing = facing
			rig.use_aim = true
			rig.aim_world = mouse


## 每条链按自己的 bind_action 触发；同名的链会被同一个键一起甩出
func _poll_limb_actions() -> void:
	for action in _rigs_by_action:
		if not InputMap.has_action(action):
			continue
		if not Input.is_action_just_pressed(action):
			continue
		for rig in _rigs_by_action[action]:
			rig.facing = facing
			rig.trigger()


## 由关卡在进入时调用：把躯干形状与肢体链接进玩家
## 把新装配系统里的两段贴图与枢轴喂给肢体
func _attach_segments(rig, chain) -> void:
	var lib := PartsLibrary.catalog()
	for part in lib.values():
		if part.segment_textures.size() < 2 or part.segment_pivots.size() < 4:
			continue
		var is_leg := String(chain.bind_action).is_empty()
		if part.id == &"leg_standard" and is_leg:
			rig.segment_textures = part.segment_textures
			rig.segment_pivots = part.segment_pivots
			return
		if part.id == &"arm_standard" and not is_leg:
			rig.segment_textures = part.segment_textures
			rig.segment_pivots = part.segment_pivots
			return


func setup_limbs(chains: Array, layout = null) -> void:
	if layout != null:
		apply_layout(layout)
	var idx := 0
	for c in chains:
		var anchor := Vector2(0, -18)
		if layout != null and idx < layout.anchors.size():
			anchor = layout.anchors[idx]
		idx += 1
		if not c.valid:
			continue
		var rig := LimbRig.new()
		rig.name = "Limb%d" % _rigs.size()
		add_child(rig)
		var use_motion: LimbMotion = c.motion if c.motion != null else _motion_for(c.bind_action)
		rig.setup(c, use_motion, anchor)
		_attach_segments(rig, c)
		rig.walk_mode = String(c.bind_action).is_empty()
		rig.facing = facing
		rig.hit_landed.connect(_on_limb_hit)
		_rigs.append(rig)
		rig.z_index = 1
		# 没绑定按键的链只渲染，不响应攻击键（腿默认就是这样）
		if String(c.bind_action).is_empty():
			continue
		var action := String(c.bind_action)
		if not _rigs_by_action.has(action):
			_rigs_by_action[action] = []
		_rigs_by_action[action].append(rig)


## 用拼装结果替换固定的胶囊：躯干融合成一块肉，碰撞用逐格轮廓
func apply_layout(layout) -> void:
	_layout = layout
	_flesh_offset = Vector2(randf(), randf()) * FLESH_TILE
	_scar_offset = Vector2(randf(), randf()) * SCAR_TILE
	var old := get_node_or_null("Shape")
	if old != null:
		old.set_deferred("disabled", true)
	# 每段轮廓一个碰撞多边形（支持凹形与多段）
	for child in get_children():
		if child is CollisionPolygon2D:
			child.queue_free()
	var index := 0
	for loop in layout.loops:
		if loop.size() < 3:
			continue
		var shape := CollisionPolygon2D.new()
		shape.name = "BodyShape%d" % index
		shape.polygon = loop
		add_child(shape)
		index += 1
	# 腿的碰撞块：撑住身体，让它站在腿上而不是悬空
	if layout.leg_rect.size.y > 1.0:
		var legs := CollisionPolygon2D.new()
		legs.name = "LegShape"
		var r: Rect2 = layout.leg_rect
		legs.polygon = PackedVector2Array([
			r.position,
			r.position + Vector2(r.size.x, 0),
			r.position + r.size,
			r.position + Vector2(0, r.size.y),
		])
		add_child(legs)
	_body.visible = false
	queue_redraw()


## 直接用新装配系统的机体渲染（部件贴图逐个画）
## 从 pivot_* 接口拼出 [hip, knee_u, knee_l, foot]
func _pivots_of(part: PartData) -> Array[Vector2]:
	var names := [&"pivot_hip", &"pivot_knee_u", &"pivot_knee_l", &"pivot_ankle_s", &"pivot_ankle_f"]
	var out: Array[Vector2] = []
	for n in names:
		var so: SocketData = part.socket(n)
		out.append(so.offset if so != null else Vector2.ZERO)
	return out


func apply_body(body) -> void:
	_assembly_body = body
	if _body != null:
		_body.visible = false
	_build_body_limbs(body)
	_build_movement_shapes(body)
	queue_redraw()


## 按部件类型造肢体：运动件 → 腿，作业件 → 臂
func _build_body_limbs(body) -> void:
	for r in _rigs:
		r.queue_free()
	_rigs.clear()
	_gait = null
	_leg_spec = null
	
	var lib := PartsLibrary.catalog()
	var leg_part: PartData = lib.get(&"leg_standard")
	
	# 先读腿的几何
	if leg_part != null:
		_leg_spec = LegGeometry.from_part(leg_part)
		if _leg_spec.total_length > 0.0:
			_gait = GaitController.new()
			_gait.ground_probe = get_world_2d().direct_space_state
			_gait.collision_mask = collision_mask   # 地形在玩家 mask 覆盖的层里
			_gait.excluded_body = self
			# 初始化双脚位置（髋点从第一个运动部件取）
			for part in body.parts:
				if part.data.category == PartData.Category.LOCOMOTION:
					var hip_local: Vector2 = part.position
					if part.data.anchor != null:
						hip_local += part.data.anchor.offset
					# 髋点离地 = 弯曲后的腿长 + 脚掌厚度
					var stand_h := _leg_spec.total_length * 0.88 + _leg_spec.foot_offset.y
					_gait.init_stance(to_global(hip_local), stand_h)
					break
	
	for part in body.parts:
		var kind: int = part.data.category
		if kind != PartData.Category.LOCOMOTION and kind != PartData.Category.WORK:
			continue
		var limb_part: PartData = lib.get(&"leg_standard") if kind == PartData.Category.LOCOMOTION else lib.get(&"arm_standard")
		if limb_part == null:
			continue
		
		# 髋点：本件挂点在世界里的位置
		var hip_world: Vector2 = part.position
		if part.data.anchor != null:
			hip_world = part.position + part.data.anchor.offset
		
		var rig := LimbRig.new()
		rig.name = "Limb%d" % _rigs.size()
		add_child(rig)
		
		# 腿用新几何，臂保留旧方式
		if kind == PartData.Category.LOCOMOTION and _leg_spec != null:
			var chain := LimbChainBuilder.Chain.new()
			chain.valid = true
			chain.base_angle_deg = 90.0
			for i in 2:
				var seg := LimbChainBuilder.Segment.new()
				seg.organ = limb_part
				seg.length = _leg_spec.upper_length if i == 0 else _leg_spec.lower_length
				seg.joint_min = -70.0
				seg.joint_max = 70.0
				seg.tip_radius = 4.0
				chain.segments.append(seg)
			rig.segment_textures = limb_part.segment_textures
			rig.segment_pivots = _pivots_of(limb_part)
			rig.setup(chain, _motion_for(&"attack"), hip_world)
			rig.walk_mode = true
			rig.externally_driven = true
			rig.facing = facing
			rig.z_index = 1
			rig.mirror_pivot = _assembly_body.bounds.size.x
			_rigs.append(rig)
			
			# 远侧腿：压暗 + 略微后移，视觉上区分前后腿
			var far := LimbRig.new()
			far.name = "LimbFar%d" % _rigs.size()
			add_child(far)
			far.setup(chain, _motion_for(&"attack"), hip_world + Vector2(-10.0, -4.0))
			far.segment_textures = limb_part.segment_textures
			far.segment_pivots = _pivots_of(limb_part)
			far.walk_mode = true
			far.externally_driven = true
			far.facing = facing
			far.z_index = 0
			far.show_behind_parent = true
			far.modulate = Color(0.5, 0.5, 0.55, 1.0)
			far.mirror_pivot = _assembly_body.bounds.size.x
			_rigs.append(far)
		else:
			# 臂或旧腿（fallback）
			var chain := LimbChainBuilder.Chain.new()
			chain.valid = true
			var piv := _pivots_of(limb_part)
			var tex_a: Texture2D = limb_part.segment_textures[0] if limb_part.segment_textures.size() > 0 else null
			var tex_b: Texture2D = limb_part.segment_textures[1] if limb_part.segment_textures.size() > 1 else null
			var seg1 := piv[1].distance_to(piv[0]) if piv.size() > 1 else 50.0
			var seg2 := (tex_b.get_height() - piv[2].y) if tex_b != null and piv.size() > 2 else 50.0
			for i in 2:
				var seg := LimbChainBuilder.Segment.new()
				seg.organ = limb_part
				seg.length = seg1 if i == 0 else seg2
				seg.joint_min = -70.0
				seg.joint_max = 70.0
				seg.tip_radius = 4.0
				chain.segments.append(seg)
			chain.base_angle_deg = 90.0
			if limb_part.segment_textures.size() >= 2:
				rig.segment_textures = limb_part.segment_textures
				rig.segment_pivots = _pivots_of(limb_part)
			rig.setup(chain, _motion_for(&"attack"), hip_world)
			rig.walk_mode = kind == PartData.Category.LOCOMOTION
			rig.facing = facing
			rig.z_index = 1
			_rigs.append(rig)


## 躯干绘制：朝左时绕机体中心水平镜像；跳跃时整体上下偏移
## 碰撞轮廓：绿线 = 机身矩形，青线 = 腿根胶囊
func _draw_collision_gizmos() -> void:
	var green := Color(0.2, 1.0, 0.3, 0.65)
	var cyan := Color(0.3, 0.9, 1.0, 0.65)
	if _torso_shape != null and _torso_shape.shape is RectangleShape2D:
		var r: RectangleShape2D = _torso_shape.shape
		draw_rect(Rect2(_torso_shape.position - r.size * 0.5, r.size), green, false, 2.0)
	if _shape_node != null and _shape_node.shape is CapsuleShape2D:
		var c: CapsuleShape2D = _shape_node.shape
		var top := _shape_node.position + Vector2(0.0, -c.height * 0.5 + c.radius)
		var bottom := _shape_node.position + Vector2(0.0, c.height * 0.5 - c.radius)
		draw_line(top, bottom, cyan, 4.0)
		draw_arc(top, c.radius, PI, TAU, 16, cyan, 2.0)
		draw_arc(bottom, c.radius, 0.0, PI, 16, cyan, 2.0)


## 躯干绘制：朝左时绕机体中心水平镜像；跳跃时整体上下偏移
func _draw_parts() -> void:
	var body_w: float = _assembly_body.bounds.size.x
	var mirror := facing < 0.0
	var drop := Vector2(0.0, _body_offset_y)
	for part in _assembly_body.parts:
		if part.data.texture == null:
			continue
		var tex: Texture2D = part.data.texture
		var origin: Vector2 = part.position + part.data.texture_offset + drop
		if not mirror:
			draw_texture(tex, origin)
		else:
			# 用负 scale 翻转贴图，位置换算成镜像后的左上角
			var cx := body_w * 0.5
			draw_set_transform(Vector2(cx, 0.0), 0.0, Vector2(-1.0, 1.0))
			draw_texture(tex, Vector2(origin.x - cx, origin.y))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	if _assembly_body != null:
		_draw_parts()
		if DevFlags.show_collision:
			_draw_collision_gizmos()
		return
	if _layout == null:
		return
	var flesh := _flesh()
	# 1) 通用肉膜：一张贴图，多边形自动裁切 + 镜像平铺
	for loop in _layout.loops:
		if loop.size() < 3:
			continue
		if flesh != null:
			var uvs := PackedVector2Array()
			for p in loop:
				uvs.append(_mirror_uv(p))
			var colors := PackedColorArray()
			colors.resize(loop.size())
			colors.fill(Color(1, 1, 1, 1))
			draw_polygon(loop, colors, uvs, flesh)
		else:
			draw_colored_polygon(loop, BodyLayout.FLESH)
	# 2) 内阴影：轮廓往重心收一点，压暗，读成一整坨有厚度的肉
	for loop in _layout.loops:
		if loop.size() < 3:
			continue
		var centroid := Vector2.ZERO
		for p in loop:
			centroid += p
		centroid /= float(loop.size())
		var inner := PackedVector2Array()
		for p in loop:
			inner.append(centroid.lerp(p, 0.86))
		draw_colored_polygon(inner, Color(0, 0, 0, 0.16))
	# 3) 器官叠加：只在透视模式画
	if show_organs:
		for part in _layout.parts:
			var rect: Rect2 = part["rect"]
			var tex: Texture2D = part["texture"]
			if tex != null:
				draw_texture_rect(tex, rect, false, Color(1, 1, 1, 0.85))
			else:
				var c: Color = part["color"]
				draw_rect(rect.grow(-1.5), Color(c.r, c.g, c.b, 0.5))
	# 4) 缝合线：只在器官交界处（方案 B）
	_draw_seams()
	# 5) 外轮廓压暗
	for loop in _layout.loops:
		if loop.size() < 2:
			continue
		var closed := PackedVector2Array(loop)
		closed.append(loop[0])
		draw_polyline(closed, Color(0.14, 0.07, 0.08, 0.9), 2.0)


## 缝合线：虚线 + 横跨的针脚；位置来自器官交界，不做任何贴图变换
func _draw_seams() -> void:
	for seam in _layout.seams:
		var a: Vector2 = seam["from"]
		var b: Vector2 = seam["to"]
		var total := a.distance_to(b)
		if total < 1.0:
			continue
		var dir := (b - a) / total
		var nrm := Vector2(-dir.y, dir.x)
		var t := 0.0
		var on := true
		while t < total:
			var step := 6.0 if on else 5.0
			var t2 := minf(t + step, total)
			if on:
				draw_line(a + dir * t, a + dir * t2, SEAM_COLOR, 2.0)
			t = t2
			on = not on
		var k := 12.0
		while k < total:
			var mid := a + dir * k
			draw_line(mid - nrm * 4.0, mid + nrm * 4.0, STITCH_COLOR, 1.6)
			k += 24.0


## 疤痕贴图：同样用多边形裁切 + 镜像平铺，但贴图尺度小、每具身体偏移不同
func _draw_scars() -> void:
	var tex := _scar()
	if tex == null:
		return
	for loop in _layout.loops:
		if loop.size() < 3:
			continue
		var uvs := PackedVector2Array()
		for p in loop:
			var q: Vector2 = p + _scar_offset
			uvs.append(Vector2(_tri(q.x / SCAR_TILE), _tri(q.y / SCAR_TILE)))
		var colors := PackedColorArray()
		colors.resize(loop.size())
		colors.fill(Color(1, 1, 1, 1))
		draw_polygon(loop, colors, uvs, tex)


static func _scar() -> Texture2D:
	if not _scar_loaded:
		_scar_loaded = true
		if ResourceLoader.exists(SCAR_PATH):
			_scar_texture = load(SCAR_PATH) as Texture2D
	return _scar_texture


## 镜像平铺：uv 走三角波，一张方形贴图就能无缝铺满。
## 每具身体用一个随机偏移，避免不同身体看到同一块纹理
func _mirror_uv(p: Vector2) -> Vector2:
	var q := p + _flesh_offset
	return Vector2(_tri(q.x / FLESH_TILE), _tri(q.y / FLESH_TILE))


static func _tri(t: float) -> float:
	var m := fposmod(t, 2.0)
	return m if m <= 1.0 else 2.0 - m


static func _flesh() -> Texture2D:
	if not _flesh_loaded:
		_flesh_loaded = true
		if ResourceLoader.exists(FLESH_PATH):
			_flesh_texture = load(FLESH_PATH) as Texture2D
	return _flesh_texture


func _on_limb_hit(_damage: float) -> void:
	attacked.emit(1)


## 透视：显示体内器官
func toggle_xray() -> void:
	show_organs = not show_organs
	queue_redraw()


## 有没有可用的肢体链；没有时 J 退回旧的近战判定
func has_limbs() -> bool:
	return not _rigs.is_empty()


func _motion_for(action: StringName) -> LimbMotion:
	if action == &"attack2":
		return load("res://resources/motions/thrust.tres") as LimbMotion
	return load("res://resources/motions/swing.tres") as LimbMotion


func attack() -> bool:
	if dead or _attack_timer > 0.0:
		return false
	_attack_timer = tuning.attack_cooldown
	_flash_timer = 0.12
	_attack_visual.scale.x = facing
	_attack_visual.show()
	var hits := 0
	var slice := get_parent()
	var attack_center := global_position + Vector2(0.0, -50.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D or not slice.is_ancestor_of(enemy):
			continue
		if enemy.dead or not enemy.has_method("take_damage"):
			continue
		var offset: Vector2 = enemy.global_position - attack_center
		if offset.x * facing < 0.0 or absf(offset.x) > tuning.attack_range:
			continue
		if absf(offset.y) > tuning.attack_vertical:
			continue
		enemy.take_damage(tuning.damage)
		hits += 1
		# Death darkening always wins over an in-flight hit flash.
		var flash: Tween = enemy.create_tween()
		flash.tween_method(func(color: Color) -> void:
			if is_instance_valid(enemy):
				enemy.modulate = Color(0.45, 0.45, 0.45) if enemy.dead else color,
			Color(1.8, 1.3, 0.9), Color.WHITE, 0.12)
	attacked.emit(hits)
	return true


func take_hit(damage: float, source: Vector2) -> void:
	if dead or _invulnerability_timer > 0.0 or damage <= 0.0:
		return
	_invulnerability_timer = tuning.invulnerability_duration
	hp = maxf(0.0, hp - damage)
	var direction := signf(global_position.x - source.x)
	if is_zero_approx(direction):
		direction = -facing
	add_knockback(Vector2(absf(tuning.hit_knockback.x) * direction, tuning.hit_knockback.y))
	_body.modulate = Color(1.0, 0.35, 0.3)
	if hp <= 0.0:
		dead = true
		super.set_walk_intent(0.0)
		jump_requested = false
		velocity = Vector2.ZERO
		motor_speed = 0.0
		vertical_speed = 0.0
		external_velocity = Vector2.ZERO
		remove_from_group("creature")
		_attack_visual.hide()
		_body.modulate = Color(0.45, 0.45, 0.45)
	hurt.emit()
	if dead:
		died.emit()
