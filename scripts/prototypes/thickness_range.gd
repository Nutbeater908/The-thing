## 可丢弃的浅厚度试验；复用模块地图、控制和瞄准。
extends "res://scripts/prototypes/module_range.gd"

@export var torso_depth := 0.65
var thickness_enabled := true
var thickness_root: Node3D
var far_leg_root: Node3D
var torso_sprite: Sprite3D
var torso_restore: MeshInstance3D
var contour_vertices := 0

func _build_calibrated_visual() -> void:
	super._build_calibrated_visual()
	torso_sprite = visual.get_child(0) as Sprite3D
	torso_restore = visual.get_node("DepthRestore0") as MeshInstance3D
	thickness_root = Node3D.new()
	thickness_root.name = "TorsoThickness"
	visual.add_child(thickness_root)
	var image := torso_sprite.texture.get_image()
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image, 0.5)
	var contours := bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), 2.0)
	# 只取最大连通轮廓，忽略透明碎屑。当前小样不复原内部孔洞。
	var outline := PackedVector2Array()
	var best_area := 0.0
	for candidate in contours:
		var area := 0.0
		for i in candidate.size():
			area += candidate[i].cross(candidate[(i + 1) % candidate.size()])
		if absf(area) > best_area:
			best_area = absf(area)
			outline = candidate
	var polygon := PackedVector2Array()
	for point in outline:
		polygon.append(Vector2(point.x - image.get_width() * 0.5, image.get_height() * 0.5 - point.y) * torso_sprite.pixel_size)
	contour_vertices = polygon.size()
	if polygon.size() >= 3:
		var shell := CSGPolygon3D.new()
		shell.name = "ExtrudedSilhouette"
		shell.polygon = polygon
		shell.depth = torso_depth
		shell.position = torso_sprite.position
		shell.use_collision = false
		shell.material = _mat(Color("38444f"))
		thickness_root.add_child(shell)
	# 同一标定图组，不另改关节点；远腿放在机身背后。
	far_leg_root = Node3D.new()
	far_leg_root.name = "FarLegLayer"
	visual.add_child(far_leg_root)
	for child in visual.get_children():
		if child is Sprite3D and child != torso_sprite:
			var far := child.duplicate() as Sprite3D
			far.position.z = -torso_depth - 0.04
			far.modulate = Color(0.65, 0.69, 0.74)
			far_leg_root.add_child(far)
	_apply_thickness()

func _apply_thickness() -> void:
	if thickness_root == null:
		return
	thickness_root.visible = thickness_enabled
	far_leg_root.visible = thickness_enabled
	# 厚度体不再 billboard；整个图组保持统一关节点和左右镜像。
	if thickness_enabled:
		visual.rotation = Vector3.ZERO
		visual.scale.y = cos(deg_to_rad(camera_elevation))
	else:
		visual.scale.y = 1.0
	torso_sprite.position.z = 0.008 if thickness_enabled else 0.0
	torso_restore.position.z = torso_sprite.position.z

func _process(delta: float) -> void:
	super._process(delta)
	_apply_thickness()
	# 基类只切换补绘平面；厚度体可见性单独控制。
	$HUD/Info.text += "\nF7 平面/浅厚度对比 | 当前：%s | 轮廓顶点 %d | 仅静态体积小样" % ["浅厚度" if thickness_enabled else "平面", contour_vertices]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7:
		thickness_enabled = not thickness_enabled
		return
	super._unhandled_key_input(event)
