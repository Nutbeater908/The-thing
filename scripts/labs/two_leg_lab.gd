extends Node2D
const BIPED = preload("res://scenes/labs/articulated_biped.tscn")
@onready var rig = $ArticulatedBiped
@onready var readout: Label = $HUD/Panel/Box/Readout
@onready var drive: CheckButton = $HUD/Panel/Box/Drive

func _ready() -> void:
	$HUD/Panel/Box/Buttons/Stand.pressed.connect(func(): rig.request_crouch(false))
	$HUD/Panel/Box/Buttons/Crouch.pressed.connect(func(): rig.request_crouch(true))
	$HUD/Panel/Box/Buttons/Reset.pressed.connect(_reset)
	drive.toggled.connect(func(enabled: bool): rig.drive_enabled = enabled)
	$HUD/Panel/Box/Assistance.toggled.connect(func(enabled: bool): rig.assistance_enabled = enabled)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		rig.request_jump()
		get_viewport().set_input_as_handled()

func _reset() -> void:
	var old = rig
	rig = BIPED.instantiate()
	rig.position = old.position
	remove_child(old)
	old.queue_free()
	add_child(rig)
	rig.drive_enabled = drive.button_pressed
	rig.assistance_enabled = $HUD/Panel/Box/Assistance.button_pressed

func _process(_delta: float) -> void:
	var d: Dictionary = rig.diagnostics()
	readout.text = "%s\n主体高度 %.1f / 目标 %.1f px\n主体倾角 %+.1f° · 脚底支持 %d/2\n全身质心 x %.1f · 足部漂移 %.1f px\n关节误差 %.2f px · 扭矩上限使用 %.0f%%\n异常触地：%s" % [d.status, d.height, d.target_height, d.tilt_deg, d.feet, d.com.x, d.foot_drift, d.joint_gap, d.saturation * 100.0, "是" if d.bad_contact else "否"]
	readout.text += "\n阶段 %s · %s\n向上辅助 %.0f N · 累计 %.0f / %.0f\n姿态辅助扭矩 %+.0f（非锁定）" % [d.phase, d.outcome, d.assist_force, d.assist_impulse, rig.tuning.jump_assist_impulse_cap, d.attitude_torque]
