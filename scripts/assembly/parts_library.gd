## 部件库：扫描 resources/parts 下的 PartData。
class_name PartsLibrary
extends RefCounted

const PATH := "res://resources/parts"

static var _cache: Dictionary
static var _ordered: Array[PartData] = []


static func all() -> Array[PartData]:
	if _ordered.is_empty():
		_scan()
	return _ordered


static func catalog() -> Dictionary:
	if _cache.is_empty():
		_scan()
	return _cache


static func get_part(id: StringName) -> PartData:
	return catalog().get(id)


static func _scan() -> void:
	_cache = {}
	_ordered = []
	var dir := DirAccess.open(PATH)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var res := load("%s/%s" % [PATH, file])
		if res is PartData:
			for issue in res.audit():
				push_error("部件数据异常 %s: %s" % [file, issue])
			_cache[res.id] = res
			_ordered.append(res)
	_ordered.sort_custom(func(a, b): return String(a.display_name) < String(b.display_name))
