## 搭建界面：库存按钮 → 拼装盘 → 存活校验。
## 节点结构在 build_screen.tscn 里，脚本只做接线。
extends Control

const C_OK := Color(0.62, 0.88, 0.62)
const C_FAIL := Color(0.95, 0.55, 0.55)
const C_IDLE := Color(0.62, 0.60, 0.66)

@onready var _grid: AssemblyGrid = $Margin/Root/Body/GridPanel/AssemblyGrid
@onready var _organ_list: VBoxContainer = $Margin/Root/Body/InventoryPanel/InventoryBox/OrganList
@onready var _message: Label = $Margin/Root/Body/StatusPanel/StatusBox/Message
@onready var _physics_toggle: CheckButton = $Margin/Root/Tools/PhysicsToggle
@onready var _repair_toggle: CheckButton = $Margin/Root/Tools/RepairToggle
@onready var _repair_all: Button = $Margin/Root/Tools/RepairAll
@onready var _preset_name: LineEdit = $Margin/Root/Presets/PresetName
@onready var _preset_save: Button = $Margin/Root/Presets/PresetSave
@onready var _preset_list: OptionButton = $Margin/Root/Presets/PresetList
@onready var _preset_load: Button = $Margin/Root/Presets/PresetLoad
@onready var _backpack_list: VBoxContainer = $Margin/Root/Body/InventoryPanel/InventoryBox/BackpackList
@onready var _credits: Label = $Margin/Root/Header/Credits
@onready var _slice: Button = $Margin/Root/Body/StatusPanel/StatusBox/SliceButton
@onready var _title: Label = $Margin/Root/Header/Title

@onready var _checks: Dictionary = {
	"control": $Margin/Root/Body/StatusPanel/StatusBox/Checks/ControlCheck,
	"blood": $Margin/Root/Body/StatusPanel/StatusBox/Checks/BloodCheck,
	"structure": $Margin/Root/Body/StatusPanel/StatusBox/Checks/StructureCheck,
}

var _catalog: Dictionary = {}
var _run_state
var _pending_backpack := -1


func _ready() -> void:
	_catalog = OrganLibrary.catalog()
	_run_state = get_node_or_null("/root/RunState")

	# 器官列表按资源目录动态生成：新增器官/骨骼不用改场景
	for button in _organ_list.get_children():
		if button is Button:
			button.queue_free()
	for data in OrganLibrary.all():
		var btn := Button.new()
		btn.text = data.display_name
		btn.custom_minimum_size = Vector2(0, 40)
		btn.set_meta("organ_id", data.id)
		btn.pressed.connect(_on_organ_pressed.bind(btn))
		_organ_list.add_child(btn)

	_grid.validation_changed.connect(_on_validation_changed)
	_grid.layout_changed.connect(_on_layout_changed)
	_grid.organ_placed.connect(_on_organ_placed)
	_grid.notice.connect(_on_notice)
	_physics_toggle.toggled.connect(_on_physics_toggled)
	_repair_toggle.toggled.connect(_on_repair_toggled)
	_repair_all.pressed.connect(_on_repair_all)
	_preset_save.pressed.connect(_on_preset_save)
	_preset_load.pressed.connect(_on_preset_load)
	_slice.pressed.connect(_on_slice)
	_make_sample_button()

	if _run_state != null:
		_grid.economy = _run_state
		if not _run_state.is_empty():
			_run_state.restore_to_grid(_grid)
		if _run_state.migrated:
			_on_notice("存档已升级到新的器官格形：旧拼装已清空，代币、胃和进度保留。请重新拼装身体。")

	_refresh_credits()
	_refresh_presets()
	_refresh_backpack()
	_refresh_level_state()
	_on_validation_changed(_grid.result())


func _on_organ_pressed(button: Button) -> void:
	var id: StringName = button.get_meta("organ_id", &"")
	if _catalog.has(id):
		_pending_backpack = -1
		_grid.free_next_placement = false
		_grid.set_selected(_catalog[id])


func _refresh_backpack() -> void:
	for child in _backpack_list.get_children():
		child.queue_free()

	if _run_state == null:
		return

	if _run_state.backpack.is_empty():
		var empty := Label.new()
		empty.text = "空"
		empty.modulate = Color(0.55, 0.53, 0.6)
		_backpack_list.add_child(empty)
		return

	for i in _run_state.backpack.size():
		var entry: Dictionary = _run_state.backpack[i]
		var organ: OrganData = _catalog.get(entry["id"])
		if organ == null:
			continue
		var btn := Button.new()
		btn.text = "%s（%d 格）" % [organ.display_name, organ.cells.size()]
		btn.pressed.connect(_on_backpack_pressed.bind(i))
		_backpack_list.add_child(btn)


func _on_backpack_pressed(index: int) -> void:
	if _run_state == null or index >= _run_state.backpack.size():
		return
	var organ: OrganData = _catalog.get(_run_state.backpack[index]["id"])
	if organ == null:
		return
	_pending_backpack = index
	# 已经带回来的器官不再收一次钱
	_grid.free_next_placement = true
	_grid.set_selected(organ)
	_on_notice("从胃里取出 %s，点击网格放置（不再收费）" % organ.display_name)


## 从胃里来的器官落位后，从胃中移除
func _on_organ_placed(_organ: OrganData) -> void:
	if _pending_backpack < 0 or _run_state == null:
		return
	if _pending_backpack >= _run_state.backpack.size():
		_pending_backpack = -1
		return
	_run_state.backpack.remove_at(_pending_backpack)
	_pending_backpack = -1
	_refresh_backpack()
	_run_state.save_session()


func _on_validation_changed(result: Dictionary) -> void:
	_message.text = result.get("message", "")
	_slice.disabled = not result.get("alive", false)

	var by_id := {}
	for c in result.get("checks", []):
		by_id[c["id"]] = c

	for id in _checks:
		var label: Label = _checks[id]
		if not by_id.has(id):
			label.text = ""
			label.modulate = C_IDLE
			continue
		var c: Dictionary = by_id[id]
		label.text = "%s %s\n    %s" % ["✓" if c["ok"] else "✗", c["label"], c["detail"]]
		label.modulate = C_OK if c["ok"] else C_FAIL


func _on_physics_toggled(on: bool) -> void:
	_grid.set_physics_preview(on)


func _on_repair_toggled(on: bool) -> void:
	_grid.set_repair_mode(on)


func _on_repair_all() -> void:
	_grid.repair_all()


func _on_notice(text: String) -> void:
	_message.text = text


## 拼装变化时同步存档，下次启动自动恢复
func _on_layout_changed() -> void:
	if _run_state != null:
		_run_state.save_from_grid(_grid)
		_run_state.save_session()
	_refresh_credits()


func _refresh_credits() -> void:
	if _run_state == null:
		_credits.text = ""
		return
	var total := EconomyTuning.get_tuning().total_levels
	var level := mini(_run_state.progress + 1, total)
	_credits.text = "代币 %d　·　第 %d/%d 关　·　局外 %d" % [
		_run_state.credits, level, total, _run_state.meta_credits,
	]


func _refresh_presets() -> void:
	_preset_list.clear()
	if _run_state == null:
		return
	for name in _run_state.preset_names():
		_preset_list.add_item(name)


func _on_preset_save() -> void:
	if _run_state == null:
		return
	_run_state.save_from_grid(_grid)
	_run_state.save_preset(_preset_name.text)
	_refresh_presets()
	_on_notice("已保存方案：%s" % _preset_name.text.strip_edges())


func _on_preset_load() -> void:
	if _run_state == null or _preset_list.item_count == 0:
		return
	var name := _preset_list.get_item_text(_preset_list.selected)
	if not _run_state.load_preset(name):
		return
	_grid.clear_all()
	_run_state.restore_to_grid(_grid)
	_on_layout_changed()
	_on_notice("已加载方案：%s" % name)


## 拼装驱动的关卡循环：读取当前拼装，进入第 progress+1 关。
func _on_slice() -> void:
	if _run_state != null and _run_state.is_run_complete():
		_start_new_run()
		return
	var result: Dictionary = _grid.result()
	if not bool(result.get("alive", false)):
		_on_notice("无法出发：%s" % str(result.get("message", "构造未存活")))
		return
	var body := SliceBodyProfile.from_grid(_grid)
	if not body.supported():
		_on_notice("无法出发：身体没有朝下的支撑腿，横版里无法行走。")
		return
	var lvl := 1
	if _run_state != null:
		lvl = _run_state.progress + 1
	var room := preload("res://scenes/arena/playable_slice.tscn").instantiate()
	room.enter_from(self, body, lvl)


## 一键生成一套能通过全部校验的示例身体，用来测各种功能
func _make_sample_button() -> void:
	var tools := $Margin/Root/Tools
	var btn := Button.new()
	btn.name = "SampleBody"
	btn.text = "示例身体"
	btn.pressed.connect(_build_sample_body)
	tools.add_child(btn)


func _build_sample_body() -> void:
	_grid.clear_all()
	var lib := OrganLibrary.catalog()
	# 机身（骨架的根，4×6）：右侧上下两个接口
	_grid.place(Vector2i(0, 0), lib[&"torso"], 0, true)
	# 头部外壳 + 处理器，压在机身上方
	_grid.place(Vector2i(0, -3), lib[&"skull"], 0, true)
	_grid.place(Vector2i(0, -3), lib[&"brain"], 0, true)
	# 电源核心：压在机身内部
	_grid.place(Vector2i(0, 1), lib[&"heart"], 0, true)
	# 主控芯片：压在机身内部
	_grid.place(Vector2i(2, 1), lib[&"parasite"], 0, true)
	# 肢体：插进机身右侧的上/下接口（接口在机身内部一格）
	_grid.place(Vector2i(3, 1), lib[&"arm_standard"], 0, true)
	_grid.place(Vector2i(3, 4), lib[&"leg_standard"], 0, true)
	# 工具：绑定到机械臂的工具口
	var arm_placed = _grid.organ_at(Vector2i(3, 1))
	if arm_placed != null:
		arm_placed.tool = lib.get(&"claw_tool")
	# 连线：信号 主控 → 处理器；能源 电源 → 处理器
	_try_link(&"parasite", &"nerve", &"brain", &"nerve_in", OrganData.NERVE)
	_try_link(&"heart", &"blood", &"brain", &"blood", OrganData.BLOOD)
	_on_notice("已生成示例机体：机身 + 头部外壳 + 处理器 + 电源核心 + 主控芯片 + 机械臂 + 机械腿")


## 按器官 id 找实例并连一条线
func _try_link(a_id: StringName, a_uid: StringName, b_id: StringName, b_uid: StringName, type: int) -> void:
	var a = null
	var b = null
	for p in _grid.organs():
		if p.data.id == a_id and a == null:
			a = p
		if p.data.id == b_id and b == null:
			b = p
	if a == null or b == null:
		return
	var ea := AssemblyGrid.Endpoint.new()
	ea.organ = a
	ea.port_uid = a_uid
	ea.type = type
	var eb := AssemblyGrid.Endpoint.new()
	eb.organ = b
	eb.port_uid = b_uid
	eb.type = type
	_grid._try_link(ea, eb)
func _refresh_level_state() -> void:
	if _run_state == null:
		_slice.text = "出发"
		_title.text = "装配车间 · 机体组装"
		return
	var total := EconomyTuning.get_tuning().total_levels
	if _run_state.is_run_complete():
		_slice.text = "本轮通关 · 开始新一轮"
		_title.text = "本轮通关 · 三层已清理"
	elif _run_state.progress <= 0:
		_slice.text = "出发 · 第 1/%d 关" % total
		_title.text = "装配车间 · 机体组装"
	else:
		_slice.text = "出发 · 第 %d/%d 关" % [_run_state.progress + 1, total]
		_title.text = "整备站 · 第 %d 关后" % _run_state.progress


## 关卡回执：刷新进度、代币、胃和按钮状态
func on_run_finished(text: String) -> void:
	_refresh_level_state()
	_refresh_credits()
	_refresh_backpack()
	if _run_state != null and _run_state.is_run_complete():
		text += " 本轮三关已通关。"
	_on_notice(text)


## 通关后开新一轮：清空本轮拼装与胃，保留局外代币
func _start_new_run() -> void:
	if _run_state == null:
		return
	_run_state.reset_run()
	_run_state.save_session()
	_grid.clear_all()
	_pending_backpack = -1
	_refresh_backpack()
	_refresh_level_state()
	_refresh_credits()
	_on_notice("新一轮开始：拼装盘已清空，局外代币保留。摆好身体再出发。")
