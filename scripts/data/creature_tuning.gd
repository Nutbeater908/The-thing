## 生物在关卡里的行为参数。改手感只动这个资源，不改代码。
class_name CreatureTuning
extends Resource

@export var walk_force := 250.0        ## 每格腿长提供的水平推力
@export var jump_impulse := 70.0       ## 每格腿长提供的跳跃冲量
@export var claw_damage := 8.0
@export var attack_cooldown := 0.35
@export var attack_reach_pad := 1.0    ## 爪末端外多出的攻击距离（格）
@export var hit_flash := 0.15

@export var cell_px := 16.0            ## 一格的像素边长
@export var linear_damp := 1.2
@export var angular_damp := 3.5
@export var friction := 0.0
