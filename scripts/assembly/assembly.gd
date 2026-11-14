## 拼装数据模型：一棵以根部件为原点的树。自由坐标，不依赖格子。
class_name Assembly
extends RefCounted

class Part:
	var data: PartData
	var position := Vector2.ZERO    ## 左上角的世界坐标
	var rotation := 0
	var hp := 0.0
	var parent := -1                ## 父件下标，-1 表示根
	var parent_socket: StringName = &""
	var tool: PartData = null       ## 装在工具口上的末端工具

var parts: Array[Part] = []


# ---------------------------------------------------------------- 查询

func root_index() -> int:
	for i in parts.size():
		if parts[i].parent < 0:
			return i
	return -1


func count_of(predicate: Callable) -> int:
	var n := 0
	for p in parts:
		if predicate.call(p):
			n += 1
	return n


func children(index: int) -> Array[int]:
	var out: Array[int] = []
	for i in parts.size():
		if parts[i].parent == index:
			out.append(i)
	return out


## 接口的世界坐标
func socket_position(index: int, uid: StringName) -> Vector2:
	var p := parts[index]
	return p.position + p.data.socket_offset(uid, p.rotation)


## 部件在世界里的矩形
func rect_of(index: int) -> Rect2:
	var p := parts[index]
	return Rect2(p.position, p.data.size)


## 这个接口有没有被占用
func is_socket_used(index: int, uid: StringName) -> bool:
	for p in parts:
		if p.parent == index and p.parent_socket == uid:
			return true
	return false


# ---------------------------------------------------------------- 修改

## 放下根部件（机身）
func add_root(data: PartData, position := Vector2.ZERO) -> bool:
	if data == null or not data.is_root or parts.size() > 0:
		return false
	var p := Part.new()
	p.data = data
	p.position = position
	p.hp = data.max_hp
	parts.append(p)
	return true


## 把部件挂到某件的某个接口上；位置由接口推导
func attach(data: PartData, parent_index: int, socket_uid: StringName, rotation := 0) -> bool:
	if data == null or data.anchor == null:
		return false
	if parent_index < 0 or parent_index >= parts.size():
		return false
	var socket := parts[parent_index].data.socket(socket_uid)
	if socket == null or is_socket_used(parent_index, socket_uid):
		return false
	if socket.kind != data.anchor.kind:
		return false
	var need_dir := SocketData.opposite(SocketData.rotate_dir(socket.dir, parts[parent_index].rotation))
	if SocketData.rotate_dir(data.anchor.dir, rotation) != need_dir:
		return false

	var p := Part.new()
	p.data = data
	p.rotation = rotation
	p.parent = parent_index
	p.parent_socket = socket_uid
	p.hp = data.max_hp
	# 本件的 anchor 正好落在父件接口上
	p.position = socket_position(parent_index, socket_uid) - SocketData.rotate_vec(data.anchor.offset, rotation)
	parts.append(p)
	return true


## 拆掉某件及其整棵子树，返回被拆掉的下标（已排序）
func remove(index: int) -> Array[int]:
	var doomed: Array[int] = []
	if index < 0 or index >= parts.size():
		return doomed
	var stack: Array[int] = [index]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		doomed.append(cur)
		for c in children(cur):
			stack.append(c)
	doomed.sort()
	for i in range(doomed.size() - 1, -1, -1):
		parts.remove_at(doomed[i])
	return doomed


## 整机平移
func move_root(delta: Vector2) -> void:
	var r := root_index()
	if r >= 0:
		for p in parts:
			p.position += delta


## 装工具（不占格）；已装则替换
func bind_tool(index: int, tool: PartData) -> bool:
	if index < 0 or index >= parts.size():
		return false
	if not _has_tool_socket(index):
		return false
	parts[index].tool = tool
	return true


func unbind_tool(index: int) -> PartData:
	if index < 0 or index >= parts.size():
		return null
	var old := parts[index].tool
	parts[index].tool = null
	return old


func _has_tool_socket(index: int) -> bool:
	for s in parts[index].data.sockets:
		if s.kind == SocketData.Kind.TOOL:
			return true
	return false


## 吸附候选：给定插头当前位置，找最近的可用接口。
## 返回 {parent, socket, position}（position 是挂上后部件的左上角），或空字典
func find_snap(data: PartData, rotation: int, anchor_position: Vector2, max_distance: float) -> Dictionary:
	if data == null or data.anchor == null:
		return {}
	var best := {}
	var best_dist := max_distance
	for i in parts.size():
		for s in parts[i].data.sockets:
			if s.kind != data.anchor.kind or is_socket_used(i, s.uid):
				continue
			var target := socket_position(i, s.uid)
			var dist := target.distance_to(anchor_position)
			if dist < best_dist:
				best_dist = dist
				best = {
					"parent": i,
					"socket": s.uid,
					"position": target - SocketData.rotate_vec(data.anchor.offset, rotation),
				}
	return best
