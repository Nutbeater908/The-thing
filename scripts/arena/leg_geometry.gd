## 腿部几何：从标定点计算骨长、变换、脚底偏移。
## 拼装预览和关卡共用，避免各算各的。
class_name LegGeometry
extends RefCounted

## 从 PartData 读取标定点，计算几何
class Spec:
	var upper_length := 0.0      ## 髋→膝
	var lower_length := 0.0      ## 膝→踝
	var foot_offset := Vector2.ZERO  ## 踝→脚底中心
	var total_length := 0.0      ## 髋→脚底（伸直）
	
	## 三段贴图的本地枢轴（用于绘制变换）
	var hip := Vector2.ZERO
	var knee_upper := Vector2.ZERO
	var knee_lower := Vector2.ZERO
	var ankle_shin := Vector2.ZERO
	var ankle_foot := Vector2.ZERO


static func from_part(part: PartData) -> Spec:
	var spec := Spec.new()
	if part == null or part.segment_textures.size() < 2:
		return spec
	
	var hip_s := part.socket(&"pivot_hip")
	var knee_u := part.socket(&"pivot_knee_u")
	var knee_l := part.socket(&"pivot_knee_l")
	var ankle_s := part.socket(&"pivot_ankle_s")
	var ankle_f := part.socket(&"pivot_ankle_f")
	
	if hip_s == null or knee_u == null or knee_l == null or ankle_s == null:
		return spec
	
	spec.hip = hip_s.offset
	spec.knee_upper = knee_u.offset
	spec.knee_lower = knee_l.offset
	spec.ankle_shin = ankle_s.offset
	spec.ankle_foot = ankle_f.offset if ankle_f != null else ankle_s.offset
	
	# 骨长：标定点之间的距离
	spec.upper_length = spec.knee_upper.distance_to(spec.hip)
	spec.lower_length = spec.ankle_shin.distance_to(spec.knee_lower)
	spec.total_length = spec.upper_length + spec.lower_length
	
	# 脚底偏移：踝点到脚掌图下边缘
	if part.segment_textures.size() >= 3 and part.segment_textures[2] != null:
		var foot_tex: Texture2D = part.segment_textures[2]
		spec.foot_offset = Vector2(0.0, foot_tex.get_height() - spec.ankle_foot.y)
	
	return spec


## 给定髋和踝的世界坐标，返回三段的绘制变换（position, rotation）
## 只用于静态预览（拼装盘），因为这里没有膝盖信息
static func compute_transforms(spec: Spec, hip_world: Vector2, ankle_world: Vector2) -> Array:
	var transforms := []
	
	# 大腿：髋→踝方向减去本地膝偏移
	var leg_dir := (ankle_world - hip_world).normalized()
	var thigh_angle := leg_dir.angle() - (spec.knee_upper - spec.hip).angle()
	transforms.append({"position": hip_world, "rotation": thigh_angle})
	
	# 小腿：膝点的世界坐标
	var knee_world := hip_world + (spec.knee_upper - spec.hip).rotated(thigh_angle)
	var shin_angle := (ankle_world - knee_world).angle() - (spec.ankle_shin - spec.knee_lower).angle()
	transforms.append({"position": knee_world, "rotation": shin_angle})
	
	# 脚：踝点世界坐标，保持水平
	var ankle_actual := knee_world + (spec.ankle_shin - spec.knee_lower).rotated(shin_angle)
	transforms.append({"position": ankle_actual, "rotation": 0.0})
	
	return transforms


## 用 IK 解出的 [髋, 膝, 踝] 三点直接驱动绘制。
## 关卡里必须用这个：compute_transforms 只有方向、丢掉距离，无法表现抬脚。
static func transforms_from_points(spec: Spec, hip: Vector2, knee: Vector2, ankle: Vector2) -> Array:
	var thigh_angle := (knee - hip).angle() - (spec.knee_upper - spec.hip).angle()
	var shin_angle := (ankle - knee).angle() - (spec.ankle_shin - spec.knee_lower).angle()
	return [
		{"position": hip, "rotation": thigh_angle},
		{"position": knee, "rotation": shin_angle},
		{"position": ankle, "rotation": 0.0},
	]


## 两点之间的胶囊参数：用于受击区/腿部碰撞跟随 IK 点
static func capsule_between(a: Vector2, b: Vector2, radius: float) -> Dictionary:
	var len := a.distance_to(b)
	# 胶囊本地轴是 (0,1)（竖直向下），转到 a→b 方向要减掉本地轴的角度
	return {
		"position": (a + b) * 0.5,
		"rotation": (b - a).angle() - PI * 0.5,
		"height": maxf(len, radius * 2.0),
	}
