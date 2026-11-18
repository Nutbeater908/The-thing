## 静态装配 → Sprite3D；不解析资源文本、不访问存档、不接旧步态。
extends Node3D

const METRES_PER_PIXEL := 0.01
var entries: Array[Dictionary] = []
var pixel_bounds := Rect2()
var can_walk := false
var restore_materials: Array[ShaderMaterial] = []

static func snapshot(source: Assembly) -> Assembly:
	var out := Assembly.new()
	for original in source.parts:
		var part := Assembly.Part.new()
		part.data = original.data
		part.position = original.position
		part.rotation = original.rotation
		part.parent = original.parent
		part.parent_socket = original.parent_socket
		part.hp = original.hp
		part.tool = original.tool
		out.parts.append(part)
	return out

func prepare(assembly: Assembly) -> void:
	entries.clear()
	can_walk = false
	var root := assembly.root_index()
	if root < 0:
		return
	var root_pos: Vector2 = assembly.parts[root].position
	for index in assembly.parts.size():
		var part := assembly.parts[index]
		var d: PartData = part.data
		var origin: Vector2 = part.position - root_pos
		var rotation := part.rotation
		if d.category == PartData.Category.LOCOMOTION and rotation == 0:
			can_walk = true
		if d.segment_textures.size() >= 3 and _has_leg_pivots(d):
			var knee := d.socket(&"pivot_knee_u").offset - d.socket(&"pivot_knee_l").offset
			var ankle := knee + d.socket(&"pivot_ankle_s").offset - d.socket(&"pivot_ankle_f").offset
			var offsets := [Vector2.ZERO, knee, ankle]
			for i in 3:
				_add(index, d.segment_textures[i], origin, offsets[i], rotation, d.color, d.size)
		else:
			_add(index, d.texture, origin, d.texture_offset, rotation, d.color, d.size)
		if part.tool != null:
			var mount: SocketData = null
			for socket in d.sockets:
				if socket.kind == SocketData.Kind.TOOL:
					mount = socket
					break
			if mount != null:
				_add(index, part.tool.texture, origin, mount.offset + part.tool.texture_offset, rotation, part.tool.color, part.tool.size)
	var first := true
	for entry in entries:
		var transform: Transform2D = entry.transform
		var dimensions: Vector2 = entry.size
		for corner in [Vector2.ZERO, Vector2(dimensions.x, 0), dimensions, Vector2(0, dimensions.y)]:
			var point: Vector2 = transform * corner
			if first:
				pixel_bounds = Rect2(point, Vector2.ZERO)
				first = false
			else:
				pixel_bounds = pixel_bounds.expand(point)

func _has_leg_pivots(d: PartData) -> bool:
	for uid in [&"pivot_knee_u", &"pivot_knee_l", &"pivot_ankle_s", &"pivot_ankle_f"]:
		if d.socket(uid) == null:
			return false
	return true

func _add(index: int, texture: Texture2D, origin: Vector2, offset: Vector2, rotation: int, tint: Color, fallback_size: Vector2) -> void:
	var angle := rotation * PI * 0.5
	var transform := Transform2D(angle, origin + offset.rotated(angle))
	entries.append({"part": index, "texture": texture, "transform": transform, "size": texture.get_size() if texture != null else fallback_size, "color": tint})

func build() -> void:
	var reference := Vector2(pixel_bounds.get_center().x, pixel_bounds.end.y)
	for i in entries.size():
		var entry := entries[i]
		var transform: Transform2D = entry.transform
		var center: Vector2 = transform * (entry.size * 0.5) - reference
		var texture: Texture2D = entry.texture
		if texture == null:
			# 无素材件用颜色占位，尺寸仍来自部件定义。
			var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
			image.fill(entry.color)
			texture = ImageTexture.create_from_image(image)
		var anchor := Node3D.new()
		anchor.name = "Part%dPiece%d" % [entry.part, i]
		anchor.position = Vector3(center.x, -center.y, 0) * METRES_PER_PIXEL
		anchor.rotation.z = -transform.get_rotation()
		add_child(anchor)
		var sprite := Sprite3D.new()
		sprite.texture = texture
		sprite.pixel_size = METRES_PER_PIXEL
		sprite.scale = Vector3(entry.size.x / texture.get_width(), entry.size.y / texture.get_height(), 1)
		sprite.shaded = false
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		anchor.add_child(sprite)
		var plane := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = entry.size * METRES_PER_PIXEL
		plane.mesh = quad
		var material := ShaderMaterial.new()
		material.shader = load("res://scripts/prototypes/depth_restore.gdshader")
		material.set_shader_parameter("sprite_texture", texture)
		material.render_priority = mini(100, 10 + i)
		plane.material_override = material
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		anchor.add_child(plane)
		restore_materials.append(material)
