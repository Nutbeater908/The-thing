## 桥接：把新装配系统（Assembly）换算成关卡需要的世界坐标数据。
## 独立文件，不改动任何现有脚本；先写、先测，再接进 playable_slice。
class_name AssemblyBridge
extends RefCounted

## 一个部件在世界里的摆放
class Placed:
	var data: PartData
	var position: Vector2        ## 左上角的世界坐标
	var rotation := 0
	var tool: PartData = null


## 整台机体：部件列表 + 包围盒 + 各接口的世界坐标
class Body:
	var parts: Array[Placed] = []
	var root_index := -1
	var bounds := Rect2()
	## 接口世界坐标：{ "shoulder": Vector2, ... }
	var sockets := {}


static func from_assembly(assembly: Assembly, origin := Vector2.ZERO) -> Body:
	var body := Body.new()
	if assembly == null:
		return body

	# 根部件左上角对齐到 origin，其余部件按差值平移
	var root := assembly.root_index()
	var shift := Vector2.ZERO
	if root >= 0:
		shift = origin - assembly.parts[root].position
		body.root_index = root

	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for i in assembly.parts.size():
		var src := assembly.parts[i]
		var p := Placed.new()
		p.data = src.data
		p.rotation = src.rotation
		p.tool = src.tool
		p.position = src.position + shift
		body.parts.append(p)
		min_p = Vector2(minf(min_p.x, p.position.x), minf(min_p.y, p.position.y))
		max_p = Vector2(maxf(max_p.x, p.position.x + p.data.size.x),
						maxf(max_p.y, p.position.y + p.data.size.y))
	if body.parts.is_empty():
		return body
	body.bounds = Rect2(min_p, max_p - min_p)

	# 接口世界坐标
	for i in assembly.parts.size():
		for s in assembly.parts[i].data.sockets:
			body.sockets[s.uid] = assembly.socket_position(i, s.uid) + shift
	return body


## 某个接口的世界坐标（没有返回 origin）
static func socket_of(body: Body, uid: StringName, fallback := Vector2.ZERO) -> Vector2:
	return body.sockets.get(uid, fallback)


## 机体高度（脚底到头顶），用于镜头与脚底对齐
## 用根部件（机身）的底边对齐到给定 y，默认 0 = 玩家脚底
static func root_bottom_at(body: Body, bottom_y := 0.0) -> Vector2:
	if body.root_index < 0:
		return Vector2.ZERO
	var root: Placed = body.parts[body.root_index]
	var bottom := root.position.y + root.data.size.y
	return Vector2(0.0, bottom_y - bottom)


## 让髋点上方 leg_len 的高度落到地面：机身被腿"顶起来"
## 现在从实际装配的腿读取骨长，不再用固定的标准腿
static func hip_ground_lift(body: Body, ground_y := 0.0, standing_bend := 0.92) -> Vector2:
	if body.parts.is_empty():
		return Vector2.ZERO
	
	# 找第一个运动部件，读其腿长
	var leg_spec: LegGeometry.Spec = null
	for part in body.parts:
		if part.data.category == PartData.Category.LOCOMOTION:
			leg_spec = LegGeometry.from_part(part.data)
			break
	
	if leg_spec == null or leg_spec.total_length <= 0.0:
		return Vector2.ZERO
	
	var hip_pos: Vector2 = socket_of(body, &"hip")
	# 站姿弯曲：0.92 表示略微弯膝，保留活动余量
	var effective_height := leg_spec.total_length * standing_bend
	return Vector2(0.0, (ground_y - effective_height) - hip_pos.y)


static func height(body: Body) -> float:
	return body.bounds.size.y
