## 关卡木桩：被攻击后反击，用来验证部件受击与方向判定。
class_name Dummy
extends StaticBody2D

@export var max_hp := 30.0
@export var attack_range := 130.0
@export var attack_damage := 10.0
@export var attack_interval := 1.2

var hp := 0.0
var _flash := 0.0
var _attack_timer := 0.0


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")


func hit(damage: float) -> void:
	if hp <= 0.0:
		return
	hp -= damage
	_flash = 0.15
	modulate = Color(1.0, 0.35, 0.35)
	if hp <= 0.0:
		queue_free()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			modulate = Color.WHITE

	if hp <= 0.0:
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)
	if _attack_timer > 0.0:
		return

	var creature = get_tree().get_first_node_in_group("creature")
	if creature == null:
		return

	# 用质心而不是节点原点：生物原点在网格左上角，不是身体中心
	var target: Vector2 = creature.to_global(creature.center_of_mass)
	var offset: Vector2 = target - global_position
	if offset.length() > attack_range:
		return

	_attack_timer = attack_interval
	creature.take_hit(attack_damage, global_position)
