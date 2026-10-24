## 敌人数据：数值、吸收收益、尸体掉落。
##
## 普通敌人靠吸收给代币，精英靠吸收给器官。
class_name EnemyData
extends Resource

@export var id: StringName = &""
@export var display_name := ""
@export var color := Color(0.55, 0.5, 0.45)
@export var size := Vector2(40, 40)

@export_group("战斗")
@export var max_hp := 30.0
@export var damage := 10.0
@export var attack_range := 130.0
@export var attack_interval := 1.2

@export_group("吸收")
## 击杀后吸收获得的代币
@export var absorb_credits := 0
## 击杀后留在尸体里的器官；空表示没有器官掉落
@export var loot: Array[StringName] = []
