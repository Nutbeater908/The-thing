## 拼装视图：自由坐标 + 可选参考线 + 网格吸附。规则全在 Assembly / Rules 里。
class_name AssemblyView
extends Control

const GRID := 16.0            ## 参考线间距（世界像素）
const SNAP_DISTANCE := 24.0   ## 接口吸附半径（世界像素）
const MIN_ZOOM := 0.4
const MAX_ZOOM := 3.0
const DISC_PATH := "res://art/tiles/joint_disc.png"

static var _disc_tex: Texture2D
static var _disc_loaded := false

var assembly := Assembly.new()
var journal := Journal.new()

var held: PartData = null
var held_tool: PartData = null
var held_rotation := 0
var moving := {}
var held_anchor := Vector2.ZERO   ## 手持时插头所在的世界位置

var pan := Vector2(600, 400)
var zoom := 1.0
var show_grid := true
var snap_grid := true
var snap := {}
var _panning := false

signal notice(text: String)

var _menu: PopupMenu
var _menu_target := {}
var _menu_parts: Array = []


func _ready() -> void:
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu_pick)
	add_child(_menu)
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	journal.reset(Blueprint.to_dict(assembly))


# ---------------------------------------------------------------- 坐标

func screen_to_world(pos: Vector2) -> Vector2:
	return (pos - pan) / zoom


func world_to_screen(p: Vector2) -> Vector2:
	return p * zoom + pan


func snap_to_grid(v: Vector2) -> Vector2:
	if not snap_grid:
		return v
	return Vector2(roundf(v.x / GRID) * GRID, roundf(v.y / GRID) * GRID)


# ---------------------------------------------------------------- 输入

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _panning:
			pan += event.relative
		_update_held(event.position)
		queue_redraw()
		return

	if event is InputEventMouseButton and event.pressed and event.ctrl_pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var before := screen_to_world(event.position)
		zoom = clampf(zoom * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), MIN_ZOOM, MAX_ZOOM)
		pan = event.position - before * zoom
		queue_redraw()
		return

	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and held != null:
		held_rotation = (held_rotation + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 3)) % 4
		_update_held(event.position)
		queue_redraw()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		return

	if event is InputEventMouseButton and not event.pressed:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_on_left(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_right(event)


func _on_left(mouse: Vector2) -> void:
	if held == null and held_tool != null:
		var idx := _part_at(screen_to_world(mouse))
		if idx >= 0 and _has_tool_socket(idx):
			assembly.bind_tool(idx, held_tool)
			_record("装上 %s" % held_tool.display_name)
			held_tool = null
			queue_redraw()
		return

	if held != null:
		if held.is_root:
			if assembly.root_index() >= 0:
				notice.emit("机身已经有一个了")
				return
			var pos := snap_to_grid(screen_to_world(mouse) - held.size * 0.5)
			if assembly.add_root(held, pos):
				_record("安装 %s" % held.display_name)
				held = null
			queue_redraw()
			return
		if assembly.root_index() < 0:
			notice.emit("先放机身")
			return
		if snap.is_empty():
			notice.emit("这里没有可接的接口")
			return
		if moving.is_empty():
			if assembly.attach(held, snap["parent"], snap["socket"], held_rotation):
				_record("安装 %s" % held.display_name)
				held = null
		else:
			_place_subtree(snap)
		queue_redraw()
		return

	var world := screen_to_world(mouse)
	var sock := _socket_near(world)
	if sock != null:
		_open_socket_menu(sock)
		return
	var idx := _part_at(world)
	if idx >= 0:
		_pick_up(idx)


func _on_right(event: InputEventMouseButton) -> void:
	if held != null:
		held = null
		moving = {}
		notice.emit("取消")
		queue_redraw()
		return
	var idx := _part_at(screen_to_world(event.position))
	if idx < 0:
		return
	var p := assembly.parts[idx]
	if event.shift_pressed:
		if assembly.remove(idx).size() > 0:
			_record("拆下 %s" % p.data.display_name)
	else:
		if assembly.remove(idx).size() > 0:
			_record("拆除 %s" % p.data.display_name)
	queue_redraw()


func _update_held(mouse: Vector2) -> void:
	snap = {}
	if held == null:
		return
	var raw := screen_to_world(mouse)
	if held.is_root:
		# 根部件：跟随鼠标，按网格吸附后以中心对齐
		held_anchor = snap_to_grid(raw - held.size * 0.5)
		return
	var off: Vector2 = held.anchor.offset if held.anchor != null else Vector2.ZERO
	held_anchor = snap_to_grid(raw - off)
	snap = assembly.find_snap(held, held_rotation, raw, SNAP_DISTANCE)
	if not snap.is_empty():
		# snap["position"] 已经是部件左上角，不能再加一次锚点偏移
		held_anchor = snap["position"]


# ---------------------------------------------------------------- 拎起 / 放下

## 光标附近的空接口
func _socket_near(world: Vector2) -> Dictionary:
	var best := {}
	var best_d := 14.0
	for i in assembly.parts.size():
		for soc in assembly.parts[i].data.sockets:
			if assembly.is_socket_used(i, soc.uid):
				continue
			var pos := assembly.socket_position(i, soc.uid)
			var d := pos.distance_to(world)
			if d < best_d:
				best_d = d
				best = {"part": i, "socket": soc.uid, "kind": soc.kind}
	return best


## 点击空槽位：列出能装的部件
func _open_socket_menu(sock: Dictionary) -> void:
	_menu_target = sock
	_menu_parts.clear()
	_menu.clear()
	var target_dir: Vector2i = SocketData.opposite(
		SocketData.rotate_dir(assembly.parts[sock["part"]].data.socket(sock["socket"]).dir,
			assembly.parts[sock["part"]].rotation))
	for part in PartsLibrary.all():
		if part.anchor == null or part.anchor.kind != sock["kind"] or part.is_root:
			continue
		# 方向必须对得上（菜单里统一按 0 度插入）
		if SocketData.rotate_dir(part.anchor.dir, 0) != target_dir:
			continue
		_menu_parts.append(part)
		_menu.add_item("%s  %d" % [part.display_name, part.cost])
	if _menu_parts.is_empty():
		notice.emit("没有可装的部件")
		return
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.popup()


func _on_menu_pick(id: int) -> void:
	if id < 0 or id >= _menu_parts.size() or _menu_target.is_empty():
		return
	var part: PartData = _menu_parts[id]
	if assembly.attach(part, _menu_target["part"], _menu_target["socket"], 0):
		_record("安装 %s" % part.display_name)
	else:
		notice.emit("装不上：方向不匹配")
	queue_redraw()


func _pick_up(index: int) -> void:
	var subtree := _capture(index)
	assembly.remove(index)
	moving = subtree
	held = subtree["parts"][0]["data"]
	held_rotation = subtree["parts"][0]["rot"]
	_record("拎起 %s" % held.display_name)
	queue_redraw()


func _capture(index: int) -> Dictionary:
	var order: Array[int] = [index]
	var list: Array = []
	var queue: Array[int] = [index]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		var p := assembly.parts[cur]
		var local_parent := order.find(p.parent)
		list.append({
			"data": p.data, "rot": p.rotation, "hp": p.hp,
			"parent": local_parent, "socket": p.parent_socket, "tool": p.tool,
			"offset": p.position - assembly.parts[index].position,
		})
		for c in assembly.children(cur):
			order.append(c)
			queue.append(c)
	return {"parts": list}


func _place_subtree(target: Dictionary) -> void:
	var base := assembly.parts.size()
	var list: Array = moving["parts"]
	if not assembly.attach(list[0]["data"], target["parent"], target["socket"], list[0]["rot"]):
		return
	for i in range(1, list.size()):
		var e: Dictionary = list[i]
		assembly.attach(e["data"], base + e["parent"], e["socket"], e["rot"])
	_record("移动 %s" % list[0]["data"].display_name)
	held = null
	moving = {}


func _has_tool_socket(index: int) -> bool:
	for s in assembly.parts[index].data.sockets:
		if s.kind == SocketData.Kind.TOOL:
			return true
	return false


func _part_at(world: Vector2) -> int:
	for i in range(assembly.parts.size() - 1, -1, -1):
		if assembly.rect_of(i).has_point(world):
			return i
	return -1


# ---------------------------------------------------------------- 日志

func _record(label: String) -> void:
	journal.record(label, Blueprint.to_dict(assembly))
	notice.emit(label)


func undo() -> void:
	if journal.can_undo():
		_restore(journal.undo(Blueprint.to_dict(assembly)))


func redo() -> void:
	if journal.can_redo():
		_restore(journal.redo())


func jump_to(step: int) -> void:
	_restore(journal.jump(step))


func _restore(snapshot: Dictionary) -> void:
	assembly = Blueprint.from_dict(snapshot, PartsLibrary.catalog()) if not snapshot.is_empty() else Assembly.new()
	held = null
	moving = {}
	queue_redraw()


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if show_grid:
		_draw_grid()
	_draw_parts()
	_draw_sockets()
	_draw_held()


func _draw_grid() -> void:
	var step := GRID * zoom
	if step < 6.0:
		return
	var col := Color(0.15, 0.16, 0.19)
	var major := Color(0.22, 0.23, 0.27)
	var x := fposmod(pan.x, step * 4.0)
	var i := 0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), major if i % 4 == 0 else col)
		x += step
		i += 1
	var y := fposmod(pan.y, step * 4.0)
	i = 0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), major if i % 4 == 0 else col)
		y += step
		i += 1


func _draw_parts() -> void:
	for i in assembly.parts.size():
		var p := assembly.parts[i]
		var r := Rect2(world_to_screen(p.position), p.data.size * zoom)
		if held != null:
			draw_rect(r, Color(1, 0.4, 0.4, 0.8), false, 1.0)
		# 多段部件（腿/臂）：按枢轴把各段接起来画
		if _draw_segments(p, r):
			continue
		if p.data.texture != null:
			var tr := Rect2(world_to_screen(p.position + p.data.texture_offset), p.data.texture.get_size() * zoom)
			draw_texture_rect(p.data.texture, tr, false)
		else:
			draw_rect(r, p.data.color)
			draw_rect(r, Color(0, 0, 0, 0.7), false, 1.5)


## 把多段贴图按枢轴接起来画，返回 true 表示已处理
func _draw_segments(p, _r: Rect2) -> bool:
	var d = p.data
	if d.segment_textures.size() < 2:
		return false
	
	var spec := LegGeometry.from_part(d)
	if spec.total_length <= 0.0:
		return false
	
	# 髋和踝的世界坐标（拼装盘上，假设腿垂直向下）
	var hip_world: Vector2 = p.position
	if d.anchor != null:
		hip_world += d.anchor.offset
	var ankle_world: Vector2 = hip_world + Vector2(0.0, spec.total_length)
	
	# 计算三段变换
	var transforms := LegGeometry.compute_transforms(spec, hip_world, ankle_world)
	
	for i in mini(d.segment_textures.size(), transforms.size()):
		var tex: Texture2D = d.segment_textures[i]
		if tex == null:
			continue
		var t: Dictionary = transforms[i]
		var offset := Vector2.ZERO
		if i == 0:
			offset = -spec.hip
		elif i == 1:
			offset = -spec.knee_lower
		elif i == 2:
			offset = -spec.ankle_foot
		var pos: Vector2 = world_to_screen(t["position"] + offset)
		draw_texture_rect(tex, Rect2(pos, tex.get_size() * zoom), false)
	return true


func _draw_sockets() -> void:
	var tex := _disc()
	for i in assembly.parts.size():
		for s in assembly.parts[i].data.sockets:
			var pos := world_to_screen(assembly.socket_position(i, s.uid))
			var radius := 9.0 * zoom
			var used := assembly.is_socket_used(i, s.uid)
			var lit: bool = not snap.is_empty() and snap.get("parent", -1) == i and snap.get("socket", &"") == s.uid
			var tint := Color(0.55, 0.58, 0.62)
			if used:
				tint = Color(0.3, 0.32, 0.36)
			if lit:
				tint = Color(1.0, 0.85, 0.35)
			# 只有面朝观察者（DEPTH）的接口才画完整圆；侧对着的只点一个小标记
			if s.axis != SocketData.Axis.DEPTH:
				continue
			# 十字准星 + 空心圆：圆心就是接口位置，便于肉眼对位
			draw_line(pos - Vector2(radius, 0), pos + Vector2(radius, 0), tint, 1.0)
			draw_line(pos - Vector2(0, radius), pos + Vector2(0, radius), tint, 1.0)
			draw_circle(pos, radius * 0.6, tint, false, 1.5)


func _draw_held() -> void:
	if held == null:
		return
	var r := Rect2(world_to_screen(held_anchor), held.size * zoom)
	if held.segment_textures.size() >= 2:
		var spec := LegGeometry.from_part(held)
		if spec.total_length > 0.0:
			var hip_world: Vector2 = held_anchor
			if held.anchor != null:
				hip_world += held.anchor.offset
			var ankle_world: Vector2 = hip_world + Vector2(0.0, spec.total_length)
			var transforms := LegGeometry.compute_transforms(spec, hip_world, ankle_world)
			for i in mini(held.segment_textures.size(), transforms.size()):
				var tex: Texture2D = held.segment_textures[i]
				if tex == null:
					continue
				var t: Dictionary = transforms[i]
				var offset := Vector2.ZERO
				if i == 0:
					offset = -spec.hip
				elif i == 1:
					offset = -spec.knee_lower
				elif i == 2:
					offset = -spec.ankle_foot
				var pos: Vector2 = world_to_screen(t["position"] + offset)
				draw_texture_rect(tex, Rect2(pos, tex.get_size() * zoom), false, Color(1, 1, 1, 0.65))
			return
	if held.texture != null:
		var tr := Rect2(world_to_screen(held_anchor + held.texture_offset), held.texture.get_size() * zoom)
		draw_texture_rect(held.texture, tr, false, Color(1, 1, 1, 0.65))
	else:
		draw_rect(r, Color(held.color, 0.55))
	draw_rect(r, Color(1, 0.4, 0.4, 0.9), false, 1.0)


static func _disc() -> Texture2D:
	if not _disc_loaded:
		_disc_loaded = true
		if ResourceLoader.exists(DISC_PATH):
			_disc_tex = load(DISC_PATH) as Texture2D
	return _disc_tex
