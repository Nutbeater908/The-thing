## 拼装结果 → 生物属性。
##
## 质量与质心按器官格子的 mass_per_cell 加权；
## 每条肢体记录自己的根部位置和伸展方向。
##
## 移动推力由「玩家输入方向」与「腿的蹬地方向」的对齐程度决定：
## 腿在哪个方向，就只能往哪个方向蹬。位置和朝向直接改变手感，
## 而不是靠器官数量线性叠加。
class_name CreatureStats
extends RefCounted

const TUNING_PATH := "res://resources/tuning/creature.tres"

## 推力换算成像素/秒的比例系数（俯视模型用）
const SPEED_SCALE := 150.0

static var _tuning: CreatureTuning


static func tuning() -> CreatureTuning:
	if _tuning == null:
		_tuning = load(TUNING_PATH)
	return _tuning


## 一个肢体在网格中的几何信息
class Limb:
	var kind: int            ## OrganData.Limb
	var anchor: Vector2i     ## 绝对格坐标（根部）
	var direction: Vector2    ## 伸展方向，单位向量
	var length: int          ## 占格数
	var mass: float


var mass := 0.0
var centroid := Vector2.ZERO   ## 绝对格坐标（浮点），质量加权
var limbs: Array[Limb] = []

## 每个格子的位置与质量，用于转动惯量
var _points: Array = []


## 一个器官实例的几何信息（与 AssemblyGrid 解耦）
class Piece:
	var data: OrganData
	var rotation: int
	var anchor: Vector2i
	var cells: Array[Vector2i]


static func from_grid(grid) -> CreatureStats:
	var pieces: Array[Piece] = []
	for p in grid.organs():
		var piece := Piece.new()
		piece.data = p.data
		piece.rotation = p.rotation
		piece.anchor = p.anchor
		piece.cells = p.cells
		pieces.append(piece)
	return _from_pieces(pieces)


## 从 RunState 保存的蓝图重建（关卡侧用）
static func from_blueprint(blueprint: Array) -> CreatureStats:
	var lib := OrganLibrary.catalog()
	var pieces: Array[Piece] = []

	for entry in blueprint:
		var data: OrganData = lib.get(entry["id"])
		if data == null:
			continue
		var rotation: int = entry["rotation"]
		var anchor: Vector2i = entry["anchor"]

		var piece := Piece.new()
		piece.data = data
		piece.rotation = rotation
		piece.anchor = anchor
		for c in data.rotated_cells(rotation):
			piece.cells.append(anchor + c)
		pieces.append(piece)

	return _from_pieces(pieces)


static func _from_pieces(pieces: Array[Piece]) -> CreatureStats:
	var stats := CreatureStats.new()
	stats._build(pieces)
	return stats


func legs() -> Array[Limb]:
	var out: Array[Limb] = []
	for limb in limbs:
		if limb.kind == OrganData.Limb.LEG:
			out.append(limb)
	return out


func claws() -> Array[Limb]:
	var out: Array[Limb] = []
	for limb in limbs:
		if limb.kind == OrganData.Limb.CLAW:
			out.append(limb)
	return out


## 支撑腿：伸展方向朝下，负责站立、行走、跳跃
func support_legs() -> Array[Limb]:
	var out: Array[Limb] = []
	for limb in limbs:
		if limb.kind == OrganData.Limb.LEG and limb.direction.dot(Vector2.DOWN) > 0.5:
			out.append(limb)
	return out


## 横向腿：伸展方向接近水平，只用于蹬击
func side_legs() -> Array[Limb]:
	var out: Array[Limb] = []
	for limb in limbs:
		if limb.kind == OrganData.Limb.LEG and absf(limb.direction.dot(Vector2.DOWN)) <= 0.5:
			out.append(limb)
	return out


## 支撑腿的总长度
func support_power() -> float:
	var power := 0.0
	for limb in support_legs():
		power += float(limb.length)
	return power


## 横版：水平行走力；dir 取 -1 / 0 / 1
func walk_force(dir: float) -> float:
	return dir * support_power() * tuning().walk_force


## 横版：跳跃冲量
func jump_impulse() -> float:
	return support_power() * tuning().jump_impulse


## 转动惯量：Σ m × r²（相对质心）
func inertia() -> float:
	var out := 0.0
	for point in _points:
		var r: Vector2 = point["pos"] - centroid
		out += float(point["mass"]) * r.length_squared()
	return out


## 输入方向（单位向量）下，全部腿产生的推力向量
func push_for(input_dir: Vector2) -> Vector2:
	var out := Vector2.ZERO
	for limb in limbs:
		if limb.kind != OrganData.Limb.LEG:
			continue
		var push_dir := -limb.direction   # 蹬地方向 = 腿伸展的反方向
		var align := maxf(0.0, push_dir.dot(input_dir))
		out += push_dir * align * float(limb.length)
	return out


## 输入方向下的移动速度（像素/秒）
func speed_for(input_dir: Vector2) -> float:
	if mass <= 0.0:
		return 0.0
	return push_for(input_dir).length() / mass * SPEED_SCALE


## 输入方向下相对质心的扭矩；正负代表旋转方向
func torque_for(input_dir: Vector2) -> float:
	var out := 0.0
	for limb in limbs:
		if limb.kind != OrganData.Limb.LEG:
			continue
		var push_dir := -limb.direction
		var align := maxf(0.0, push_dir.dot(input_dir))
		var force := push_dir * align * float(limb.length)
		var r := Vector2(limb.anchor) - centroid
		out += r.x * force.y - r.y * force.x
	return out


# ---------------------------------------------------------------- 内部

func _build(organs: Array) -> void:
	mass = 0.0
	var weighted := Vector2.ZERO
	_points.clear()

	for p in organs:
		var organ_mass: float = p.data.mass()
		mass += organ_mass
		for c in p.cells:
			var cell_mass: float = p.data.mass_per_cell
			weighted += Vector2(c) * cell_mass
			_points.append({"pos": Vector2(c), "mass": cell_mass})

		var limb := _make_limb(p)
		if limb != null:
			limbs.append(limb)

	if mass > 0.0:
		centroid = weighted / mass


func _make_limb(p) -> Limb:
	if p.data.limb == OrganData.Limb.NONE:
		return null

	var ports: Array = p.data.rotated_ports(p.rotation)
	if ports.is_empty():
		return null

	# 根部 = 所有接点的平均位置（腿/爪的三个接点通常在同一格）
	var root := Vector2.ZERO
	for port in ports:
		root += Vector2(port.cell)
	root /= float(ports.size())

	# 伸展方向 = 从根部指向最远的格子
	var rotated: Array = p.data.rotated_cells(p.rotation)
	var far := Vector2(rotated[0])
	var far_dist := -1.0
	for c in rotated:
		var d := Vector2(c).distance_squared_to(root)
		if d > far_dist:
			far_dist = d
			far = Vector2(c)

	var dir := far - root
	if dir.length_squared() < 0.0001:
		return null

	var limb := Limb.new()
	limb.kind = p.data.limb
	limb.anchor = p.anchor + Vector2i(roundi(root.x), roundi(root.y))
	limb.direction = dir.normalized()
	limb.length = rotated.size()
	limb.mass = p.data.mass()
	return limb
