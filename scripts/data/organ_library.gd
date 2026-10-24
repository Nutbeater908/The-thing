## 器官图鉴：从 res://resources/organs/ 加载所有器官资源。
##
## 新增器官 = 在目录里放一个 OrganData 类型的 .tres，不需要改代码。
class_name OrganLibrary
extends RefCounted

const ORGAN_DIR := "res://resources/organs"


static func catalog() -> Dictionary:
	var out := {}
	for d in all():
		out[d.id] = d
	return out


static func all() -> Array[OrganData]:
	var out: Array[OrganData] = []
	var dir := DirAccess.open(ORGAN_DIR)
	if dir == null:
		push_error("器官目录不存在：%s" % ORGAN_DIR)
		return out

	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".tres"):
			var d := load(ORGAN_DIR.path_join(file)) as OrganData
			if d != null:
				out.append(d)
			else:
				push_warning("不是有效的器官资源：%s" % file)
		file = dir.get_next()
	dir.list_dir_end()

	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out
