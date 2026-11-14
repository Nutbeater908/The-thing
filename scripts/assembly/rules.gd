## 校验规则。每条规则一个函数，返回 {id, label, ok, detail}。
## 加规则 = 加一个函数 + 在 default_rules() 里登记一行。
class_name AssemblyRules
extends RefCounted


static func default_rules() -> Array[Callable]:
	return [has_root, connected, control_source, power_balance]


static func check_all(a: Assembly) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rule in default_rules():
		out.append(rule.call(a))
	return out


static func all_ok(a: Assembly) -> bool:
	for c in check_all(a):
		if not c["ok"]:
			return false
	return true


# ---------------------------------------------------------------- 规则

## 有且只有一个根部件
static func has_root(a: Assembly) -> Dictionary:
	var n := a.count_of(func(p): return p.data.is_root)
	return {
		"id": "root",
		"label": "结构",
		"ok": n == 1,
		"detail": "缺少机身" if n == 0 else ("机身只能有一个" if n > 1 else "机身已就位"),
	}


## 每个部件都能沿父链走到根
static func connected(a: Assembly) -> Dictionary:
	if a.parts.is_empty():
		return {"id": "connect", "label": "连接", "ok": false, "detail": "还没有部件"}
	var root := a.root_index()
	if root < 0:
		return {"id": "connect", "label": "连接", "ok": false, "detail": "没有根部件"}
	var loose := 0
	for i in a.parts.size():
		if i == root:
			continue
		var cur := a.parts[i].parent
		var guard := 0
		while cur >= 0 and cur != root and guard <= a.parts.size():
			cur = a.parts[cur].parent
			guard += 1
		if cur != root:
			loose += 1
	return {
		"id": "connect",
		"label": "连接",
		"ok": loose == 0,
		"detail": "%d 个部件没接上" % loose if loose > 0 else "全部接通",
	}


## 有且只有一个控制源
static func control_source(a: Assembly) -> Dictionary:
	var n := a.count_of(func(p): return p.data.is_control_source)
	return {
		"id": "control",
		"label": "控制",
		"ok": n == 1,
		"detail": "缺少主控" if n == 0 else ("主控只能有一个" if n > 1 else "主控已接入"),
	}


## 供能覆盖耗能
static func power_balance(a: Assembly) -> Dictionary:
	var supply := 0.0
	var demand := 0.0
	for p in a.parts:
		if p.data.power >= 0.0:
			supply += p.data.power
		else:
			demand -= p.data.power
	return {
		"id": "power",
		"label": "能源",
		"ok": supply >= demand,
		"detail": "供 %.0f / 耗 %.0f" % [supply, demand],
	}
