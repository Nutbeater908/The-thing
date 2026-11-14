## 存档 v1：部件 + 树关系。带版本号，方便以后迁移。
class_name Blueprint
extends RefCounted

const VERSION := 1


static func to_dict(a: Assembly) -> Dictionary:
	var out: Array = []
	for p in a.parts:
		out.append({
			"id": String(p.data.id),
			"pos": [p.position.x, p.position.y],
			"rot": p.rotation,
			"hp": p.hp,
			"parent": p.parent,
			"socket": String(p.parent_socket),
			"tool": String(p.tool.id) if p.tool != null else "",
		})
	return {"v": VERSION, "parts": out}


static func from_dict(dict: Dictionary, library: Dictionary) -> Assembly:
	var a := Assembly.new()
	if int(dict.get("v", 0)) != VERSION:
		return a
	for entry in dict.get("parts", []):
		var data: PartData = library.get(StringName(entry.get("id", "")))
		if data == null:
			continue
		var parent := int(entry.get("parent", -1))
		var pos := Vector2(float(entry["pos"][0]), float(entry["pos"][1]))
		var rotation := int(entry.get("rot", 0))
		if parent < 0:
			a.add_root(data, pos)
		else:
			a.attach(data, parent, StringName(entry.get("socket", "")), rotation)
		var p := a.parts[a.parts.size() - 1]
		p.position = pos
		p.hp = float(entry.get("hp", data.max_hp))
		var tid := String(entry.get("tool", ""))
		if tid != "":
			p.tool = library.get(StringName(tid))
	return a
