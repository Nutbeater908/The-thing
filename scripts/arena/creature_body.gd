## 关卡里的生物实体：按器官蓝图生成碰撞、视觉和质量分布。
##
## 机关有独立 HP，受击时按攻击方向选中最突出的器官。
## 心脏 / 大脑 / 寄生虫任意一个被摧毁 → 死亡。
## 朝向由鼠标左右位置决定，切换时整个身体镜像。
class_name CreatureBody
extends RigidBody2D

signal died

var cell_px := 16.0
var _tuning: CreatureTuning


## 一个器官实例：数据 + 运行时 HP + 它的显示/碰撞节点
class Part:
	var entry: Dictionary
	var data: OrganData
	var rotation: int
	var anchor: Vector2i
	var hp: float
	var nodes: Array = []
	var polys: Array = []


var stats: CreatureStats
var facing := 1
var link_snapshot: Array = []   # 带入关卡的拉线快照，供完整存活校验使用
var _dead := false

var _blueprint: Array = []            # 当前存活的器官
var _parts: Array[Part] = []
var _contact_points: Array[Vector2] = []
var _attack_timer := 0.0

# 腿部表现：弹簧驱动的摆动与屈膝
var _leg_swing := 0.0
var _leg_swing_v := 0.0
var _leg_bend := 0.0
var _leg_bend_v := 0.0

var _base_com := Vector2.ZERO
var _mirror_shapes: Array = []        # [{node, x}]
var _mirror_polys: Array = []         # [{node, points}]
var _mirror_axis := 0.0               # 包围盒中心（格坐标）
var _mirror_axis_px := 0.0            # 包围盒中心（像素）


func _ready() -> void:
	add_to_group("creature")


func setup(blueprint: Array, links: Array = []) -> void:
	_blueprint = blueprint.duplicate(true)
	link_snapshot = links.duplicate(true)
	_tuning = CreatureStats.tuning()
	cell_px = _tuning.cell_px

	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM

	# 不设置的话 get_contact_count() 永远是 0
	max_contacts_reported = 16

	# 直接施加推力，不靠地面摩擦驱动
	var mat := PhysicsMaterial.new()
	mat.friction = _tuning.friction
	mat.bounce = 0.0
	physics_material_override = mat

	linear_damp = _tuning.linear_damp
	angular_damp = _tuning.angular_damp
	can_sleep = false

	_spawn_parts()
	_recompute()


func _process(delta: float) -> void:
	if stats == null:
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)

	# 面始终朝向鼠标所在的一侧
	var center := to_global(center_of_mass)
	var mouse := get_global_mouse_position()
	var want := 1 if mouse.x >= center.x else -1
	if want != facing:
		_apply_facing(want)

	_update_legs(delta)
	queue_redraw()


## 腿部姿态：速度驱动的摆动 + 离地收腿
func _update_legs(delta: float) -> void:
	var target_swing := clampf(-linear_velocity.x * 0.0015, -0.55, 0.55)
	_leg_swing_v += (target_swing - _leg_swing) * 90.0 * delta
	_leg_swing_v *= exp(-7.0 * delta)
	_leg_swing += _leg_swing_v * delta

	var target_bend := 0.0
	if not _any_leg_grounded():
		target_bend = 0.45 if linear_velocity.y < 0.0 else 0.15
	_leg_bend_v += (target_bend - _leg_bend) * 80.0 * delta
	_leg_bend_v *= exp(-9.0 * delta)
	_leg_bend += _leg_bend_v * delta


func _any_leg_grounded() -> bool:
	for limb in stats.legs():
		if _leg_grounded(limb):
			return true
	return false


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_contact_points.clear()
	for i in state.get_contact_count():
		_contact_points.append(state.get_contact_local_position(i))


func _physics_process(_delta: float) -> void:
	if stats == null or _dead:
		return

	var dir := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir += 1.0
	dir = clampf(dir, -1.0, 1.0)

	if is_zero_approx(dir):
		return

	# 每条腿在自己的位置出力；悬空的腿不参与
	var com := to_global(center_of_mass)
	var total_force := Vector2.ZERO
	var total_torque := 0.0

	for limb in stats.legs():
		if not _leg_grounded(limb):
			continue
		var r := to_global(_leg_foot(limb) * cell_px) - com
		var f := Vector2(dir * float(limb.length) * _tuning.walk_force, 0.0)
		total_force += f
		total_torque += r.x * f.y - r.y * f.x

	# 净力按质心推，同时配平部件施力产生的旋转
	if total_force != Vector2.ZERO:
		apply_central_force(total_force)
		apply_torque(-total_torque)


func _unhandled_input(event: InputEvent) -> void:
	if stats == null or _dead:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_attack()
		return

	if not event.is_action_pressed("ui_accept"):
		return

	# 至少有一条腿接触地面才能起跳
	for limb in stats.legs():
		if _leg_grounded(limb):
			apply_central_impulse(Vector2(0, -stats.jump_impulse()))
			return


# ---------------------------------------------------------------- 受击

## 选中距离攻击源最近的器官并扣血
func take_hit(damage: float, source: Vector2) -> void:
	if _dead or _parts.is_empty():
		return

	var best: Part = null
	var best_dist := INF

	for part in _parts:
		var d := _part_center(part).distance_to(source)
		if d < best_dist:
			best_dist = d
			best = part

	if best == null:
		return

	best.hp -= damage
	# 受击时腿被甩一下
	_leg_swing_v -= signf(source.x - global_position.x) * 2.5
	_flash_part(best)
	if best.hp <= 0.0:
		_remove_part(best)


## 每只爪朝自己的伸展方向出击
func _attack() -> void:
	if _attack_timer > 0.0:
		return
	var claws := stats.claws()
	if claws.is_empty():
		return
	_attack_timer = _tuning.attack_cooldown

	for limb in claws:
		_hit_with(limb)


func _hit_with(limb) -> void:
	var origin := to_global((Vector2(limb.anchor) + Vector2(0.5, 0.5)) * cell_px)
	var dir: Vector2 = limb.direction
	if facing < 0:
		dir.x = -dir.x
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()

	var reach := (float(limb.length) + _tuning.attack_reach_pad) * cell_px

	for enemy in get_tree().get_nodes_in_group("enemies"):
		var offset: Vector2 = enemy.global_position - origin
		if offset.length() > reach:
			continue
		if offset.normalized().dot(dir) < 0.4:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(_tuning.claw_damage)


# ---------------------------------------------------------------- 存活

func _remove_part(part: Part) -> void:
	_parts.erase(part)
	_blueprint.erase(part.entry)

	for node in part.nodes:
		if is_instance_valid(node):
			node.queue_free()
	_mirror_shapes = _mirror_shapes.filter(func(e): return not part.nodes.has(e["node"]))
	_mirror_polys = _mirror_polys.filter(func(e): return not part.nodes.has(e["node"]))

	if _parts.is_empty():
		_die()
		return

	_recompute()
	_check_alive()


func _check_alive() -> void:
	var has_brain := false
	var has_heart := false
	var has_parasite := false

	for part in _parts:
		if part.data.is_brain:
			has_brain = true
		if part.data.is_heart:
			has_heart = true
		if part.data.is_parasite:
			has_parasite = true

	if not (has_brain and has_heart and has_parasite):
		_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	died.emit()


## 导出当前存活器官（含剩余 HP），供回城时写回 RunState
func export_organs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part in _parts:
		out.append({
			"id": part.data.id,
			"rotation": part.rotation,
			"anchor": part.anchor,
			"hp": part.hp,
		})
	return out


# ---------------------------------------------------------------- 几何

## 腿部绘制：两节线，膝盖按弯曲量向面朝方向凸出
func _draw() -> void:
	if stats == null:
		return
	for limb in stats.legs():
		_draw_leg(limb)


func _draw_leg(limb) -> void:
	var hip := _leg_hip(limb) * cell_px
	var total := float(limb.length) * cell_px
	var dir := Vector2.DOWN.rotated(_leg_swing)
	var foot := hip + dir * total

	var mid := (hip + foot) * 0.5
	var knee := mid + dir.orthogonal() * facing * (_leg_bend * total * 0.5)

	var leg_color := Color(0.35, 0.55, 0.8)
	draw_line(hip, knee, leg_color, 4.0)
	draw_line(knee, foot, leg_color, 4.0)
	draw_circle(knee, 3.0, Color(0.5, 0.7, 0.95))
	draw_circle(foot, 3.5, Color(0.6, 0.75, 0.95))


## 腿根在刚体局部坐标中的格位置（含朝向镜像）
func _leg_hip(limb) -> Vector2:
	var p: Vector2 = Vector2(limb.anchor) + Vector2(0.5, 0.5)
	if facing < 0:
		p.x = 2.0 * _mirror_axis - p.x
	return p


func _leg_foot(limb) -> Vector2:
	var p: Vector2 = Vector2(limb.anchor) + limb.direction * float(limb.length) + Vector2(0.5, 0.5)
	if facing < 0:
		p.x = 2.0 * _mirror_axis - p.x
	return p


## 注意：get_contact_local_position() 返回的其实是全局坐标
func _leg_grounded(limb) -> bool:
	var foot := to_global(_leg_foot(limb) * cell_px)
	for p in _contact_points:
		if p.distance_to(foot) <= cell_px * 0.75:
			return true
	return false


func _part_center(part: Part) -> Vector2:
	var cells := part.data.rotated_cells(part.rotation)
	var sum := Vector2.ZERO
	for c in cells:
		sum += Vector2(part.anchor + c) + Vector2(0.5, 0.5)
	var p := (sum / float(cells.size())) * cell_px
	if facing < 0:
		p.x = 2.0 * _mirror_axis_px - p.x
	return to_global(p)


# ---------------------------------------------------------------- 构造 / 重建

func _spawn_parts() -> void:
	var lib := OrganLibrary.catalog()

	for entry in _blueprint:
		var data: OrganData = lib.get(entry["id"])
		if data == null:
			continue

		var part := Part.new()
		part.entry = entry
		part.data = data
		part.rotation = entry["rotation"]
		part.anchor = entry["anchor"]
		part.hp = data.max_hp

		for c in data.rotated_cells(part.rotation):
			_add_cell(part.anchor + c, data.color, part)

		_parts.append(part)


func _add_cell(cell: Vector2i, color: Color, part: Part) -> void:
	var center := (Vector2(cell) + Vector2(0.5, 0.5)) * cell_px
	var half := Vector2(cell_px, cell_px) * 0.5

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(cell_px, cell_px)
	shape.shape = rect
	shape.position = center
	add_child(shape)
	_mirror_shapes.append({"node": shape, "x": center.x})
	part.nodes.append(shape)

	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		center + Vector2(-half.x, -half.y),
		center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y),
		center + Vector2(-half.x, half.y),
	])
	poly.color = color
	poly.z_index = -1   # 器官在腿的下层
	add_child(poly)
	_mirror_polys.append({"node": poly, "points": poly.polygon})
	part.nodes.append(poly)
	part.polys.append(poly)


func _recompute() -> void:
	stats = CreatureStats.from_blueprint(_blueprint)

	mass = maxf(stats.mass, 1.0)
	_base_com = (stats.centroid + Vector2(0.5, 0.5)) * cell_px

	var i := stats.inertia() * cell_px * cell_px
	if i > 0.0:
		inertia = i

	# 重新计算镜像轴
	var min_x := 1 << 30
	var max_x := -(1 << 30)
	for part in _parts:
		for c in part.data.rotated_cells(part.rotation):
			var cell: Vector2i = part.anchor + c
			min_x = mini(min_x, cell.x)
			max_x = maxi(max_x, cell.x)

	if min_x <= max_x:
		_mirror_axis = (float(min_x) + float(max_x) + 1.0) * 0.5
		_mirror_axis_px = _mirror_axis * cell_px

	_apply_facing(facing)


func _apply_facing(f: int) -> void:
	facing = f
	var flip := f < 0

	for entry in _mirror_shapes:
		if not is_instance_valid(entry["node"]):
			continue
		var node: CollisionShape2D = entry["node"]
		var x: float = entry["x"]
		node.position.x = (2.0 * _mirror_axis_px - x) if flip else x

	for entry in _mirror_polys:
		if not is_instance_valid(entry["node"]):
			continue
		var node: Polygon2D = entry["node"]
		var base: PackedVector2Array = entry["points"]
		var out := PackedVector2Array()
		for i in base.size():
			var x := base[i].x
			out.append(Vector2((2.0 * _mirror_axis_px - x) if flip else x, base[i].y))
		node.polygon = out

	var com_x := (2.0 * _mirror_axis_px - _base_com.x) if flip else _base_com.x
	center_of_mass = Vector2(com_x, _base_com.y)


func _flash_part(part: Part) -> void:
	for node in part.polys:
		if is_instance_valid(node):
			node.modulate = Color(1.0, 0.35, 0.35)
	get_tree().create_timer(_tuning.hit_flash).timeout.connect(_restore_part.bind(part))


func _restore_part(part: Part) -> void:
	for node in part.polys:
		if is_instance_valid(node):
			node.modulate = Color.WHITE
