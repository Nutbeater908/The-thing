## 一次性工具：把初始器官定义写成 .tres 资源。
##
## 运行：
##   godot --headless --path <项目> --script res://tools/generate_organs.gd
##
## 生成后，器官的所有数值和形状都在 resources/organs/*.tres 里，
## 调平衡或加新器官都不需要再改这个脚本。
extends SceneTree

const OUT_DIR := "res://resources/organs"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var N := OrganData.NERVE
	var B := OrganData.BLOOD
	var S := OrganData.BONE

	# 寄生虫 1×1：指令核心
	var parasite := _make(&"parasite", "寄生虫", Color(0.85, 0.55, 0.75),
		[Vector2i(0, 0)],
		[_port(Vector2i(0, 0), N, &"nerve")])
	parasite.is_parasite = true

	# 大脑 1×2：控制中枢
	var brain := _make(&"brain", "大脑", Color(0.78, 0.72, 0.45),
		[Vector2i(0, 0), Vector2i(0, 1)],
		[
			_port(Vector2i(0, 0), N, &"nerve_in"),
			_port(Vector2i(0, 1), N, &"nerve_out"),
			_port(Vector2i(0, 1), B, &"blood"),
			_port(Vector2i(0, 1), S, &"bone"),
		])
	brain.is_brain = true
	brain.needs_blood = true
	brain.blood_rate = 1.0

	# 心脏 1×1：血源
	var heart := _make(&"heart", "心脏", Color(0.80, 0.22, 0.28),
		[Vector2i(0, 0)],
		[_port(Vector2i(0, 0), B, &"blood")])
	heart.is_heart = true
	heart.blood_rate = -10.0

	# 腿 1×3：移动
	var leg := _make(&"leg", "腿", Color(0.42, 0.55, 0.72),
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		[
			_port(Vector2i(0, 0), N, &"nerve"),
			_port(Vector2i(0, 0), B, &"blood"),
			_port(Vector2i(0, 0), S, &"bone"),
		])
	leg.needs_nerve = true
	leg.needs_blood = true
	leg.blood_rate = 2.0

	# 爪 L 形：攻击
	var claw := _make(&"claw", "爪", Color(0.72, 0.48, 0.30),
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[
			_port(Vector2i(0, 0), N, &"nerve"),
			_port(Vector2i(0, 0), B, &"blood"),
			_port(Vector2i(0, 0), S, &"bone"),
		])
	claw.needs_nerve = true
	claw.needs_blood = true
	claw.blood_rate = 3.0

	# 脂肪 2×2：储能
	var fat := _make(&"fat", "脂肪", Color(0.68, 0.62, 0.38),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[
			_port(Vector2i(0, 0), B, &"blood_a"),
			_port(Vector2i(1, 1), B, &"blood_b"),
		])
	fat.blood_rate = 0.5

	for d in [parasite, brain, heart, leg, claw, fat]:
		var path := OUT_DIR.path_join(String(d.id) + ".tres")
		var err := ResourceSaver.save(d, path)
		print("%-8s -> %s [%s]" % [d.id, path, error_string(err)])

	quit()


func _port(cell: Vector2i, type: int, uid: StringName) -> OrganPort:
	return OrganPort.new(cell, type, uid)


func _make(id: StringName, display_name: String, color: Color,
		cells: Array, ports: Array) -> OrganData:
	var d := OrganData.new()
	d.id = id
	d.display_name = display_name
	d.color = color
	d.cells.assign(cells)
	d.ports.assign(ports)
	return d
