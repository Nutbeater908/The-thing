## 跨场景状态：代币、进度，以及孵化池与关卡之间传递的器官蓝图。
##
## 每项器官：{"id": StringName, "rotation": int, "anchor": Vector2i, "hp": float}
extends Node

const SESSION_PATH := "user://session.save"
const PRESET_PATH := "user://presets.save"

## 本轮代币（死亡时不带走）
var credits := EconomyTuning.get_tuning().start_credits

## 局外代币（死亡时按进度折算后累积）
var meta_credits := 0

## 已通过的关卡数
var progress := 0

var organs: Array[Dictionary] = []

## 拉线快照，格式见 AssemblyGrid.link_snapshot()
var links: Array[Dictionary] = []

## 胃（背包）快照，格式见 BackpackPanel.snapshot()
var backpack: Array[Dictionary] = []


func reset_run() -> void:
	credits = EconomyTuning.get_tuning().start_credits
	progress = 0
	organs.clear()
	links.clear()
	backpack.clear()


func save_from_grid(grid) -> void:
	organs.clear()
	for p in grid.organs():
		organs.append({
			"id": p.data.id,
			"rotation": p.rotation,
			"anchor": p.anchor,
			"hp": p.hp,
		})
	links = grid.link_snapshot()


## 把上一轮的器官（含损伤）恢复到拼装盘上
func restore_to_grid(grid) -> void:
	# 用快照遍历：恢复过程中 layout_changed 回调会改写 organs
	var organ_snapshot := organs.duplicate(true)
	var link_snapshot_copy := links.duplicate(true)
	var lib := OrganLibrary.catalog()

	for entry in organ_snapshot:
		var data: OrganData = lib.get(entry["id"])
		if data == null:
			continue
		if not grid.place(entry["anchor"], data, entry["rotation"], true):
			continue
		var placed = grid.organ_at(entry["anchor"])
		if placed != null:
			placed.hp = float(entry.get("hp", data.max_hp))

	grid.restore_links(link_snapshot_copy)


func can_afford(amount: int) -> bool:
	return credits >= amount


func spend(amount: int) -> bool:
	if credits < amount:
		return false
	credits -= amount
	return true


func earn(amount: int) -> void:
	credits += amount


## 死亡 / 本轮结束时按已通过进度折算局外代币，返回获得量
func bank_progress() -> int:
	var total := maxi(1, EconomyTuning.get_tuning().total_levels)
	var gain := floori(credits * float(progress) / float(total))
	meta_credits += gain
	return gain


func is_run_complete() -> bool:
	return progress >= EconomyTuning.get_tuning().total_levels


# ---------------------------------------------------------------- 会话存档

func _ready() -> void:
	load_session()


## 把当前拼装、代币和胃写入 user://，下次启动自动恢复
func save_session() -> void:
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_var({
		"organs": organs,
		"links": links,
		"backpack": backpack,
		"credits": credits,
		"meta_credits": meta_credits,
		"progress": progress,
	})
	f.close()


func load_session() -> bool:
	if not FileAccess.file_exists(SESSION_PATH):
		return false

	var f := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = f.get_var()
	f.close()

	if typeof(data) != TYPE_DICTIONARY:
		return false

	organs.clear()
	for e in data.get("organs", []):
		organs.append(e)
	links.clear()
	for e in data.get("links", []):
		links.append(e)
	backpack.clear()
	for e in data.get("backpack", []):
		backpack.append(e)

	credits = int(data.get("credits", credits))
	meta_credits = int(data.get("meta_credits", 0))
	progress = int(data.get("progress", 0))
	return true


# ---------------------------------------------------------------- 方案

## 把当前拼装存成命名方案
func save_preset(name: String) -> void:
	if name.strip_edges() == "":
		return
	var all := _load_presets()
	all[name.strip_edges()] = {
		"organs": organs.duplicate(true),
		"links": links.duplicate(true),
	}
	_write_presets(all)


## 载入命名方案；调用后需要再 restore_to_grid()
func load_preset(name: String) -> bool:
	var all := _load_presets()
	if not all.has(name):
		return false
	var data: Dictionary = all[name]
	organs.clear()
	for e in data.get("organs", []):
		organs.append(e)
	links.clear()
	for e in data.get("links", []):
		links.append(e)
	return true


func preset_names() -> Array[String]:
	var out: Array[String] = []
	for key in _load_presets().keys():
		out.append(String(key))
	out.sort()
	return out


func delete_preset(name: String) -> void:
	var all := _load_presets()
	if all.erase(name):
		_write_presets(all)


func _load_presets() -> Dictionary:
	if not FileAccess.file_exists(PRESET_PATH):
		return {}
	var f := FileAccess.open(PRESET_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var()
	f.close()
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _write_presets(all: Dictionary) -> void:
	var f := FileAccess.open(PRESET_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_var(all)
	f.close()


func clear_session() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	organs.clear()
	links.clear()
	backpack.clear()
	credits = EconomyTuning.get_tuning().start_credits
	meta_credits = 0
	progress = 0


func is_empty() -> bool:
	return organs.is_empty()
