## 操作日志 = 撤销栈。一条记录 = 一步操作 + 那一步之后的状态快照。
class_name Journal
extends RefCounted

class Entry:
	var label: String
	var snapshot: Dictionary

var entries: Array[Entry] = []
## 当前处于第几条之后（0 = 基线状态）
var cursor := 0
## 第 0 条之前的状态（空装配）
var base: Dictionary = {}
const LIMIT := 100


## 设一个基线（比如空装配），之后撤销最远回到这里
func reset(initial: Dictionary) -> void:
	base = initial.duplicate(true)
	entries.clear()
	cursor = 0


## 记一步。会丢掉游标之后的重做分支
func record(label: String, snapshot: Dictionary) -> void:
	if entries.size() > cursor:
		entries.resize(cursor)
	entries.append(_make(label, snapshot))
	if entries.size() > LIMIT:
		entries.remove_at(0)
	cursor = entries.size()


func can_undo() -> bool:
	return cursor > 0


func can_redo() -> bool:
	return cursor < entries.size()


## 回到上一步之前，返回那之前的快照（由调用方恢复）
func undo(current: Dictionary) -> Dictionary:
	if not can_undo():
		return {}
	cursor -= 1
	return snapshot_at(cursor)


func redo() -> Dictionary:
	if not can_redo():
		return {}
	cursor += 1
	return snapshot_at(cursor)


## 跳到第 index 条之后（0 = 基线）
func jump(index: int) -> Dictionary:
	var target := clampi(index, 0, entries.size())
	if target == cursor:
		return {}
	cursor = target
	return snapshot_at(cursor)


## cursor 处的快照：0 表示基线，否则是第 cursor 条之后
func snapshot_at(step: int) -> Dictionary:
	if step <= 0:
		return base.duplicate(true)
	return entries[step - 1].snapshot.duplicate(true)


## 供 UI 显示：第几行显示什么
func label_at(index: int) -> String:
	if index < 1 or index > entries.size():
		return ""
	return "%d：%s" % [index, entries[index - 1].label]


func _make(label: String, snapshot: Dictionary) -> Entry:
	var e := Entry.new()
	e.label = label
	e.snapshot = snapshot.duplicate(true)
	return e
