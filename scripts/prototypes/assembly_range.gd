## 拼装到纵深场景的独立接入；继承已验收材质、控制与射击。
extends "res://scripts/prototypes/material_range.gd"
const Visual3D = preload("res://scripts/prototypes/assembly_visual_3d.gd")
var assembly_snapshot: Assembly
var assembly_visual: Node3D
var build_screen: Control
var build_parent: Node
var build_mode: ProcessMode

func enter_from(build: Control) -> void:
	assembly_snapshot = Visual3D.snapshot(build.current_assembly())
	build_screen = build
	build_parent = build.get_parent()
	build_mode = build.process_mode
	build.hide()
	build.process_mode = Node.PROCESS_MODE_DISABLED
	build.get_tree().root.add_child(self)
	get_tree().current_scene = self

func _ready() -> void:
	# 独立 F6 时为空装配，不偷偷补入标准机体。
	if assembly_snapshot == null:
		assembly_snapshot = Assembly.new()
	assembly_visual = Visual3D.new()
	assembly_visual.prepare(assembly_snapshot)
	body_width = maxf(0.1, assembly_visual.pixel_bounds.size.x * Visual3D.METRES_PER_PIXEL)
	body_height = maxf(0.1, assembly_visual.pixel_bounds.size.y * Visual3D.METRES_PER_PIXEL * cos(deg_to_rad(camera_elevation)))
	# 部件没有纵深尺寸：body_depth 保留原型配置，明确不是按图推测。
	super._ready()
	var back := Button.new()
	back.text = "返回拼装 [Esc]"
	back.position = Vector2(20, 150)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(return_to_build)
	$HUD.add_child(back)

func _build_calibrated_visual() -> void:
	visual.add_child(assembly_visual)
	assembly_visual.build()
	depth_restore_materials.assign(assembly_visual.restore_materials)

func advance_player(delta: float, intent: Vector2, jump: bool) -> void:
	if assembly_visual != null and not assembly_visual.can_walk:
		intent = Vector2.ZERO
		jump = false
		player.velocity.x = 0
		player.velocity.z = 0
	super.advance_player(delta, intent, jump)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			return_to_build()
			return
		if event.physical_keycode == KEY_SPACE and not assembly_visual.can_walk:
			return
	super._unhandled_key_input(event)

func _process(delta: float) -> void:
	super._process(delta)
	for anchor in assembly_visual.get_children():
		for child in anchor.get_children():
			if child is MeshInstance3D:
				child.visible = restore_depth_occlusion
	$HUD/Info.text += "\n当前拼装：%d 部件 · 静态显示 · 纵深厚度暂用试验值 · %s" % [assembly_snapshot.parts.size(), "可行走" if assembly_visual.can_walk else "无可用直立腿：禁止移动/跳跃"]

func return_to_build() -> void:
	if not is_instance_valid(build_screen):
		return
	set_process(false)
	set_physics_process(false)
	build_screen.process_mode = build_mode
	build_screen.show()
	get_tree().current_scene = build_screen
	queue_free()
