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

## 拼装盘是无边界虚拟网格：坐标只受这个防呆上限约束
const GRID_LIMIT := 64
## 缩放档，都是 64×64 贴图的整数倍，任何一档都不糊
const ZOOM_STEPS: Array[float] = [16.0, 32.0, 64.0, 128.0]
## 无边界网格里 -1 也是合法格，必须用一个绝对不可能落到的坐标当"没有悬停"
const NO_CELL := Vector2i(-100000, -100000)
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
	## 绑在工具口上的末端工具（不占格）
	var tool: OrganData = null


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


var _placed: Dictionary = {}      # Vector2i -> Array[Placed]（器官层，允许不同器官重叠）
var _bones: Dictionary = {}       # Vector2i -> Placed（骨骼层，可与器官同格）
var _order: Array = []            # 放置顺序，决定绘制层级
var _hover := NO_CELL
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

var _repair_hint := NO_CELL

## 视图状态：缩放档索引 + 以像素为单位的平移（原点 = 面板中心）
var zoom_index := 2
var pan := Vector2.ZERO
var _panning := false
var _pan_anchor := Vector2.ZERO


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
	_repair_hint = NO_CELL
	_refresh()


## 修复一格上的器官；返回是否成功
func repair_at(cell: Vector2i) -> bool:
	var p: Placed = organ_at(cell)
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


## 格子上的器官实例（优先器官层最上面那个，其次骨骼层）；空格返回 null
func organ_at(cell: Vector2i):
	var p = _top_at(cell)
	if p != null:
		return p
	return _bones.get(cell)


## 格子上的骨骼；没有返回 null
func bone_at(cell: Vector2i):
	return _bones.get(cell)


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
	var p: Placed = null
	for candidate in _order:
		if candidate.anchor == data["anchor"] and candidate.data.id == data["id"] \
				and candidate.rotation == data["rotation"]:
			p = candidate
			break
	if p == null:
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
	_bones.clear()
	_order.clear()
	_links.clear()
	drag_from = null
	_selected = null
	layout_changed.emit()
	_revalidate()


# ---------------------------------------------------------------- 编辑操作

## 骨骼和器官各占一层：同一格可以同时有一根骨和一个器官
func _layer_of(data: OrganData) -> Dictionary:
	return _bones if data.is_bone else _placed


## 某格器官层上最上面那个（最后放置的）
func _top_at(cell: Vector2i):
	var arr: Array = _placed.get(cell, [])
	if arr.is_empty():
		return null
	return arr[arr.size() - 1]


## 某格是否有任何对象（骨或器官）
func _occupied(cell: Vector2i) -> bool:
	return _placed.has(cell) or _bones.has(cell)


func _can_place(anchor: Vector2i, data: OrganData, rotation: int, ignore: Placed = null) -> bool:
	for c in data.rotated_cells(rotation):
		var ac: Vector2i = anchor + c
		if not _in_bounds(ac):
			return false
		if data.is_bone:
			# 骨骼层：同格不能再有别的骨
			var other: Placed = _bones.get(ac)
			if other != null and other != ignore:
				return false
		else:
			# 器官层：允许重叠，但同类器官不能压在一起
			var arr: Array = _placed.get(ac, [])
			for p in arr:
				if p != ignore and p.data.id == data.id:
					return false
	return true


## 下一次放置免收代币（从胃里装回已拥有的器官时用），放置成功后自动清除
var free_next_placement := false


func place(anchor: Vector2i, data: OrganData, rotation: int = 0, free := false) -> bool:
	if not _can_place(anchor, data, rotation):
		return false

	var charge := not free and not free_next_placement
	if charge and economy != null and not economy.spend(data.cost):
		notice.emit("代币不足 — 需要 %d" % data.cost)
		return false
	if not charge:
		free_next_placement = false

	var p := Placed.new()
	p.data = data
	p.rotation = rotation
	p.anchor = anchor
	p.cells = _abs_cells(anchor, data, rotation)
	p.hp = data.max_hp

	var tile := OrganTile.new()
	add_child(tile)
	tile.setup(data, rotation, cell_size())
	# 骨骼在下，器官在上（两者都在网格背景之上）
	tile.z_index = 0 if data.is_bone else 1
	_reposition(p, tile)
	p.node = tile

	for c in p.cells:
		if data.is_bone:
			_bones[c] = p
		else:
			if not _placed.has(c):
				_placed[c] = []
			_placed[c].append(p)
	_order.append(p)

	layout_changed.emit()
	organ_placed.emit(data)
	_refresh_open_textures()
	_revalidate()
	return true


## 有剖开贴图的器官：里面装了别的东西时切成剖面
func _refresh_open_textures() -> void:
	for p in _order:
		if p.node == null:
			continue
		# 鼠标停在它上面、且它内部压着别的器官时，半透明让人看到里面
		var ghost := false
		if _in_bounds(_hover):
			var over := false
			for c in p.cells:
				if c == _hover:
					over = true
					break
			if over:
				for c in p.cells:
					for other in _placed.get(c, []):
						if other != p:
							ghost = true
							break
					if ghost:
						break
		var alpha := 0.35 if ghost else 1.0
		if not is_equal_approx(p.node.modulate.a, alpha):
			p.node.modulate.a = alpha
		# 被骨骼包住的器官画在骨骼下面：包着的时候看不见，悬停骨骼才透出来
		var z := 30
		if p.data.is_bone:
			z = 20
		else:
			for c in p.cells:
				if _bones.has(c):
					z = 10
					break
		if p.node.z_index != z:
			p.node.z_index = z


## 把工具装到带工具口的部件上（工具不占格，只做绑定）
func bind_tool(placed, tool: OrganData) -> bool:
	if placed == null or not placed.data.tool_socket:
		return false
	if placed.tool != null:
		notice.emit("这条已装 %s，先卸下再换" % placed.tool.display_name)
		return false
	if economy != null and not economy.spend(tool.cost):
		notice.emit("代币不足 — 需要 %d" % tool.cost)
		return false
	placed.tool = tool
	notice.emit("%s 装上了 %s" % [placed.data.display_name, tool.display_name])
	layout_changed.emit()
	_revalidate()
	return true


## 卸下工具并按原价返还
func unbind_tool(placed) -> bool:
	if placed == null or placed.tool == null:
		return false
	if economy != null:
		economy.earn(placed.tool.cost)
	notice.emit("卸下 %s" % placed.tool.display_name)
	placed.tool = null
	layout_changed.emit()
	_revalidate()
	return true


func remove_at(cell: Vector2i) -> bool:
	var p: Placed = organ_at(cell)
	if p == null:
		return false

	if economy != null:
		economy.earn(OrganData.refund_value(p.data, p.hp))

	_erase(p)
	layout_changed.emit()
	_refresh_open_textures()
	_revalidate()
	return true


func rotate_at(cell: Vector2i) -> bool:
	var p: Placed = organ_at(cell)
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
	if p.data.is_bone:
		for c in p.cells:
			_bones.erase(c)
		return
	for c in p.cells:
		var arr: Array = _placed.get(c, [])
		arr.erase(p)
		if arr.is_empty():
			_placed.erase(c)


func _write_cells(p: Placed) -> void:
	if p.data.is_bone:
		for c in p.cells:
			_bones[c] = p
		return
	for c in p.cells:
		if not _placed.has(c):
			_placed[c] = []
		_placed[c].append(p)


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

	var p: Placed = organ_at(_hover)
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
		_check_limb_branch(),
		_check_skeleton(),
	]

	var failed: Array[String] = []
	for c in checks:
		# 骨骼分叉只做提示，不阻止出发
		if not c.ok and String(c.id) != "limb":
			failed.append(c.label)

	var message := "启动成功 — 可以出发" if failed.is_empty() else "启动失败：" + "、".join(failed)
	for c in checks:
		if not c.ok and String(c.id) == "limb":
			message += "（提示：%s）" % String(c.detail)
	return {"alive": failed.is_empty(), "checks": checks, "message": message}


## 信号链：寄生虫 → 大脑 → 所有需要神经的器官
func _check_control() -> Dictionary:
	var parasite: Placed = null
	var brain: Placed = null
	for p in _order:
		if p.data.is_parasite:
			parasite = p
		if p.data.is_brain:
			brain = p

	if parasite == null:
		return _check_fail("control", "信号链", "缺少主控芯片")
	if brain == null:
		return _check_fail("control", "信号链", "缺少处理器")

	var adj := _adjacency(OrganData.NERVE)
	if not _reachable(adj, [parasite]).has(brain):
		return _check_fail("control", "信号链", "主控芯片没有连到处理器")

	var from_brain := _reachable(adj, [brain])
	var missing := _names_unreachable(from_brain, true)
	if not missing.is_empty():
		return _check_fail("control", "信号链", "%s 没有信号连接" % ", ".join(missing))

	return _check_ok("control", "信号链", "主控芯片 → 处理器 → 全部部件")


## 能源：心脏 → 所有耗血器官，且供血量足够
func _check_blood() -> Dictionary:
	var heart: Placed = null
	for p in _order:
		if p.data.is_heart:
			heart = p
	if heart == null:
		return _check_fail("blood", "能源", "缺少电源核心")

	var adj := _adjacency(OrganData.BLOOD)
	var reach := _reachable(adj, [heart])

	var missing := _names_unreachable(reach, false)
	if not missing.is_empty():
		return _check_fail("blood", "能源", "%s 没有接入能源" % ", ".join(missing))

	var supply := 0.0
	var demand := 0.0
	for p in _order:
		if p.data.blood_rate < 0.0:
			supply += -p.data.blood_rate
		else:
			demand += p.data.blood_rate

	if demand > supply:
		return _check_fail("blood", "能源", "功率不足：需要 %.1f，电源核心只能提供 %.1f" % [demand, supply])

	return _check_ok("blood", "能源", "功率 %.1f / 需求 %.1f" % [supply, demand])


## 肢体：一个骨骼接点只能接一根线，否则链会分叉
func _check_limb_branch() -> Dictionary:
	var counts := {}
	for link in _links:
		if link.type != OrganData.BONE:
			continue
		for ep in [link.a, link.b]:
			var key := "%s|%s" % [ep.organ.anchor, String(ep.port_uid)]
			counts[key] = int(counts.get(key, 0)) + 1

	var shared: Array[String] = []
	for link in _links:
		if link.type != OrganData.BONE:
			continue
		for ep in [link.a, link.b]:
			var key := "%s|%s" % [ep.organ.anchor, String(ep.port_uid)]
			if int(counts.get(key, 0)) >= 2:
				var label := "%s的%s" % [String(ep.organ.data.display_name), String(ep.port_uid)]
				if not shared.has(label):
					shared.append(label)

	if shared.is_empty():
		return _check_ok("limb", "肢体", "骨骼链条清晰")
	return _check_fail("limb", "肢体", "%s 接了多根骨骼线，肢体链会断" % "、".join(shared))


## 骨架：唯一根骨骼 + 脑必须在颅骨内 + 肢体单元必须挂在骨骼挂点上
func _check_skeleton() -> Dictionary:
	var roots: Array[String] = []
	for p in _order:
		if p.data.is_bone_root:
			roots.append(p.data.display_name)
	if roots.is_empty():
		return _check_fail("skeleton", "骨架", "缺少主梁（骨架的根）")
	if roots.size() > 1:
		return _check_fail("skeleton", "骨架", "只能有一根主梁")

	# 脑必须在「容纳式」骨骼的容积里
	for p in _order:
		if not p.data.is_brain:
			continue
		var inside := false
		for bone in _order:
			if not bone.data.is_bone:
				continue
			if _bone_volume_has(bone, p):
				inside = true
				break
		if not inside:
			return _check_fail("skeleton", "骨架", "处理器必须整个装进头部外壳")

	# 肢体单元必须挂在骨骼挂点上（挂点是骨骼旁边的空格）
	for p in _order:
		if p.data.unit_segments.is_empty():
			continue
		var cell: Vector2i = p.anchor + p.data.attach_cell
		var ok := false
		for bone in _order:
			if not bone.data.is_bone:
				continue
			for pt in bone.data.bone_attach_points:
				var bone_cell: Vector2i = bone.anchor + Vector2i(pt.get("cell", Vector2i.ZERO))
				if bone_cell == cell:
					ok = true
					break
			if ok:
				break
		if not ok:
			return _check_fail("skeleton", "骨架", "%s 没有接在骨骼挂点上" % p.data.display_name)

	return _check_ok("skeleton", "骨架", "主梁 + 头部外壳 + 肢体挂载正常")


## 器官是否完全落在骨骼的容积里（容积为空时退化成骨骼格集合）
func _bone_volume_has(bone, placed) -> bool:
	var volume := {}
	if bone.data.bone_volume.is_empty():
		for c in bone.data.rotated_cells(bone.rotation):
			volume[bone.anchor + c] = true
	else:
		for c in bone.data.bone_volume:
			volume[bone.anchor + c] = true
	for c in placed.data.rotated_cells(placed.rotation):
		if not volume.has(placed.anchor + c):
			return false
	return true


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
	return absi(cell.x) <= GRID_LIMIT and absi(cell.y) <= GRID_LIMIT


func cell_size() -> float:
	return ZOOM_STEPS[clampi(zoom_index, 0, ZOOM_STEPS.size() - 1)]


## 格坐标 (0,0) 的左上角在控件内的位置：面板中心 - 平移
func _grid_origin() -> Vector2:
	return size * 0.5 - pan


## 滚轮缩放：保持光标下的那个格点不动
func _zoom_to(index: int, anchor: Vector2) -> void:
	index = clampi(index, 0, ZOOM_STEPS.size() - 1)
	if index == zoom_index:
		return
	var before := cell_size()
	var world := (anchor - _grid_origin()) / before
	zoom_index = index
	var after := cell_size()
	pan = size * 0.5 - (anchor - world * after)
	_relayout()
	_refresh()


func _pan_by(delta: Vector2) -> void:
	pan += delta
	_relayout()
	_refresh()


## 当前可见的格范围（用于只画看得见的网格线）
func _visible_cells() -> Rect2i:
	var cs := cell_size()
	var origin := _grid_origin()
	var first := ((Vector2.ZERO - origin) / cs).floor()
	var last := ((size - origin) / cs).ceil()
	return Rect2i(
		Vector2i(int(first.x), int(first.y)),
		Vector2i(int(last.x - first.x) + 1, int(last.y - first.y) + 1)
	)


func _cell_rect(cell: Vector2i) -> Rect2:
	var cs := cell_size()
	return Rect2(_grid_origin() + Vector2(cell) * cs, Vector2(cs, cs))


func _cell_at(pos: Vector2) -> Vector2i:
	var cs := cell_size()
	var local := ((pos - _grid_origin()) / cs).floor()
	var cell := Vector2i(local)
	return cell if _in_bounds(cell) else NO_CELL


# ---------------------------------------------------------------- 输入

func _on_mouse_exited() -> void:
	_hover = NO_CELL
	drag_from = null
	_refresh_open_textures()
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _panning:
			# 抓取式平移：画面跟着光标走，所以 pan 反向累计
			pan -= event.position - _pan_anchor
			_pan_anchor = event.position
			_relayout()
			return
		_hover = _cell_at(event.position)
		if drag_from != null:
			drag_pos = event.position
		if repair_mode:
			_update_repair_hint()
		_refresh_open_textures()
		_refresh()
		return

	# 滚轮 = 缩放（四档，整数倍，不糊）。上滚放大，下滚缩小，和地图类软件一致
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_zoom_to(zoom_index + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1), event.position)
		return

	if not (event is InputEventMouseButton):
		return

	# 中键拖动 = 平移画布
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		_pan_anchor = event.position
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
	if cell == NO_CELL:
		return

	_hover = cell

	# Shift + 左键 = 拆卸：先卸工具，没工具再拆部件
	if event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed:
		if _occupied(cell):
			var target = organ_at(cell)
			if target != null and target.tool != null:
				unbind_tool(target)
			else:
				remove_at(cell)
		return

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if repair_mode:
				repair_at(cell)
				return
			# 手持工具时：点在带工具口的部件上 = 绑定
			if _selected != null and _selected.is_tool:
				var target = organ_at(cell)
				if target != null and target.data.tool_socket:
					bind_tool(target, _selected)
				else:
					notice.emit("工具要装在带工具口的机械臂上")
				return
			# 按住接点 = 开始拉线；点空格 = 放置器官
			var ep := endpoint_at(event.position)
			if ep != null:
				drag_from = ep
				drag_pos = event.position
				_selected = null   # 拉线时退出手持器官状态
				_refresh()
				return
			if _selected != null and not _occupied(cell):
				if not place(_anchor_for(cell, _selected, _pending_rotation), _selected, _pending_rotation):
					notice.emit("放不下：这里被占用，或超出可放置范围")
		MOUSE_BUTTON_RIGHT:
			if _occupied(cell):
				rotate_at(cell)
			else:
				rotate_pending()


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var cs := cell_size()
	var origin := _grid_origin()

	draw_rect(Rect2(Vector2.ZERO, size), C_GRID)
	# 只画视口内可见的网格线，无边界网格不能全量遍历
	var vis := _visible_cells()
	for i in range(vis.position.x, vis.position.x + vis.size.x + 1):
		var x := origin.x + i * cs
		if x < 0.0 or x > size.x:
			continue
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), C_GRID_LINE, 1.0)
	for j in range(vis.position.y, vis.position.y + vis.size.y + 1):
		var y := origin.y + j * cs
		if y < 0.0 or y > size.y:
			continue
		draw_line(Vector2(0.0, y), Vector2(size.x, y), C_GRID_LINE, 1.0)

	if not _in_bounds(_hover):
		return

	# 悬停高亮
	if _occupied(_hover):
		draw_rect(_cell_rect(_hover), C_HOVER_BAD)
	elif _selected != null:
		_draw_preview(_anchor_for(_hover, _selected, _pending_rotation))


## 放置锚点：以光标所在格为中心，而不是左上角对齐。1 格器官不受影响。
func _anchor_for(cell: Vector2i, data: OrganData, rotation: int) -> Vector2i:
	var bb := data.bounds(rotation)
	return cell - Vector2i((bb.size.x - 1) / 2, (bb.size.y - 1) / 2)


## 待放置器官的预览：形状 + 接点
func _draw_preview(anchor: Vector2i) -> void:
	var ok := _can_place(anchor, _selected, _pending_rotation)
	var cs := cell_size()
	var bb := _selected.bounds(_pending_rotation)
	var shift := _grid_origin() + Vector2(anchor + bb.position) * cs
	var alpha := 0.45 if ok else 0.20
	var tint := Color(1, 1, 1, alpha + 0.35) if ok else Color(1.0, 0.45, 0.45, alpha + 0.35)
	var full := Rect2(shift, Vector2(bb.size) * cs)

	if _selected.texture != null:
		# 和落地后的绘制一致：整块只画一次，多格器官不复制
		draw_texture_rect(_selected.texture, full, false, tint)
		if not ok:
			draw_rect(full, Color(0.9, 0.15, 0.15, 0.22))
	else:
		for c in _selected.rotated_cells(_pending_rotation):
			var ac: Vector2i = anchor + c
			if not _in_bounds(ac):
				continue
			var r := Rect2(shift + Vector2(c - bb.position) * cs, Vector2(cs, cs))
			var inner := r.grow(-2.0)
			draw_rect(inner, Color(_selected.color, alpha))
			draw_rect(inner, Color(0, 0, 0, 0.4), false, 1.5)
			if not ok:
				draw_rect(r, Color(0.9, 0.15, 0.15, 0.22))

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
