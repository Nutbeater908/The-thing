## 拼装盘：异形多格器官的摆放、旋转、移除与拉线。
##
## 器官用一组绝对格坐标占位；放置前检查全部格子是否在界内且为空。
## 连线由独立的 LinkLayer 子节点绘制，保证线在器官之上。
## 存活校验在下一步接入；器官外观由 OrganTile 负责。
class_name AssemblyGrid
extends Control

signal layout_changed
signal validation_changed(result: Dictionary)
signal notice(text: String)
signal organ_placed(organ: OrganData)

const LinkLayerScript := preload("res://scripts/build/link_layer.gd")

const COLS := 9
const ROWS := 7
const CELL_MIN := 34.0
const CELL_MAX := 84.0
const GRID_PAD := 16.0
const PORT_HIT_RADIUS := 14.0

const C_GRID := Color(0.16, 0.15, 0.18)
const C_GRID_LINE := Color(0.28, 0.26, 0.32)
const C_HOVER_OK := Color(0.45, 0.85, 0.55, 0.10)
const C_HOVER_BAD := Color(0.90, 0.30, 0.30, 0.12)


## 盘面上的一个器官实例
class Placed:
	var data: OrganData
	var rotation: int
	var anchor: Vector2i
	var cells: Array[Vector2i]
	var node: OrganTile
	var hp := 0.0


## 拉线的一端：某个器官上的某个接点
class Endpoint:
	var organ: Placed
	var port_uid: StringName
	var type: int


## 两个同类接点之间的连接
class LinkData:
	var a: Endpoint
	var b: Endpoint
	var type: int


var _placed: Dictionary = {}      # Vector2i -> Placed
var _order: Array = []            # 放置顺序，决定绘制层级
var _hover := Vector2i(-1, -1)
var _selected: OrganData = null   # 库存中选中、等待放置的器官
var _pending_rotation := 0
var _result: Dictionary = {}

var _links: Array[LinkData] = []
var drag_from: Endpoint = null    # 正在拖拽的起点
var drag_pos := Vector2.ZERO
var _link_layer: Control

var stats: CreatureStats         # 每次改动后重新推导
var show_physics := false        # 「物理预览」开关
var repair_mode := false         # 「修复工具」开关
var economy                      # 可选：提供 spend() / earn() 的代币系统

var _repair_hint := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_relayout)

	_link_layer = LinkLayerScript.new()
	_link_layer.grid = self
	_link_layer.z_index = 10
	add_child(_link_layer)

	_revalidate()


# ---------------------------------------------------------------- 对外接口

func set_selected(data: OrganData) -> void:
	_selected = data
	_pending_rotation = 0
	_refresh()


func set_physics_preview(on: bool) -> void:
	show_physics = on
	_refresh()


func set_repair_mode(on: bool) -> void:
	repair_mode = on
	_repair_hint = Vector2i(-1, -1)
	_refresh()


## 修复一格上的器官；返回是否成功
func repair_at(cell: Vector2i) -> bool:
	var p: Placed = _placed.get(cell)
	if p == null or p.hp >= p.data.max_hp:
		return false

	var cost := OrganData.repair_cost(p.data, p.hp)
	if economy != null and not economy.spend(cost):
		notice.emit("代币不足 — 修复需要 %d" % cost)
		return false

	p.hp = p.data.max_hp
	layout_changed.emit()
	notice.emit("修复 %s，花费 %d" % [p.data.display_name, cost])
	_revalidate()
	return true


## 一次修满全部器官
func repair_all() -> bool:
	var total := 0
	for p in _order:
		total += OrganData.repair_cost(p.data, p.hp)

	if total <= 0:
		notice.emit("没有需要修复的器官")
		return false

	if economy != null and not economy.spend(total):
		notice.emit("代币不足 — 全部修复需要 %d" % total)
		return false

	for p in _order:
		p.hp = p.data.max_hp
	layout_changed.emit()
	notice.emit("全部修复，花费 %d" % total)
	_revalidate()
	return true


## 当前全部修复需要多少代币
func repair_all_cost() -> int:
	var total := 0
	for p in _order:
		total += OrganData.repair_cost(p.data, p.hp)
	return total


func selected() -> OrganData:
	return _selected


func organ_count() -> int:
	return _order.size()


func organs() -> Array:
	return _order.duplicate()


## 格子上的器官实例；空格返回 null
func organ_at(cell: Vector2i):
	return _placed.get(cell)


## 把当前所有拉线导出成可序列化的快照
func link_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for link in _links:
		out.append({
			"a": _endpoint_snapshot(link.a),
			"b": _endpoint_snapshot(link.b),
			"type": link.type,
		})
	return out


func _endpoint_snapshot(ep: Endpoint) -> Dictionary:
	return {
		"id": ep.organ.data.id,
		"anchor": ep.organ.anchor,
		"rotation": ep.organ.rotation,
		"uid": ep.port_uid,
	}


## 从快照恢复拉线；器官必须已经恢复到位
func restore_links(snapshot: Array) -> void:
	for entry in snapshot:
		var a := _find_endpoint(entry["a"])
		var b := _find_endpoint(entry["b"])
		if a != null and b != null:
			_try_link(a, b)


func _find_endpoint(data: Dictionary) -> Endpoint:
	var p: Placed = _placed.get(data["anchor"])
	if p == null:
		return null
	if p.data.id != data["id"] or p.rotation != data["rotation"]:
		return null

	var ep := Endpoint.new()
	ep.organ = p
	ep.port_uid = data["uid"]
	ep.type = _port_type(p, ep.port_uid)
	return ep


func _port_type(p: Placed, uid: StringName) -> int:
	for port in p.data.rotated_ports(p.rotation):
		if port.uid == uid:
			return port.type
	return 0


func links() -> Array[LinkData]:
	return _links


func result() -> Dictionary:
	return _result


func clear_all() -> void:
	for p in _order:
		p.node.queue_free()
	_placed.clear()
	_order.clear()
	_links.clear()
	drag_from = null
	_selected = null
	layout_changed.emit()
	_revalidate()


# ---------------------------------------------------------------- 编辑操作

func _can_place(anchor: Vector2i, data: OrganData, rotation: int, ignore: Placed = null) -> bool:
	for c in data.rotated_cells(rotation):
		var ac: Vector2i = anchor + c
		if not _in_bounds(ac):
			return false
		var other: Placed = _placed.get(ac)
		if other != null and other != ignore:
			return false
	return true


func place(anchor: Vector2i, data: OrganData, rotation: int = 0, free := false) -> bool:
	if not _can_place(anchor, data, rotation):
		return false

	if not free and economy != null and not economy.spend(data.cost):
		notice.emit("代币不足 — 需要 %d" % data.cost)
		return false

	var p := Placed.new()
	p.data = data
	p.rotation = rotation
	p.anchor = anchor
	p.cells = _abs_cells(anchor, data, rotation)
	p.hp = data.max_hp

	var tile := OrganTile.new()
	add_child(tile)
	tile.setup(data, rotation, cell_size())
	_reposition(p, tile)
	p.node = tile

	for c in p.cells:
		_placed[c] = p
	_order.append(p)

	layout_changed.emit()
	organ_placed.emit(data)
	_revalidate()
	return true


func remove_at(cell: Vector2i) -> bool:
	var p: Placed = _placed.get(cell)
	if p == null:
		return false

	if economy != null:
		economy.earn(OrganData.refund_value(p.data, p.hp))

	_erase(p)
	layout_changed.emit()
	_revalidate()
	return true


func rotate_at(cell: Vector2i) -> bool:
	var p: Placed = _placed.get(cell)
	if p == null:
		return false
	var new_rotation := (p.rotation + 1) % 4
	if not _can_place(p.anchor, p.data, new_rotation, p):
		return false

	_erase_cells(p)
	p.rotation = new_rotation
	p.cells = _abs_cells(p.anchor, p.data, new_rotation)
	_write_cells(p)
	p.node.setup(p.data, new_rotation, cell_size())
	_reposition(p, p.node)

	layout_changed.emit()
	_revalidate()
	return true


## 旋转待放置的器官（空格上右键 / 滚轮）
func rotate_pending() -> void:
	if _selected == null:
		return
	_pending_rotation = (_pending_rotation + 1) % 4
	_refresh()


# ---------------------------------------------------------------- 内部工具

func _abs_cells(anchor: Vector2i, data: OrganData, rotation: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in data.rotated_cells(rotation):
		out.append(anchor + c)
	return out


func _erase_cells(p: Placed) -> void:
	for c in p.cells:
		_placed.erase(c)


func _write_cells(p: Placed) -> void:
	for c in p.cells:
		_placed[c] = p


func _erase(p: Placed) -> void:
	_erase_cells(p)
	_order.erase(p)
	_drop_links_of(p)
	p.node.queue_free()


func _reposition(p: Placed, tile: OrganTile) -> void:
	var bb := p.data.bounds(p.rotation)
	tile.position = _grid_origin() + Vector2(p.anchor + bb.position) * cell_size()


## 窗口尺寸变化时重排所有器官
func _relayout() -> void:
	for p in _order:
		p.node.setup(p.data, p.rotation, cell_size())
		_reposition(p, p.node)
	_refresh()


## 修复工具开启时，鼠标移到受损器官上显示花费
func _update_repair_hint() -> void:
	if not _in_bounds(_hover) or _hover == _repair_hint:
		return
	_repair_hint = _hover

	var p: Placed = _placed.get(_hover)
	if p == null or p.hp >= p.data.max_hp:
		return
	notice.emit("修复 %s：%d 代币" % [p.data.display_name, OrganData.repair_cost(p.data, p.hp)])


## 重绘网格/预览和拉线层
func _refresh() -> void:
	queue_redraw()
	if _link_layer != null:
		_link_layer.queue_redraw()


# ---------------------------------------------------------------- 校验

func _revalidate() -> void:
	stats = CreatureStats.from_grid(self)
	_result = _validate()
	validation_changed.emit(_result)
	_refresh()


func _validate() -> Dictionary:
	if _order.is_empty():
		return {
			"alive": false,
			"checks": [],
			"message": "拼装盘是空的 — 从左侧选一个器官放上来",
		}

	var checks: Array[Dictionary] = [
		_check_control(),
		_check_blood(),
		_check_structure(),
	]

	var failed: Array[String] = []
	for c in checks:
		if not c.ok:
			failed.append(c.label)

	var message := "构造存活 — 可以出发" if failed.is_empty() else "无法维持生命：" + "、".join(failed)
	return {"alive": failed.is_empty(), "checks": checks, "message": message}


## 控制链：寄生虫 → 大脑 → 所有需要神经的器官
func _check_control() -> Dictionary:
	var parasite: Placed = null
	var brain: Placed = null
	for p in _order:
		if p.data.is_parasite:
			parasite = p
		if p.data.is_brain:
			brain = p

	if parasite == null:
		return _check_fail("control", "控制链", "缺少寄生虫")
	if brain == null:
		return _check_fail("control", "控制链", "缺少大脑")

	var adj := _adjacency(OrganData.NERVE)
	if not _reachable(adj, [parasite]).has(brain):
		return _check_fail("control", "控制链", "寄生虫没有连到大脑")

	var from_brain := _reachable(adj, [brain])
	var missing := _names_unreachable(from_brain, true)
	if not missing.is_empty():
		return _check_fail("control", "控制链", "%s 没有神经连接" % ", ".join(missing))

	return _check_ok("control", "控制链", "寄生虫 → 大脑 → 全部肢体")


## 血路：心脏 → 所有耗血器官，且供血量足够
func _check_blood() -> Dictionary:
	var heart: Placed = null
	for p in _order:
		if p.data.is_heart:
			heart = p
	if heart == null:
		return _check_fail("blood", "血路", "缺少心脏")

	var adj := _adjacency(OrganData.BLOOD)
	var reach := _reachable(adj, [heart])

	var missing := _names_unreachable(reach, false)
	if not missing.is_empty():
		return _check_fail("blood", "血路", "%s 没有接入血流" % ", ".join(missing))

	var supply := 0.0
	var demand := 0.0
	for p in _order:
		if p.data.blood_rate < 0.0:
			supply += -p.data.blood_rate
		else:
			demand += p.data.blood_rate

	if demand > supply:
		return _check_fail("blood", "血路", "供血不足：需要 %.1f，心脏只能提供 %.1f" % [demand, supply])

	return _check_ok("blood", "血路", "供血 %.1f / 需求 %.1f" % [supply, demand])


## 结构：贴邻 + 骨骼线，要求全部器官连成一体
func _check_structure() -> Dictionary:
	var adj := _adjacency(OrganData.BONE)

	# 格子直接相邻也算物理连接
	for i in _order.size():
		for j in range(i + 1, _order.size()):
			var a: Placed = _order[i]
			var b: Placed = _order[j]
			if _touching(a, b):
				adj[a].append(b)
				adj[b].append(a)

	var reach := _reachable(adj, [_order[0]])
	var missing: Array[String] = []
	for p in _order:
		if not reach.has(p):
			missing.append(p.data.display_name)
	if not missing.is_empty():
		return _check_fail("structure", "结构", "%s 悬空" % ", ".join(missing))

	return _check_ok("structure", "结构", "全部器官连成一体")


# ---------------------------------------------------------------- 校验工具

## 按链路类型构建器官邻接表
func _adjacency(link_type: int) -> Dictionary:
	var adj := {}
	for p in _order:
		adj[p] = []
	for link in _links:
		if link.type != link_type or link.a.organ == link.b.organ:
			continue
		adj[link.a.organ].append(link.b.organ)
		adj[link.b.organ].append(link.a.organ)
	return adj


## 从若干起点出发能到达的器官集合
func _reachable(adj: Dictionary, starts: Array) -> Dictionary:
	var seen := {}
	var queue := []
	for s in starts:
		seen[s] = true
		queue.append(s)

	while not queue.is_empty():
		var cur = queue.pop_front()
		for nxt in adj.get(cur, []):
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	return seen


## 找出没被连接到的器官名称；nerve=true 时只看需要神经的器官
func _names_unreachable(reach: Dictionary, nerve_only: bool) -> Array[String]:
	var out: Array[String] = []
	for p in _order:
		if p.data.is_heart or p.data.is_parasite:
			continue
		if nerve_only and not p.data.needs_nerve:
			continue
		if not nerve_only and p.data.blood_rate <= 0.0:
			continue
		if not reach.has(p):
			out.append(p.data.display_name)
	return out


## 两个器官是否有格子上下左右紧贴
func _touching(a: Placed, b: Placed) -> bool:
	for ca in a.cells:
		for cb in b.cells:
			if absi(ca.x - cb.x) + absi(ca.y - cb.y) == 1:
				return true
	return false


func _check_ok(id: String, label: String, detail: String) -> Dictionary:
	return {"id": id, "label": label, "ok": true, "detail": detail}


func _check_fail(id: String, label: String, detail: String) -> Dictionary:
	return {"id": id, "label": label, "ok": false, "detail": detail}


# ---------------------------------------------------------------- 坐标换算

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < COLS and cell.y < ROWS


func cell_size() -> float:
	var avail := size - Vector2(GRID_PAD, GRID_PAD) * 2.0
	return clampf(minf(avail.x / COLS, avail.y / ROWS), CELL_MIN, CELL_MAX)


func _grid_origin() -> Vector2:
	var cs := cell_size()
	var w := COLS * cs
	var h := ROWS * cs
	return Vector2(maxf(0.0, (size.x - w) * 0.5), maxf(0.0, (size.y - h) * 0.5))


func _cell_rect(cell: Vector2i) -> Rect2:
	var cs := cell_size()
	return Rect2(_grid_origin() + Vector2(cell) * cs, Vector2(cs, cs))


func _cell_at(pos: Vector2) -> Vector2i:
	var cs := cell_size()
	var local := ((pos - _grid_origin()) / cs).floor()
	var cell := Vector2i(local)
	return cell if _in_bounds(cell) else Vector2i(-1, -1)


# ---------------------------------------------------------------- 输入

func _on_mouse_exited() -> void:
	_hover = Vector2i(-1, -1)
	drag_from = null
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _cell_at(event.position)
		if drag_from != null:
			drag_pos = event.position
		if repair_mode:
			_update_repair_hint()
		_refresh()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		rotate_pending()
		return

	if not (event is InputEventMouseButton):
		return

	# 松开左键：结束拉线
	if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if drag_from != null:
			var target := endpoint_at(event.position)
			if target != null:
				_try_link(drag_from, target)
			drag_from = null
			_refresh()
		return

	if not event.pressed:
		return

	var cell := _cell_at(event.position)
	if cell.x < 0:
		return

	_hover = cell

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if repair_mode:
				repair_at(cell)
				return
			# 按住接点 = 开始拉线；点空格 = 放置器官
			var ep := endpoint_at(event.position)
			if ep != null:
				drag_from = ep
				drag_pos = event.position
				_selected = null   # 拉线时退出手持器官状态
				_refresh()
				return
			if _selected != null and not _placed.has(cell):
				place(cell, _selected, _pending_rotation)
		MOUSE_BUTTON_RIGHT:
			if _placed.has(cell):
				rotate_at(cell)
			else:
				rotate_pending()
		MOUSE_BUTTON_MIDDLE:
			remove_at(cell)


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var cs := cell_size()
	var origin := _grid_origin()
	var full := Rect2(origin, Vector2(COLS, ROWS) * cs)

	draw_rect(full, C_GRID)
	for i in COLS + 1:
		var x := origin.x + i * cs
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + ROWS * cs), C_GRID_LINE, 1.0)
	for j in ROWS + 1:
		var y := origin.y + j * cs
		draw_line(Vector2(origin.x, y), Vector2(origin.x + COLS * cs, y), C_GRID_LINE, 1.0)

	if not _in_bounds(_hover):
		return

	# 悬停高亮
	if _placed.has(_hover):
		draw_rect(_cell_rect(_hover), C_HOVER_BAD)
	elif _selected != null:
		_draw_preview(_hover)


## 待放置器官的预览：形状 + 接点
func _draw_preview(anchor: Vector2i) -> void:
	var ok := _can_place(anchor, _selected, _pending_rotation)
	var cs := cell_size()
	var bb := _selected.bounds(_pending_rotation)
	var shift := _grid_origin() + Vector2(anchor + bb.position) * cs
	var alpha := 0.45 if ok else 0.20

	for c in _selected.rotated_cells(_pending_rotation):
		var ac: Vector2i = anchor + c
		if not _in_bounds(ac):
			continue
		var r := Rect2(shift + Vector2(c - bb.position) * cs, Vector2(cs, cs)).grow(-2.0)
		draw_rect(r, Color(_selected.color, alpha))
		draw_rect(r, Color(0, 0, 0, 0.4), false, 1.5)

	for port in _selected.rotated_ports(_pending_rotation):
		var center := shift + (Vector2(port.cell - bb.position) + Vector2(0.5, 0.5)) * cs
		draw_circle(center, 4.0, Color(port_color(port.type), 0.75))


func port_color(type: int) -> Color:
	match type:
		OrganData.NERVE:
			return Color(0.35, 0.85, 0.95)
		OrganData.BLOOD:
			return Color(0.92, 0.26, 0.32)
		_:
			return Color(0.88, 0.86, 0.78)


# ---------------------------------------------------------------- 拉线

## 鼠标位置附近最近的接点；找不到返回 null
func endpoint_at(pos: Vector2) -> Endpoint:
	var best: Endpoint = null
	var best_dist := PORT_HIT_RADIUS
	for p in _order:
		for port in p.data.rotated_ports(p.rotation):
			var center: Vector2 = p.node.position + p.node.port_center(port.uid)
			var d := center.distance_to(pos)
			if d <= best_dist:
				best_dist = d
				var ep := Endpoint.new()
				ep.organ = p
				ep.port_uid = port.uid
				ep.type = port.type
				best = ep
	return best


func endpoint_pos(ep: Endpoint) -> Vector2:
	return ep.organ.node.position + ep.organ.node.port_center(ep.port_uid)


func _same_endpoint(a: Endpoint, b: Endpoint) -> bool:
	return a.organ == b.organ and a.port_uid == b.port_uid


func is_valid_target(from: Endpoint, to: Endpoint) -> bool:
	return from.organ != to.organ and from.type == to.type


func _try_link(from: Endpoint, to: Endpoint) -> bool:
	if not is_valid_target(from, to):
		return false

	for link in _links:
		if _same_endpoint(link.a, from) and _same_endpoint(link.b, to):
			return false
		if _same_endpoint(link.a, to) and _same_endpoint(link.b, from):
			return false

	var link := LinkData.new()
	link.a = from
	link.b = to
	link.type = from.type
	_links.append(link)

	layout_changed.emit()
	_revalidate()
	return true


## 器官被移除时，删掉所有连在它身上的线
func _drop_links_of(p: Placed) -> void:
	var kept: Array[LinkData] = []
	for link in _links:
		if link.a.organ != p and link.b.organ != p:
			kept.append(link)
	_links = kept
