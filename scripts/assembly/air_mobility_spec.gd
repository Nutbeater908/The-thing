## 可由部件引用的空中水平驱动配置；不提供向上推力。
class_name AirMobilitySpec
extends Resource

@export_range(0.0, 3000.0, 10.0) var acceleration := 600.0
@export_range(0.0, 1500.0, 10.0) var speed_limit := 300.0
@export_range(0.0, 1000.0, 1.0) var supported_mass := 55.0
