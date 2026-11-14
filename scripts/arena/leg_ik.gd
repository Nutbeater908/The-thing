## 两骨 IK：给定髋与目标脚位，解出膝盖位置。
##
## 从旧项目的 leg_kinematics.gd 移植，只保留做姿态需要的那一支：
## 余弦定理求出「髋到膝的夹角」和「膝的夹角」，再沿垂直方向偏移得到膝点。
## bend = +1 正关节（膝向前），-1 反关节（膝向后，鸟/兽腿）。
class_name LegIk
extends RefCounted


## 返回 [髋, 膝, 脚] 三个点；脚点会被夹进可达范围内
static func solve_points(hip: Vector2, target: Vector2, upper: float, lower: float, bend := -1.0) -> Array[Vector2]:
	var delta := target - hip
	var distance := clampf(delta.length(), absf(upper - lower) + 0.01, upper + lower - 0.01)
	var axis := delta.normalized() if delta.length_squared() > 0.0001 else Vector2.DOWN
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	var knee := hip + axis * along + Vector2(axis.y, -axis.x) * height * bend
	var foot := hip + axis * distance
	return [hip, knee, foot]


## 把 [髋, 膝, 脚] 转成两节的角度（度，相对上一节）
static func to_angles(points: Array[Vector2], base_deg: float) -> Array[float]:
	var hip: Vector2 = points[0]
	var knee: Vector2 = points[1]
	var foot: Vector2 = points[2]
	var a0 := rad_to_deg((knee - hip).angle())
	var a1 := rad_to_deg((foot - knee).angle()) - a0
	return [a0 - base_deg, a1]
