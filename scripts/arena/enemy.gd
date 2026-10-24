## 关卡敌人：数据驱动，死亡后变成可搜刮的尸体。
##
## 存活时属于 "enemies" 组，死亡后转入 "corpses" 组并保留节点。
class_name Enemy
extends CharacterBody2D

const GRAVITY := 980.0
const MOVE_SPEED := 70.0

@export var data: EnemyData

var hp := 0.0
var loot: Array[StringName] = []
var dead := false
var absorbed := false

var _attack_timer := 0.0
var _highlighted := false


func _ready() -> void:
	add_to_group("enemies")
	hp = data.max_hp if data != null else 20.0
	loot = data.loot.duplicate() if data != null else []
	_build_visual()


func _physics_process(delta: float) -> void:
	if dead:
		return

	velocity.y += GRAVITY * delta
	_attack_timer = maxf(0.0, _attack_timer - delta)

	var creature = get_tree().get_first_node_in_group("creature")
	if creature != null:
		var dx: float = creature.global_position.x - global_position.x
		if absf(dx) > data.attack_range:
			velocity.x = signf(dx) * MOVE_SPEED
		else:
			velocity.x = 0.0
			_try_attack(creature)
	else:
		velocity.x = 0.0

	move_and_slide()


## 玩家靠近时高亮最近的一具尸体
func set_highlighted(on: bool) -> void:
	if _highlighted == on:
		return
	_highlighted = on
	queue_redraw()


func _draw() -> void:
	if not _highlighted:
		return
	var s: Vector2 = (data.size if data != null else Vector2(32, 32)) + Vector2(8, 8)
	draw_rect(Rect2(-s * 0.5, s), Color(1.0, 0.9, 0.3), false, 2.0)


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	if hp <= 0.0:
		_die()


func take_loot(index: int) -> StringName:
	if dead and index >= 0 and index < loot.size():
		return loot[index]
	return &""


func remove_loot(organ_id: StringName) -> void:
	if dead:
		loot.erase(organ_id)


func is_empty_corpse() -> bool:
	return dead and loot.is_empty()


func _try_attack(creature) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = data.attack_interval
	creature.take_hit(data.damage, global_position)


func _die() -> void:
	dead = true
	remove_from_group("enemies")
	add_to_group("corpses")
	modulate = Color(0.45, 0.45, 0.45)
	velocity = Vector2.ZERO

	# 尸体纯视觉：关掉碰撞，避免挡路
	collision_layer = 0
	collision_mask = 0


func _build_visual() -> void:
	if data == null:
		return

	var size: Vector2 = data.size

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	add_child(shape)

	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-size.x, -size.y) * 0.5,
		Vector2(size.x, -size.y) * 0.5,
		Vector2(size.x, size.y) * 0.5,
		Vector2(-size.x, size.y) * 0.5,
	])
	poly.color = data.color
	add_child(poly)
