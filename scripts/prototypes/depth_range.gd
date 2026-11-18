## 独立原型：三维规则空间 + 二维机体。单位为米，与旧世界像素无关。
## 不访问存档、不依赖 autoload、不修改现有机体脚本。
extends Node3D

const TERRAIN := 1
const TARGET := 2
const WALK_SPEED := 5.0
const ACCEL := 22.0
const JUMP_SPEED := 7.0
const RANGE := 80.0
const SHOT_INTERVAL := 0.12

@export var allow_air_control := false
@export var allow_air_turn := true
@export var camera_elevation := 25.0
@export var camera_yaw := 12.0
var angled_camera := false
## 移动包络独立于精灵和朝向：X 宽、Y 高、Z 纵深。
@export var body_width := 1.2
@export var body_height := 3.6
@export var body_depth := 2.2
var footprint: MeshInstance3D
var contact_marker: MeshInstance3D
var sprite_layout := []
@export var restore_depth_occlusion := true
var depth_restore_materials: Array[ShaderMaterial] = []

var player: CharacterBody3D
var camera: Camera3D
var visual: Node3D
var muzzle: MeshInstance3D
var aim_marker: MeshInstance3D
var impact_marker: MeshInstance3D
var shadow: MeshInstance3D
var debug_shape: MeshInstance3D
var trace: MeshInstance3D
var targets: Array[StaticBody3D] = []
var aim_point := Vector3.ZERO
var actual_point := Vector3.ZERO
var facing := 1.0
var debug_visible := true
var shots := 0
var hits := 0
var blocked := false
var _shot_clock := 0.0
var _trace_clock := 0.0
var _air_velocity := Vector2.ZERO
var _was_grounded := false

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("202932"))
	camera = $Camera3D
	_build_range()
	_build_player()
	aim_marker = _marker("Aim", Color("ffd166"), 0.09)
	impact_marker = _marker("ActualHit", Color("ff5656"), 0.075)
	trace = MeshInstance3D.new()
	trace.name = "ShotTrace"
	add_child(trace)
	_update_camera(1.0)

func _mat(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _box(label: String, pos: Vector3, dimensions: Vector3, tint: Color, layer := TERRAIN) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 0
	add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collider.shape = shape
	body.add_child(collider)
	var model := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	model.mesh = mesh
	model.material_override = _mat(tint)
	body.add_child(model)
	return body

func _build_range() -> void:
	_box("Floor", Vector3(4, -0.3, 0), Vector3(48, 0.6, 18), Color("454f59"))
	_box("RearWall", Vector3(4, 2, -9), Vector3(48, 4, 0.4), Color("303b48"))
	_box("TallWall", Vector3(8, 2, 1), Vector3(0.7, 4, 5), Color("687789"))
	_box("LowCover", Vector3(1, 0.6, 1), Vector3(3, 1.2, 1), Color("9a8060"))
	_box("Platform", Vector3(17, 0.8, -4), Vector3(7, 1.6, 5), Color("526879"))
	var ramp := _box("Ramp", Vector3(10.7, 0.72, -4), Vector3(6.2, 0.25, 3), Color("657c87"))
	ramp.rotation.z = deg_to_rad(15.0)
	# 地面参考线只作装饰，没有碰撞。
	for x in range(-20, 29, 2):
		_line_on_floor(Vector3(x, 0.008, 0), Vector3(0.018, 0.012, 18))
	for z in range(-8, 9, 2):
		_line_on_floor(Vector3(4, 0.008, z), Vector3(48, 0.012, 0.018))
	for entry in [[Vector3(5, 1.1, -5), "NearTarget"], [Vector3(18, 2.7, -4), "RaisedTarget"]]:
		var target := _box(entry[1], entry[0], Vector3(1.1, 2.2, 0.8), Color("9b5550"), TARGET)
		target.set_meta("hits", 0)
		targets.append(target)

func _line_on_floor(pos: Vector3, dimensions: Vector3) -> void:
	var model := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	model.mesh = mesh
	model.material_override = _mat(Color("596571"))
	model.position = pos
	add_child(model)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "PrototypePlayer"
	player.position = Vector3(-5, 0.05, 3)
	player.collision_layer = 4
	player.collision_mask = TERRAIN
	player.floor_snap_length = 0.25
	add_child(player)
	var collider := CollisionShape3D.new()
	collider.name = "MovementShape"
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(body_width, body_height, body_depth)
	collider.shape = body_box
	collider.position.y = body_height * 0.5
	player.add_child(collider)
	debug_shape = MeshInstance3D.new()
	var shell := BoxMesh.new()
	shell.size = body_box.size
	debug_shape.mesh = shell
	debug_shape.position = collider.position
	var shell_mat := _mat(Color(0.2, 1, 0.6, 0.12), true)
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_shape.material_override = shell_mat
	player.add_child(debug_shape)
	visual = Node3D.new()
	visual.name = "BillboardVisual"
	player.add_child(visual)
	_build_calibrated_visual()
	footprint = MeshInstance3D.new()
	footprint.name = "GroundFootprint"
	add_child(footprint)
	var outline := ImmediateMesh.new()
	outline.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat(Color("66ff99"), true))
	for corner in [Vector3(-body_width/2, 0, -body_depth/2), Vector3(body_width/2, 0, -body_depth/2), Vector3(body_width/2, 0, body_depth/2), Vector3(-body_width/2, 0, body_depth/2), Vector3(-body_width/2, 0, -body_depth/2)]:
		outline.surface_add_vertex(corner)
	outline.surface_end()
	footprint.mesh = outline
	contact_marker = _marker("GroundContact", Color("ffffff"), 0.065)
	muzzle = _marker("Muzzle", Color("66d9ff"), 0.06)
	shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.012
	shadow.mesh = disc
	shadow.material_override = _mat(Color("222a30"))
	add_child(shadow)

## 直接读取 .tres 中的已标定坐标，不依赖旧装配脚本或重复写死坐标。
func _resource_vector(path: String, uid: String, property := "offset") -> Vector2:
	var text := FileAccess.get_file_as_string(path)
	var block := text
	if not uid.is_empty():
		for section in text.split("[sub_resource"):
			if section.contains('uid = &"' + uid + '"'):
				block = section
				break
	var pattern := RegEx.new()
	pattern.compile(property + " = Vector2\\(([-0-9.]+), *([-0-9.]+)\\)")
	var found := pattern.search(block)
	assert(found != null, "Missing calibrated vector: " + path + ":" + uid + ":" + property)
	return Vector2(float(found.get_string(1)), float(found.get_string(2)))

func _build_calibrated_visual() -> void:
	var chassis := "res://resources/parts/chassis.tres"
	var leg := "res://resources/parts/leg_standard.tres"
	var hip := _resource_vector(chassis, "hip")
	var upper := hip - _resource_vector(leg, "pivot_hip")
	var shin := upper + _resource_vector(leg, "pivot_knee_u") - _resource_vector(leg, "pivot_knee_l")
	var foot := shin + _resource_vector(leg, "pivot_ankle_s") - _resource_vector(leg, "pivot_ankle_f")
	var files := ["chassis_scout.png", "leg_upper.png", "leg_shin.png", "leg_foot.png"]
	var offsets := [_resource_vector(chassis, "", "texture_offset"), upper, shin, foot]
	var foot_texture: Texture2D = load("res://art/parts/leg_foot.png")
	var bottom := foot.y + foot_texture.get_height()
	var scale_px := body_height / (bottom * cos(deg_to_rad(camera_elevation)))
	for i in files.size():
		var sprite := Sprite3D.new()
		sprite.texture = load("res://art/parts/" + files[i])
		sprite.pixel_size = scale_px
		var center: Vector2 = offsets[i] + sprite.texture.get_size() * 0.5
		sprite.position = Vector3((center.x - hip.x) * scale_px, (bottom - center.y) * scale_px, 0)
		sprite.shaded = false
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		visual.add_child(sprite)
		var restore := MeshInstance3D.new()
		restore.name = "DepthRestore%d" % i
		var plane := QuadMesh.new()
		plane.size = sprite.texture.get_size() * scale_px
		restore.mesh = plane
		restore.position = sprite.position
		var material := ShaderMaterial.new()
		material.shader = load("res://scripts/prototypes/depth_restore.gdshader")
		material.set_shader_parameter("sprite_texture", sprite.texture)
		material.render_priority = 10 + i
		restore.material_override = material
		# 补绘不投影，也不扩大碰撞体。
		restore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(restore)
		depth_restore_materials.append(material)
		sprite_layout.append({"origin": offsets[i], "size": sprite.texture.get_size()})

func _marker(label: String, tint: Color, radius: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2
	node.mesh = ball
	node.material_override = _mat(tint, true)
	add_child(node)
	return node

## 世界空间输入仍供测试使用；玩家键盘输入按镜头地面基向量转换。
func screen_right() -> Vector3:
	return Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(camera_yaw if angled_camera else 0.0))

func screen_back() -> Vector3:
	return Vector3.BACK.rotated(Vector3.UP, deg_to_rad(camera_yaw if angled_camera else 0.0))

func screen_intent_to_world(intent: Vector2) -> Vector2:
	var world := screen_right() * intent.x + screen_back() * intent.y
	return Vector2(world.x, world.z)

func muzzle_position() -> Vector3:
	return player.position + screen_right() * facing * 0.65 + Vector3.UP * 2.25

func _key(code: Key) -> bool:
	return Input.is_physical_key_pressed(code)

func _physics_process(delta: float) -> void:
	var intent := Vector2(float(_key(KEY_D)) - float(_key(KEY_A)), float(_key(KEY_S)) - float(_key(KEY_W))).limit_length(1.0)
	advance_player(delta, screen_intent_to_world(intent), false)
	update_aim(get_viewport().get_mouse_position())
	_shot_clock = maxf(0, _shot_clock - delta)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _shot_clock <= 0:
		fire_at(aim_point)
		_shot_clock = SHOT_INTERVAL
	_trace_clock = maxf(0, _trace_clock - delta)
	trace.visible = debug_visible and _trace_clock > 0
	debug_shape.visible = debug_visible
	footprint.visible = debug_visible and shadow.visible
	contact_marker.visible = debug_visible and shadow.visible
	aim_marker.visible = debug_visible
	impact_marker.visible = debug_visible
	$HUD/Info.text = "纵深射击原型 | WASD 平面移动 · 空格跳跃 · 鼠标瞄准/左键射击 · F3 调试 · F4 遮挡修正 · F5 镜头对比 · R 复位\n黄点=期望瞄准点  红点=枪口实际命中点  青点=枪口 | 射击 %d / 靶命中 %d | %s\n占位机体没有步态；空中默认不能改变平面速度。" % [shots, hits, "枪口路径受阻" if blocked else "射界通畅"]

## 对象方法供隔离测试调用，不注入输入。
func advance_player(delta: float, intent: Vector2, jump: bool) -> void:
	var grounded := player.is_on_floor()
	if grounded:
		player.velocity.x = move_toward(player.velocity.x, intent.x * WALK_SPEED, ACCEL * delta)
		player.velocity.z = move_toward(player.velocity.z, intent.y * WALK_SPEED, ACCEL * delta)
		if jump:
			_air_velocity = Vector2(player.velocity.x, player.velocity.z)
			player.velocity.y = JUMP_SPEED
	elif allow_air_control:
		player.velocity.x = move_toward(player.velocity.x, intent.x * WALK_SPEED, ACCEL * delta)
		player.velocity.z = move_toward(player.velocity.z, intent.y * WALK_SPEED, ACCEL * delta)
	if not grounded:
		player.velocity.y -= 18.0 * delta
	player.move_and_slide()
	_was_grounded = player.is_on_floor()
	# 阴影以地面射线定位，与离地高度分开。
	var floor_hit := _ray(player.position + Vector3.UP * 0.1, player.position + Vector3.DOWN * 50, TERRAIN)
	shadow.visible = not floor_hit.is_empty()
	if shadow.visible:
		shadow.position = floor_hit["position"] + Vector3.UP * 0.012
		footprint.position = floor_hit["position"] + Vector3.UP * 0.025
		contact_marker.position = floor_hit["position"] + Vector3.UP * 0.04

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_SPACE and player.is_on_floor():
		player.velocity.y = JUMP_SPEED
	elif event.physical_keycode == KEY_F3:
		debug_visible = not debug_visible
	elif event.physical_keycode == KEY_F4:
		restore_depth_occlusion = not restore_depth_occlusion
	elif event.physical_keycode == KEY_F5:
		angled_camera = not angled_camera
	elif event.physical_keycode == KEY_R:
		player.position = Vector3(-5, 0.05, 3)
		player.velocity = Vector3.ZERO

func _process(delta: float) -> void:
	_update_camera(delta)
	# 精灵面向固定镜头；只在水平方向翻面，不旋转角色碰撞体。
	visual.rotation = Vector3(-deg_to_rad(camera_elevation), deg_to_rad(camera_yaw if angled_camera else 0.0), 0)
	# 整组镜像，同时翻转部件中心，关节不会因转身脱开。
	visual.scale.x = facing
	for material in depth_restore_materials:
		material.set_shader_parameter("ground_position", player.position)
		material.set_shader_parameter("ground_view_back", screen_back())
	for child in visual.get_children():
		if child is MeshInstance3D:
			child.visible = restore_depth_occlusion
	muzzle.position = muzzle_position()

func _update_camera(delta: float) -> void:
	var anchor := player.position + Vector3(0, 1.8, 0)
	var lead := clampf((get_viewport().get_mouse_position().x / maxf(get_viewport().get_visible_rect().size.x, 1) - 0.5) * 6, -3, 3)
	anchor += screen_right() * lead
	var offset := (Vector3.UP * sin(deg_to_rad(camera_elevation)) + screen_back() * cos(deg_to_rad(camera_elevation))) * 32
	camera.position = camera.position.lerp(anchor + offset, minf(1, delta * 8))
	camera.rotation_degrees = Vector3(-camera_elevation, camera_yaw if angled_camera else 0.0, 0)

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)

func update_aim(screen_pos: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var hit := _ray(origin, origin + direction * 150, TERRAIN | TARGET)
	if not hit.is_empty():
		aim_point = hit["position"]
	else:
		var plane := Plane(Vector3.UP, player.position.y + 2.25)
		var crossing: Variant = plane.intersects_ray(origin, direction)
		if crossing != null:
			aim_point = muzzle.position + ((crossing as Vector3) - muzzle.position).limit_length(RANGE)
		else:
			aim_point = muzzle.position + screen_right() * facing * RANGE
	if player.is_on_floor() or allow_air_turn:
		var side := (aim_point - player.position).dot(screen_right())
		if absf(side) > 0.1:
			facing = signf(side)
	muzzle.position = muzzle_position()
	var result := resolve_shot(aim_point)
	actual_point = result["position"]
	blocked = actual_point.distance_to(aim_point) > 0.2
	aim_marker.position = aim_point
	impact_marker.position = actual_point

func resolve_shot(target: Vector3) -> Dictionary:
	var start := muzzle_position()
	var delta := target - start
	if delta.length_squared() < 0.0001:
		return {"position": start, "collider": null}
	var end := start + delta.normalized() * minf(delta.length() + 0.02, RANGE)
	var hit := _ray(start, end, TERRAIN | TARGET)
	return hit if not hit.is_empty() else {"position": end, "collider": null}

func fire_at(target: Vector3) -> Dictionary:
	var result := resolve_shot(target)
	shots += 1
	var body: Variant = result.get("collider")
	if body is StaticBody3D and body.collision_layer == TARGET:
		hits += 1
		body.set_meta("hits", int(body.get_meta("hits", 0)) + 1)
	_draw_trace(muzzle_position(), result["position"])
	_trace_clock = 0.08
	return result

func _draw_trace(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _mat(Color("ffd166"), true))
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	trace.mesh = mesh
