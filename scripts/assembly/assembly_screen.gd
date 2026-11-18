## 拼装屏幕：部件库 + 拼装视图 + 校验 + 操作日志（收起态一行字）。
extends Control

var view: AssemblyView
var palette: VBoxContainer
var status: Label
var journal_label: Label

var _notice_text := ""


func _ready() -> void:
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	view = AssemblyView.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.notice.connect(_on_notice)

	# 左侧部件库
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(150, 0)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(150, 360)
	panel.add_child(scroll)
	palette = VBoxContainer.new()
	palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(palette)
	_fill_palette()

	# 出发按钮
	var go := Button.new()
	go.text = "出发"
	go.pressed.connect(_on_depart)
	add_child(go)
	go.position = Vector2(12, 430)
	go.custom_minimum_size = Vector2(120, 36)

	var depth_go := Button.new()
	depth_go.name = "DepthTrial"
	depth_go.text = "纵深试验"
	depth_go.position = Vector2(12, 474)
	depth_go.custom_minimum_size = Vector2(120, 36)
	depth_go.focus_mode = Control.FOCUS_NONE
	depth_go.pressed.connect(_on_depth_trial)
	add_child(depth_go)

	# 右下操作日志（收起态）
	journal_label = Label.new()
	journal_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	journal_label.position = Vector2(12, -30)
	journal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(journal_label)

	# 右上校验
	status = Label.new()
	status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.position = Vector2(-330, 12)
	status.custom_minimum_size = Vector2(320, 0)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)

	_refresh_status()
	_refresh_journal()


## 给关卡用：当前拼装结果
## 带着当前装配进关卡
func _on_depart() -> void:
	var room = load("res://scenes/arena/playable_slice.tscn").instantiate()
	room.enter_from(self, null, 1)


func _on_depth_trial() -> void:
	if view.assembly.root_index() < 0:
		_on_notice("先装上机身，再进入纵深试验")
		return
	var room = load("res://scenes/prototypes/assembly_range.tscn").instantiate()
	room.enter_from(self)


func current_assembly() -> Assembly:
	return view.assembly


func _fill_palette() -> void:
	for part in PartsLibrary.all():
		var b := Button.new()
		b.text = "%s  %d" % [part.display_name, part.cost]
		b.pressed.connect(_pick_part.bind(part))
		palette.add_child(b)


func _pick_part(part: PartData) -> void:
	if part.is_tool_part():
		view.held_tool = part
		view.held = null
		_on_notice("拿着 %s，点机械臂装上" % part.display_name)
		return
	view.held = part
	view.held_tool = null
	view.held_rotation = 0
	_on_notice("拿着 %s" % part.display_name)
	view.queue_redraw()


func _on_notice(text: String) -> void:
	_notice_text = text
	_refresh_journal()


func _refresh_journal() -> void:
	if journal_label == null:
		return
	var line := _notice_text
	if view.journal.entries.size() > 0:
		line = view.journal.label_at(view.journal.cursor)
		if _notice_text != "":
			line += "    · " + _notice_text
	journal_label.text = line


func _refresh_status() -> void:
	if status == null:
		return
	var lines: Array[String] = []
	for c in AssemblyRules.check_all(view.assembly):
		lines.append("%s %s" % ["✔" if c["ok"] else "✘", c["label"] + "　" + c["detail"]])
	status.text = "\n".join(lines)


func _process(_delta: float) -> void:
	_refresh_status()
	_refresh_journal()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_T:
		# T 键：快速装配测试模板（机身 + 一条腿）
		_load_test_template()
		return
	if event.keycode == KEY_G:
		if event.shift_pressed:
			view.snap_grid = not view.snap_grid
			_on_notice("网格吸附：%s" % ("开" if view.snap_grid else "关"))
		else:
			view.show_grid = not view.show_grid
			_on_notice("参考线：%s" % ("开" if view.show_grid else "关"))
		view.queue_redraw()
		return
	if event.keycode == KEY_F3:
		DevFlags.show_collision = not DevFlags.show_collision
		_on_notice("碰撞显示：%s" % ("开" if DevFlags.show_collision else "关"))
		view.queue_redraw()
		return
	if event.keycode == KEY_Z and event.ctrl_pressed:
		if event.shift_pressed:
			view.redo()
		else:
			view.undo()
		_refresh_status()
		_refresh_journal()


func _load_test_template() -> void:
	var lib := PartsLibrary.catalog()
	view.assembly = Assembly.new()
	view.assembly.add_root(lib[&"chassis"], Vector2(0, 0))
	view.assembly.attach(lib[&"leg_standard"], 0, &"hip", 0)
	view.held = null
	view.zoom = 1.5
	view.pan = Vector2(300, 200)
	view.queue_redraw()
	_on_notice("已加载测试模板：机身 + 腿（按 T 重新加载）")
