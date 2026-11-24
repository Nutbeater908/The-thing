## Assembly 和 AssemblyBridge.Body 都提供 parts/data/tool；能力结果共用此汇总。
## 不修改资源、存档或装配本身；多部件选择一份有效配置，不叠加。
extends RefCounted

static func evaluate(body) -> Dictionary:
	var mass := 0.0
	var balance := 0.0
	var candidates: Array[Resource] = []
	for part in body.parts:
		mass += part.data.mass
		balance += part.data.power
		if part.data.air_mobility != null:
			candidates.append(part.data.air_mobility)
		if part.tool != null:
			mass += part.tool.mass
			balance += part.tool.power
			if part.tool.air_mobility != null:
				candidates.append(part.tool.air_mobility)
	var result := {"installed": not candidates.is_empty(), "active": false, "mass": mass, "balance": balance, "acceleration": 0.0, "speed_limit": 0.0, "reason": "未安装空中机动部件"}
	if candidates.is_empty():
		return result
	if balance < -0.001:
		result.reason = "供能不足：空中机动无效"
		return result
	for spec in candidates:
		if mass > spec.supported_mass or spec.acceleration <= 0.0 or spec.speed_limit <= 0.0:
			continue
		if not result.active or spec.acceleration > result.acceleration:
			result.active = true
			result.acceleration = spec.acceleration
			result.speed_limit = spec.speed_limit
	if result.active:
		result.reason = "空中机动有效：加速度 %.0f / 主动速度上限 %.0f / 总质量 %.0f" % [result.acceleration, result.speed_limit, mass]
	else:
		result.reason = "负载超出支持范围或部件参数无效：空中机动无效（总质量 %.0f）" % mass
	return result
