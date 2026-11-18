## 独立材质试用；F8 切换原灰盒/钢板，使用原生三平面映射避免盒体 UV 拉伸。
extends "res://scripts/prototypes/module_range.gd"

var texture_enabled := true
var trial_surfaces: Array[MeshInstance3D] = []
var original_materials: Array[Material] = []
var trial_material: StandardMaterial3D
var floor_material: StandardMaterial3D
var diagnostic_mode := 5  ## 已验收：24m
const REPEAT_METRES := [4.0, 4.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0]
const DIAGNOSTIC_LABELS := ["4m / 无 Mipmap（原效果）", "4m / Mipmap+各向异性", "8m / Mipmap+各向异性", "12m / Mipmap+各向异性", "16m / Mipmap+各向异性", "24m / Mipmap+各向异性", "32m / Mipmap+各向异性", "48m / Mipmap+各向异性"]

func _apply_diagnostic_mode() -> void:
	var repeat_metres: float = REPEAT_METRES[diagnostic_mode]
	floor_material.uv1_scale = Vector3.ONE / repeat_metres
	floor_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR if diagnostic_mode == 0 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

func _ready() -> void:
	super._ready()
	trial_material = StandardMaterial3D.new()
	trial_material.albedo_texture = load("res://art/terrain/trials/steel_panels_a42358a8.jpg")
	trial_material.albedo_color = Color.WHITE
	trial_material.roughness = 0.88
	trial_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	trial_material.texture_repeat = true
	trial_material.uv1_triplanar = true
	trial_material.uv1_world_triplanar = true
	# 一张纹理对应约 4m，所有地板共用世界坐标，接缝不会每块重新起算。
	trial_material.uv1_scale = Vector3.ONE * 0.25
	floor_material = trial_material.duplicate() as StandardMaterial3D
	floor_material.albedo_texture = load("res://art/terrain/trials/concrete_5f50a3ba.png")
	floor_material.albedo_color = Color(0.6, 0.6, 0.6)
	floor_material.roughness = 0.95
	for module in $Terrain.get_children():
		if _uses_concrete(module):
			_register(module.get_node("Visual"))
	_register($Cover/EquipmentA/Visual)
	_apply_material_trial()
	_apply_diagnostic_mode()

func _uses_concrete(module: Node) -> bool:
	var label := String(module.name)
	return label.begins_with("Floor_") or label == "Ramp" or label.begins_with("Platform")

func _register(surface: MeshInstance3D) -> void:
	trial_surfaces.append(surface)
	original_materials.append(surface.material_override)

func _apply_material_trial() -> void:
	for i in trial_surfaces.size():
		var surface := trial_surfaces[i]
		var material: Material = floor_material if _uses_concrete(surface.get_parent()) else trial_material
		surface.material_override = material if texture_enabled else original_materials[i]

func _process(delta: float) -> void:
	super._process(delta)
	$HUD/Info.text += "\nF8 贴图/灰盒 · 地板/坡道/高台混凝土、设备钢板 · F9 过滤与尺度：%s" % DIAGNOSTIC_LABELS[diagnostic_mode]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9:
		diagnostic_mode = (diagnostic_mode + 1) % DIAGNOSTIC_LABELS.size()
		_apply_diagnostic_mode()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		texture_enabled = not texture_enabled
		_apply_material_trial()
		return
	super._unhandled_key_input(event)
