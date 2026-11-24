## Occupant-free test stand for the existing 2D slice. No rewards or save writes.
extends Node2D

signal outcome(message: String)

const TERRAIN_LAYER := 1 << 8
const ENEMY_LAYER := 1 << 11
const BARREL_LENGTH := 66.0
const SHOT_RANGE := 1100.0
const ELEVATION_LIMIT := PI * 70.0 / 180.0
const TEST_DAMAGE := 15.0
const GRUNT = preload("res://resources/enemies/grunt.tres")

var actor
var target: Enemy
var cover: StaticBody2D
var pivot: Node2D
var muzzle: Marker2D
var in_arc := false
var _requested := false
var _trace_start := Vector2.ZERO
var _trace_end := Vector2.ZERO
var _trace_time := 0.0

func setup(player_node: Node2D) -> void:
	actor = player_node
	z_index = 4
	pivot = Node2D.new()
	pivot.name = "ShoulderPivot"
	add_child(pivot)
	muzzle = Marker2D.new()
	muzzle.name = "Muzzle"
	muzzle.position.x = BARREL_LENGTH
	pivot.add_child(muzzle)

	cover = StaticBody2D.new()
	cover.name = "TestCover"
	cover.position = Vector2(690, 415)
	cover.collision_layer = TERRAIN_LAYER
	cover.collision_mask = 0
	add_child(cover)
	var cover_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(38, 280)
	cover_shape.shape = rectangle
	cover.add_child(cover_shape)
	cover.add_child(_panel(rectangle.size, Color("555d68")))

	var stand := _panel(Vector2(20, 120), Color("444b55"))
	stand.position = Vector2(855, 437)
	add_child(stand)
	target = Enemy.new()
	target.name = "PassiveTarget"
	target.data = GRUNT.duplicate()
	target.data.size = Vector2(68, 148)
	target.data.max_hp = 45.0
	target.position = Vector2(855, 306)
	target.collision_layer = ENEMY_LAYER
	target.collision_mask = 0
	add_child(target)
	target.set_physics_process(false)
	update_aim(actor.global_position + Vector2(500, -310))

func _panel(dimensions: Vector2, tint: Color) -> Polygon2D:
	var half := dimensions * 0.5
	var panel := Polygon2D.new()
	panel.polygon = PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	panel.color = tint
	return panel

func queue_shot() -> void:
	_requested = true

func _physics_process(delta: float) -> void:
	_trace_time = maxf(0.0, _trace_time - delta)
	update_aim(get_global_mouse_position())
	if _requested:
		_requested = false
		var result := fire_at(get_global_mouse_position())
		outcome.emit(result["message"])
	queue_redraw()

func update_aim(aim: Vector2) -> void:
	if not is_instance_valid(actor):
		in_arc = false
		return
	var body: AssemblyBridge.Body = actor._assembly_body
	if body == null or body.root_index < 0:
		in_arc = false
		pivot.hide()
		return
	var part := body.parts[body.root_index]
	if part.data.socket(&"shoulder") == null:
		in_arc = false
		pivot.hide()
		return
	pivot.show()
	var shoulder := part.position + part.data.socket_offset(&"shoulder", part.rotation)
	if actor.facing < 0.0:
		# Match the horizontal mirror used in SlicePlayer._draw_parts.
		shoulder.x = body.bounds.size.x - shoulder.x
	shoulder.y += actor._body_offset_y
	pivot.global_position = actor.to_global(shoulder)
	var aim_delta := aim - pivot.global_position
	var forward: Vector2 = actor.global_transform.basis_xform(Vector2(actor.facing, 0.0)).normalized()
	var bearing := forward.angle_to(aim_delta)
	in_arc = aim_delta.length() > BARREL_LENGTH and absf(bearing) <= ELEVATION_LIMIT
	pivot.global_rotation = (forward.rotated(clampf(bearing, -ELEVATION_LIMIT, ELEVATION_LIMIT))).angle()

func fire_at(aim: Vector2) -> Dictionary:
	update_aim(aim)
	if not in_arc:
		return {"kind": &"rejected", "message": "目标超出转架射界、太近，或机身没有肩部接口。"}
	var origin := muzzle.global_position
	# A barrel projecting past a wall must not let the shot start on the other side.
	var obstruction := _ray(pivot.global_position, origin, TERRAIN_LAYER)
	if not obstruction.is_empty():
		return {"kind": &"blocked", "collider": obstruction["collider"], "message": "枪管碰到掩体，无法开火。"}
	var direction := (origin - pivot.global_position).normalized()
	var end := origin + direction * SHOT_RANGE
	var hit := _ray(origin, end, TERRAIN_LAYER | ENEMY_LAYER)
	_trace_start = origin
	_trace_end = hit.get("position", end)
	_trace_time = 0.085
	queue_redraw()
	var collider: Object = hit.get("collider")
	if collider == target:
		target.take_damage(TEST_DAMAGE)
		return {"kind": &"target", "collider": target, "message": "靶机已摧毁，可返回拼装。" if target.dead else "命中靶机 · 剩余耐久 %d" % target.hp}
	if collider != null:
		return {"kind": &"blocked", "collider": collider, "message": "射线被地形挡住。"}
	return {"kind": &"miss", "message": "未命中。"}

func _ray(from: Vector2, to: Vector2, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, mask, [actor.get_rid()])
	query.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(query)

func _draw() -> void:
	if not is_instance_valid(pivot) or not pivot.visible:
		return
	var base := to_local(pivot.global_position)
	var end := to_local(muzzle.global_position)
	draw_circle(base, 12.0, Color("252e36"))
	draw_line(base, end, Color("232a30"), 13.0, true)
	draw_line(base, end, Color("859099") if in_arc else Color("a16e43"), 6.0, true)
	draw_circle(base, 5.0, Color("b3b7b0"))
	if _trace_time > 0.0:
		draw_line(to_local(_trace_start), to_local(_trace_end), Color(1, 0.82, 0.47, 0.65), 2.0, true)
