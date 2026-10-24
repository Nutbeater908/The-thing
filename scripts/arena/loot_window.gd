## 搜刮界面：左侧胃（背包），右侧尸体掉落。
##
## 打开时暂停游戏，关闭时写回 RunState.backpack。
class_name LootWindow
extends CanvasLayer

signal closed

var corpse: Enemy

var _pack: BackpackPanel
var _loot_list: VBoxContainer
var _hint: Label
var _run_state


func setup(p_corpse: Enemy) -> void:
	corpse = p_corpse
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_state = get_node_or_null("/root/RunState")
	_build()
	get_tree().paused = true


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 380)
	center.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)

	# 左：胃
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	row.add_child(left)

	var gut_title := Label.new()
	gut_title.text = "胃"
	left.add_child(gut_title)

	_pack = BackpackPanel.new()
	left.add_child(_pack)
	if _run_state != null:
		_pack.restore(_run_state.backpack)
	_pack.changed.connect(_save_backpack)

	# 右：尸体
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	var corpse_title := Label.new()
	corpse_title.text = "尸体"
	right.add_child(corpse_title)

	_loot_list = VBoxContainer.new()
	_loot_list.add_theme_constant_override("separation", 6)
	right.add_child(_loot_list)

	_hint = Label.new()
	_hint.modulate = Color(0.9, 0.75, 0.4)
	right.add_child(_hint)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)

	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(_close)
	right.add_child(close)

	_refresh_loot()


func _refresh_loot() -> void:
	for child in _loot_list.get_children():
		child.queue_free()

	if corpse == null or not is_instance_valid(corpse):
		return

	# 小怪：吸收换代币
	if corpse.data != null and corpse.data.absorb_credits > 0 and not corpse.absorbed:
		var absorb := Button.new()
		absorb.text = "吸收（+%d 代币）" % corpse.data.absorb_credits
		absorb.pressed.connect(_on_absorb)
		_loot_list.add_child(absorb)

	# 精英：逐个器官
	var lib := OrganLibrary.catalog()
	for id in corpse.loot:
		var organ: OrganData = lib.get(id)
		if organ == null:
			continue
		var btn := Button.new()
		btn.text = "%s（%d 格）" % [organ.display_name, organ.cells.size()]
		btn.pressed.connect(_on_take.bind(id))
		_loot_list.add_child(btn)

	if corpse.loot.is_empty() and (corpse.data == null or corpse.data.absorb_credits <= 0):
		var empty := Label.new()
		empty.text = "什么都没有"
		empty.modulate = Color(0.6, 0.6, 0.6)
		_loot_list.add_child(empty)


func _on_take(id: StringName) -> void:
	var lib := OrganLibrary.catalog()
	var organ: OrganData = lib.get(id)
	if organ == null:
		return

	if not _pack.add_organ(organ):
		_hint.text = "胃里放不下了"
		return

	_hint.text = "吞下 %s" % organ.display_name
	corpse.remove_loot(id)
	_refresh_loot()


func _on_absorb() -> void:
	if corpse == null or not is_instance_valid(corpse) or corpse.absorbed:
		return
	corpse.absorbed = true
	if _run_state != null:
		_run_state.earn(corpse.data.absorb_credits)
		_run_state.save_session()
	_hint.text = "吸收 +%d 代币" % corpse.data.absorb_credits
	_refresh_loot()


func _save_backpack() -> void:
	if _run_state != null and _pack != null:
		_run_state.backpack = _pack.snapshot()
		_run_state.save_session()


func _close() -> void:
	_save_backpack()
	get_tree().paused = false
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			_close()
			get_viewport().set_input_as_handled()
