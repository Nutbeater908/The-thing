extends "res://scripts/character/character_terrain_tuning.gd"
## Small playable slice: native movement plus shared combat/interaction distances.
@export var max_hp: float = 80.0
@export var damage: float = 12.0
@export var attack_range: float = 135.0
@export var attack_vertical: float = 100.0
@export var attack_cooldown: float = 0.35
@export var invulnerability_duration: float = 0.65
@export var hit_knockback: Vector2 = Vector2(125.0, -90.0)
@export var enemy_activation_distance: float = 240.0
@export var interact_range: float = 130.0

@export_group("关卡推进")
## 每多一关，敌人血量在基础上增加的比例
@export var enemy_hp_step: float = 0.35
## 每多一关，敌人伤害在基础上增加的比例
@export var enemy_damage_step: float = 0.25

