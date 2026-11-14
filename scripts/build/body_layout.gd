## 把拼装网格换算成关卡里的世界坐标：躯干轮廓 + 每条肢体链的锚点。
##
## 换算比例 CELL_PX = 32：和贴图规格（每格 32px）一致。
## 玩家原点约定为**脚底中心**（y=0 在地面），躯干轮廓底边贴 y=0。
##
## 轮廓用「逐格边界追踪」得到，不是凸包：
## 对每个实心格的四条边，邻居为空的边就是轮廓边；再把这些有向边首尾相连成闭环。
## 因此凹形（L 形、U 形）也能精确表达。
class_name BodyLayout
extends RefCounted

const CELL_PX := 32.0
const FLESH := Color(0.725, 0.541, 0.576)   ## 皮肤基色 #B98A93（贴图缺失时的兜底）
## 腿站立时的关节弯折（与 LimbRig.WALK_BEND 保持一致）
const LEG_BEND_DEG: Array[float] = [0.0, -55.0]

## 躯干轮廓闭环（世界局部坐标，原点=脚底中心）；可能有多段
var loops: Array = []              ## Array[PackedVector2Array]
## 每个躯干器官一块：{ "rect": Rect2, "color": Color, "texture": Texture2D }
var parts: Array = []
## 每条肢体链的锚点，顺序与传入的 chains 一致
var anchors: Array = []
## 缝合线：两个不同器官相邻的边界段，[{"from": Vector2, "to": Vector2}]
var seams: Array = []
var bounds := Rect2()
var cell_count := 0
## 腿把身体抬高了多少（脚底到躯干底边的距离）
var leg_drop := 0.0
## 腿的碰撞块（局部坐标），空矩形表示没有腿
var leg_rect := Rect2()


static func from_grid(grid, chains: Array) -> BodyLayout:
	var layout := BodyLayout.new()
	if grid == null:
		return layout

	var filled := {}                   # Vector2i -> Color
	var owner := {}                    # Vector2i -> 器官序号
	var organ_index := 0
	var min_cell := Vector2i(1 << 20, 1 << 20)
	var max_cell := Vector2i(-(1 << 20), -(1 << 20))
	for p in grid.organs():
		if p.data.limb != OrganData.Limb.NONE:
			continue
		for c in p.data.rotated_cells(p.rotation):
			var cell: Vector2i = p.anchor + c
			filled[cell] = p.data.color
			owner[cell] = organ_index
			min_cell.x = mini(min_cell.x, cell.x)
			min_cell.y = mini(min_cell.y, cell.y)
			max_cell.x = maxi(max_cell.x, cell.x)
			max_cell.y = maxi(max_cell.y, cell.y)
		organ_index += 1
	if filled.is_empty():
		return layout

	var size := Vector2(max_cell - min_cell + Vector2i.ONE) * CELL_PX
	# 有朝下的腿时，把整个躯干抬高，让腿的脚落在地面（y=0）
	# 垂距必须按"腿站立时的弯折"算，否则会低估、腿插进地里
	var leg_drop := 0.0
	for chain in chains:
		if not chain.valid or is_zero_approx(chain.base_angle_deg):
			continue
		var drop := 0.0
		var bend := 0.0
		for i in chain.segments.size():
			bend += LEG_BEND_DEG[i] if i < LEG_BEND_DEG.size() else 0.0
			drop += chain.segments[i].length * sin(deg_to_rad(chain.base_angle_deg + bend))
		leg_drop = maxf(leg_drop, drop)
	layout.leg_drop = leg_drop
	# 原点：底边中点对齐到 (0,0)；有腿时把躯干整体抬到腿上方
	var origin := Vector2(min_cell) * CELL_PX + Vector2(size.x * 0.5, size.y + leg_drop)
	layout.bounds = Rect2(Vector2.ZERO, size)
	layout.cell_count = filled.size()

	# --- 轮廓：逐格边界追踪 ---
	var edges := {}                    # Vector2i -> Array[Vector2i]（格角坐标）
	var dirs := [
		{"n": Vector2i(0, -1), "a": Vector2i(0, 0), "b": Vector2i(1, 0)},
		{"n": Vector2i(1, 0), "a": Vector2i(1, 0), "b": Vector2i(1, 1)},
		{"n": Vector2i(0, 1), "a": Vector2i(1, 1), "b": Vector2i(0, 1)},
		{"n": Vector2i(-1, 0), "a": Vector2i(0, 1), "b": Vector2i(0, 0)},
	]
	for cell in filled:
		for d in dirs:
			if filled.has(cell + d["n"]):
				continue
			var from: Vector2i = cell + d["a"]
			var to: Vector2i = cell + d["b"]
			if not edges.has(from):
				edges[from] = []
			edges[from].append(to)

	for loop_cells in _trace_loops(edges):
		if loop_cells.size() < 3:
			continue
		var poly := PackedVector2Array()
		for corner in loop_cells:
			poly.append(Vector2(corner) * CELL_PX - origin)
		layout.loops.append(poly)

	# --- 每个躯干器官一块，用于贴图/色块叠加 ---
	for p in grid.organs():
		if p.data.limb != OrganData.Limb.NONE:
			continue
		var cells: Array = p.data.rotated_cells(p.rotation)
		if cells.is_empty():
			continue
		var lo: Vector2i = p.anchor + cells[0]
		var hi: Vector2i = lo
		for c in cells:
			var world: Vector2i = p.anchor + c
			lo.x = mini(lo.x, world.x)
			lo.y = mini(lo.y, world.y)
			hi.x = maxi(hi.x, world.x)
			hi.y = maxi(hi.y, world.y)
		var rect := Rect2(
			Vector2(lo) * CELL_PX - origin,
			Vector2(hi - lo + Vector2i.ONE) * CELL_PX)
		layout.parts.append({
			"rect": rect,
			"color": p.data.color,
			"texture": p.data.texture,
		})

	# --- 肢体锚点 = 接在躯干上的骨骼接点所在格的中心 ---
	for chain in chains:
		var anchor_cell: Vector2i = chain.body_anchor_cell
		var center := Vector2(anchor_cell) * CELL_PX + Vector2(CELL_PX, CELL_PX) * 0.5 - origin
		layout.anchors.append(center)

	layout.seams = _seams_between_organs(filled, owner, origin)

	# 腿的碰撞块：从躯干底边一直延伸到脚底，让身体真的"站在腿上"
	if leg_drop > 0.0:
		var min_x := 1e9
		var max_x := -1e9
		for chain in chains:
			if not chain.valid or is_zero_approx(chain.base_angle_deg):
				continue
			var c := Vector2(chain.body_anchor_cell) * CELL_PX - origin
			min_x = minf(min_x, c.x - 26.0)
			max_x = maxf(max_x, c.x + 26.0)
		if max_x > min_x:
			layout.leg_rect = Rect2(min_x, -leg_drop, max_x - min_x, leg_drop)

	return layout


## 缝合线 = 两个不同器官相邻的边，按共线合并成长段
static func _seams_between_organs(filled: Dictionary, owner: Dictionary, origin: Vector2) -> Array:
	var horizontal := {}     # y -> Array[Vector2i]（x 起点、x 终点，单位：格）
	var vertical := {}       # x -> Array[Vector2i]（y 起点、y 终点）

	for cell in filled:
		var me: int = owner[cell]
		var right: Vector2i = cell + Vector2i(1, 0)
		if filled.has(right) and int(owner[right]) != me:
			if not vertical.has(cell.x + 1):
				vertical[cell.x + 1] = []
			vertical[cell.x + 1].append(Vector2i(cell.y, cell.y + 1))
		var down: Vector2i = cell + Vector2i(0, 1)
		if filled.has(down) and int(owner[down]) != me:
			if not horizontal.has(cell.y + 1):
				horizontal[cell.y + 1] = []
			horizontal[cell.y + 1].append(Vector2i(cell.x, cell.x + 1))

	var out: Array = []
	for y in horizontal:
		for span in _merge_spans(horizontal[y]):
			out.append({
				"from": Vector2(span.x, y) * CELL_PX - origin,
				"to": Vector2(span.y, y) * CELL_PX - origin,
			})
	for x in vertical:
		for span in _merge_spans(vertical[x]):
			out.append({
				"from": Vector2(x, span.x) * CELL_PX - origin,
				"to": Vector2(x, span.y) * CELL_PX - origin,
			})
	return out


## 把首尾相接的区间合并成长段
static func _merge_spans(spans: Array) -> Array:
	if spans.is_empty():
		return []
	var sorted := spans.duplicate()
	sorted.sort_custom(func(a, b): return a.x < b.x)
	var out: Array = []
	var cur: Vector2i = sorted[0]
	for i in range(1, sorted.size()):
		var s: Vector2i = sorted[i]
		if s.x <= cur.y:
			cur.y = maxi(cur.y, s.y)
		else:
			out.append(cur)
			cur = s
	out.append(cur)
	return out


## 把有向边界边串成闭环
static func _trace_loops(edges: Dictionary) -> Array:
	var loops: Array = []
	while not edges.is_empty():
		var start: Vector2i = edges.keys()[0]
		var loop: Array = []
		var cur := start
		var guard := 0
		while guard < 4096:
			guard += 1
			loop.append(cur)
			var nexts: Array = edges.get(cur, [])
			if nexts.is_empty():
				break
			var nxt: Vector2i = nexts.pop_back()
			if nexts.is_empty():
				edges.erase(cur)
			cur = nxt
			if cur == start:
				break
		if loop.size() >= 3:
			loops.append(loop)
	return loops


func summary() -> String:
	if cell_count == 0:
		return "躯干：无"
	return "躯干 %d 格 · %.0f×%.0f 像素 · %d 段轮廓" % [
		cell_count, bounds.size.x, bounds.size.y, loops.size()]
