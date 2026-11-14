## 从拼装网格解析出肢体链。
##
## 规则（见 docs/肢体系统设计稿.md 第 3 节）：
##  - 只有 limb != NONE 的器官参与链
##  - 链的每一节必须通过 BONE 链接相连
##  - 链必须从**末端**（tip_kind != NONE）出发，沿骨骼回溯到躯干（limb == NONE 的器官）
##  - 最长 MAX_SEGMENTS 节
##
## 为什么从末端回溯：玩家搭出来的骨骼图可能分叉（一个接点接两条线）。
## 从躯干向外走会走进岔路，从末端回溯则每条链对应一个明确的攻击端。
## 一个器官不会同时出现在两条链里：先解析到的链占用它。
class_name LimbChainBuilder
extends RefCounted

const MAX_SEGMENTS := 3


class Segment:
	var organ: OrganData
	var rotation := 0
	var length := 80.0
	var joint_min := -120.0
	var joint_max := 120.0
	var is_tip := false
	var tip_damage := 0.0
	var tip_radius := 10.0


class Chain:
	var segments: Array = []          ## Array[Segment]，根节（靠躯干）在前
	var bind_action: StringName = &"attack"
	## 单元自带的动作模组（整体式肢体单元才有）
	var motion: Resource = null
	## 静止姿态的基准角度（度）：由单元挂点方向决定，0=朝右，90=朝下
	var base_angle_deg := 0.0
	## 这条链接在躯干上的那个骨骼接点所在的格坐标（网格坐标）
	var body_anchor_cell := Vector2i.ZERO
	var valid := false
	var reason := ""


## 返回 Array[Chain]；无效的链也返回，方便 UI 提示原因
static func build(grid) -> Array:
	var out: Array = []
	if grid == null:
		return out

	var organs: Array = grid.organs()
	if organs.is_empty():
		return out

	var bone_adj := {}      # Placed -> Array[Placed]
	var bone_degree := {}   # Placed -> 骨骼线条数（含接躯干的）
	for p in organs:
		bone_adj[p] = []
		bone_degree[p] = 0
	for link in grid.links():
		if link.type != OrganData.BONE:
			continue
		var a = link.a.organ
		var b = link.b.organ
		if not bone_adj.has(a) or not bone_adj.has(b):
			continue
		bone_adj[a].append(b)
		bone_adj[b].append(a)
		bone_degree[a] = int(bone_degree[a]) + 1
		bone_degree[b] = int(bone_degree[b]) + 1

	var used := {}
	for tip in organs:
		if tip.data.tip_kind == OrganData.TipKind.NONE or used.has(tip):
			continue
		var found: Dictionary = _path_to_body(tip, bone_adj, used, grid)
		var path: Array = found.get("path", [])
		if path.is_empty():
			var c := Chain.new()
			c.segments.append(_segment_of(tip))
			c.bind_action = tip.data.bind_action
			c.valid = false
			c.reason = "末端没有在 %d 节内连到躯干" % MAX_SEGMENTS
			out.append(c)
			continue
		var chain := _chain_of(path)
		chain.body_anchor_cell = found.get("anchor_cell", Vector2i.ZERO)
		if chain.valid:
			for q in path:
				used[q] = true
		out.append(chain)

	return out


## 从一个「整体式肢体单元」构造链：分段来自单元自己的描述，末端也来自单元
static func from_unit(placed, anchor_cell: Vector2i) -> Chain:
	var chain := Chain.new()
	chain.body_anchor_cell = anchor_cell
	chain.bind_action = placed.data.bind_action
	chain.motion = placed.data.motion
	# 挂点朝向决定静止姿态：0=上 → -90°，1=右 → 0°，2=下 → 90°，3=左 → 180°
	chain.base_angle_deg = [(-90.0), 0.0, 90.0, 180.0][clampi(placed.data.attach_dir, 0, 3)]
	for seg in placed.data.unit_segments:
		var s := Segment.new()
		s.organ = placed.data
		s.rotation = placed.rotation
		s.length = float(seg.get("length", 80.0))
		s.joint_min = float(seg.get("joint_min", -120.0))
		s.joint_max = float(seg.get("joint_max", 120.0))
		chain.segments.append(s)
	if chain.segments.is_empty():
		chain.valid = false
		chain.reason = "肢体单元没有定义分段"
		return chain
	var last: Segment = chain.segments[chain.segments.size() - 1]
	last.is_tip = placed.data.tip_kind != OrganData.TipKind.NONE
	last.tip_damage = placed.data.tip_damage
	last.tip_radius = placed.data.tip_radius

	# 绑定了末端工具：追加一节，伤害与口径来自工具
	if placed.tool != null and placed.tool.is_tool:
		var t := Segment.new()
		t.organ = placed.tool
		t.rotation = 0
		t.length = placed.tool.tool_length
		t.joint_min = -60.0
		t.joint_max = 60.0
		t.is_tip = true
		t.tip_damage = placed.tool.tip_damage
		t.tip_radius = placed.tool.tip_radius
		# 臂自己不再是末端
		last.is_tip = false
		last.tip_damage = 0.0
		chain.segments.append(t)

	# 单元只要定义分段就有效；没有末端类型的单元（比如腿）只渲染，不造成伤害
	chain.valid = true
	return chain


## 静态：把拼装盘上的所有整体式肢体单元转成链
static func build_units(grid) -> Array:
	var out: Array = []
	if grid == null:
		return out
	for p in grid.organs():
		if p.data.limb == OrganData.Limb.NONE:
			continue
		if p.data.unit_segments.is_empty():
			continue
		var anchor_cell: Vector2i = p.anchor + p.data.attach_cell
		out.append(from_unit(p, anchor_cell))
	return out
## 返回 { "path": [根节 ... 末端], "anchor_cell": Vector2i }；失败返回空 path。
static func _path_to_body(tip, bone_adj: Dictionary, used: Dictionary, grid) -> Dictionary:
	var prev := {tip: null}
	var queue: Array = [tip]
	var head := 0
	while head < queue.size():
		var cur = queue[head]
		head += 1
		if cur != tip:
			var body_ep: Dictionary = _body_endpoint_of(cur, grid)
			if not body_ep.is_empty():
				return {
					"path": _rebuild(prev, cur),
					"anchor_cell": body_ep.get("cell", Vector2i.ZERO),
				}
		for n in bone_adj.get(cur, []):
			if n.data.limb == OrganData.Limb.NONE:
				continue
			if prev.has(n) or used.has(n):
				continue
			prev[n] = cur
			queue.append(n)
	return {"path": [], "anchor_cell": Vector2i.ZERO}


## 找 organ 与躯干之间的那根骨骼线，返回躯干那一端的格坐标
static func _body_endpoint_of(organ, grid) -> Dictionary:
	for link in grid.links():
		if link.type != OrganData.BONE:
			continue
		var a = link.a.organ
		var b = link.b.organ
		if a == organ and b.data.limb == OrganData.Limb.NONE:
			return {"organ": b, "cell": b.anchor + _port_cell(b, link.b.port_uid)}
		if b == organ and a.data.limb == OrganData.Limb.NONE:
			return {"organ": a, "cell": a.anchor + _port_cell(a, link.a.port_uid)}
	return {}


static func _port_cell(placed, uid: StringName) -> Vector2i:
	for port in placed.data.rotated_ports(placed.rotation):
		if port.uid == uid:
			return port.cell
	return Vector2i.ZERO


static func _rebuild(prev: Dictionary, last) -> Array:
	# prev 记录的是「子 → 父（更靠近末端）」，所以倒着排出来正好是 [根节 ... 末端]
	var out: Array = []
	var node = last
	while node != null:
		out.append(node)
		node = prev.get(node, null)
	return out


static func _chain_of(path: Array) -> Chain:
	var chain := Chain.new()
	for p in path:
		chain.segments.append(_segment_of(p))
	if not path.is_empty():
		chain.bind_action = path[0].data.bind_action
	_finish(chain)
	return chain


static func _segment_of(placed) -> Segment:
	var s := Segment.new()
	s.organ = placed.data
	s.rotation = placed.rotation
	s.length = placed.data.segment_length
	s.joint_min = placed.data.joint_min_deg
	s.joint_max = placed.data.joint_max_deg
	s.is_tip = placed.data.tip_kind != OrganData.TipKind.NONE
	s.tip_damage = placed.data.tip_damage
	s.tip_radius = placed.data.tip_radius
	return s


static func _finish(chain: Chain) -> void:
	if chain.segments.size() < 2:
		chain.valid = false
		chain.reason = "肢体链至少要有两节（肢体 + 末端）"
		return
	var last: Segment = chain.segments[chain.segments.size() - 1]
	if not last.is_tip:
		chain.valid = false
		chain.reason = "肢体链的末端不是可用的末端器官"
		return
	chain.valid = true
	chain.reason = ""
