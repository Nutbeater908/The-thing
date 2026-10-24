## 器官背包：固定网格 + 异形器官拖拽。
##
## 交互逻辑参考 Dungeon Scavenger 的 InventoryPanel，但去掉了
## 堆叠 / 容器嵌套 / 装备槽 / 贴图依赖，改为纯自绘。
class_name BackpackPanel
extends Control

signal changed

const CELL := 48.0
const GAP := 4.0

@export var rows := 3
@export var cols := 3

var _items: Array[Dictionary] = []   # {organ, rotation, hp, row, col}
var _drag: Dictionary = {}
var _hover := Vector2i(-1, -1)


func _ready() -> void:
	custom_minimum_size = Vector2(
		cols * CELL + (cols - 1) * GAP,
		rows * CELL + (rows - 1) * GAP
	)
	mouse_filter = Control.MOUSE_FILTER_STOP


# ---------------------------------------------------------------- 对外接口

func items() -> Array[Dictionary]:
	return _items.duplicate()


func is_empty() -> bool:
	return _items.is_empty()


## 尝试放进第一个能放下的位置；失败返回 false
func add_organ(organ: OrganData, hp: float = -1.0, rotation: int = -1) -> bool:
	var rotations := [rotation] if rotation >= 0 else [0, 1, 2, 3]
	for rot in rotations:
		for r in rows:
			for c in cols:
				if not can_place(organ, rot, r, c):
					continue
				_items.append({
					"organ": organ,
					"rotation": rot,
					"hp": hp if hp >= 0.0 else organ.max_hp,
					"row": r,
					"col": c,
				})
				changed.emit()
				queue_redraw()
				return true
	return false


## 取出某个格子上的器官
func take_at(cell: Vector2i) -> Dictionary:
	var item := _item_at(cell)
	if item.is_empty():
		return {}
	_items.erase(item)
	changed.emit()
	queue_redraw()
	return item.duplicate()


func can_place(organ: OrganData, rotation: int, row: int, col: int) -> bool:
	for c in organ.rotated_cells(rotation):
		var cell := Vector2i(col, row) + c
		if not _in_bounds(cell):
			return false
		if not _item_at(cell).is_empty():
			return false
	return true


func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in _items:
		out.append({
			"id": item["organ"].id,
			"rotation": item["rotation"],
			"row": item["row"],
			"col": item["col"],
			"hp": item["hp"],
		})
	return out


func restore(snapshot: Array) -> void:
	_items.clear()
	var lib := OrganLibrary.catalog()
	for e in snapshot:
		var organ: OrganData = lib.get(e["id"])
		if organ == null:
			continue
		_items.append({
			"organ": organ,
			"rotation": int(e["rotation"]),
			"hp": float(e["hp"]),
			"row": int(e["row"]),
			"col": int(e["col"]),
		})
	changed.emit()
	queue_redraw()


# ---------------------------------------------------------------- 输入

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if not _drag.is_empty():
			_hover = _cell_at(event.position)
			queue_redraw()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_R and not _drag.is_empty():
		_drag["rotation"] = (int(_drag["rotation"]) + 1) % 4
		queue_redraw()
		return

	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		_begin_drag(event.position)
	else:
		_end_drag()


func _begin_drag(pos: Vector2) -> void:
	var cell := _cell_at(pos)
	var item := _item_at(cell)
	if item.is_empty():
		return

	var origin := Vector2i(item["col"], item["row"])
	_drag = item.duplicate()
	_drag["grab"] = cell - origin
	_items.erase(item)
	_hover = cell
	changed.emit()
	queue_redraw()


func _end_drag() -> void:
	if _drag.is_empty():
		return

	var anchor := _drop_anchor()
	var organ: OrganData = _drag["organ"]

	if anchor.x >= 0 and can_place(organ, _drag["rotation"], anchor.y, anchor.x):
		var placed := _drag.duplicate()
		placed["row"] = anchor.y
		placed["col"] = anchor.x
		placed.erase("grab")
		_items.append(placed)
	else:
		# 放不下就退回原位
		var back := _drag.duplicate()
		back.erase("grab")
		_items.append(back)

	_drag.clear()
	_hover = Vector2i(-1, -1)
	changed.emit()
	queue_redraw()


func _drop_anchor() -> Vector2i:
	if _hover.x < 0:
		return Vector2i(-1, -1)
	return _hover - Vector2i(_drag.get("grab", Vector2i.ZERO))


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	for r in rows:
		for c in cols:
			var rect := _cell_rect(Vector2i(c, r))
			draw_rect(rect, Color(0.14, 0.13, 0.16))
			draw_rect(rect, Color(0.28, 0.26, 0.32), false, 1.0)

	for item in _items:
		_draw_organ(item, 1.0)

	if _drag.is_empty():
		return

	var anchor := _drop_anchor()
	var ok := anchor.x >= 0 and can_place(_drag["organ"], _drag["rotation"], anchor.y, anchor.x)
	_draw_organ(_drag, 0.6, anchor if anchor.x >= 0 else Vector2i(_drag["col"], _drag["row"]))
	if anchor.x >= 0:
		var color := Color(0.2, 1.0, 0.3, 0.9) if ok else Color(1.0, 0.2, 0.15, 0.9)
		for c in _drag["organ"].rotated_cells(_drag["rotation"]):
			var cell: Vector2i = anchor + c
			if _in_bounds(cell):
				draw_rect(_cell_rect(cell).grow(1.0), color, false, 2.0)


func _draw_organ(item: Dictionary, alpha: float, anchor_override = null) -> void:
	var organ: OrganData = item["organ"]
	var rotation: int = item["rotation"]
	var anchor: Vector2i = anchor_override if anchor_override != null else Vector2i(item["col"], item["row"])

	var color := organ.color
	color.a = alpha

	for c in organ.rotated_cells(rotation):
		var cell: Vector2i = anchor + c
		if not _in_bounds(cell):
			continue
		draw_rect(_cell_rect(cell).grow(-2.0), color)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * (CELL + GAP), Vector2(CELL, CELL))


# ---------------------------------------------------------------- 内部

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows


func _cell_at(pos: Vector2) -> Vector2i:
	var cell := Vector2i(int(pos.x / (CELL + GAP)), int(pos.y / (CELL + GAP)))
	return cell if _in_bounds(cell) else Vector2i(-1, -1)


func _item_at(cell: Vector2i) -> Dictionary:
	if not _in_bounds(cell):
		return {}
	for item in _items:
		var organ: OrganData = item["organ"]
		for c in organ.rotated_cells(item["rotation"]):
			if Vector2i(item["col"], item["row"]) + c == cell:
				return item
	return {}
