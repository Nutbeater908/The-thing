## 搭建界面：库存按钮 → 拼装盘 → 存活校验。
## 节点结构在 build_screen.tscn 里，脚本只做接线。
extends Control

const C_OK := Color(0.62, 0.88, 0.62)
const C_FAIL := Color(0.95, 0.55, 0.55)
const C_IDLE := Color(0.62, 0.60, 0.66)

@onready var _grid: AssemblyGrid = $Margin/Root/Body/GridPanel/AssemblyGrid
@onready var _organ_list: VBoxContainer = $Margin/Root/Body/InventoryPanel/InventoryBox/OrganList
@onready var _message: Label = $Margin/Root/Body/StatusPanel/StatusBox/Message
@onready var _launch: Button = $Margin/Root/Body/StatusPanel/StatusBox/LaunchButton
@onready var _physics_toggle: CheckButton = $Margin/Root/Tools/PhysicsToggle
@onready var _repair_toggle: CheckButton = $Margin/Root/Tools/RepairToggle
@onready var _repair_all: Button = $Margin/Root/Tools/RepairAll
@onready var _preset_name: LineEdit = $Margin/Root/Presets/PresetName
@onready var _preset_save: Button = $Margin/Root/Presets/PresetSave
@onready var _preset_list: OptionButton = $Margin/Root/Presets/PresetList
@onready var _preset_load: Button = $Margin/Root/Presets/PresetLoad
@onready var _backpack_list: VBoxContainer = $Margin/Root/Body/InventoryPanel/InventoryBox/BackpackList
@onready var _credits: Label = $Margin/Root/Header/Credits

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

	for button in _organ_list.get_children():
		if button is Button:
			button.pressed.connect(_on_organ_pressed.bind(button))

	_grid.validation_changed.connect(_on_validation_changed)
	_grid.layout_changed.connect(_on_layout_changed)
	_grid.organ_placed.connect(_on_organ_placed)
	_grid.notice.connect(_on_notice)
	_physics_toggle.toggled.connect(_on_physics_toggled)
	_repair_toggle.toggled.connect(_on_repair_toggled)
	_repair_all.pressed.connect(_on_repair_all)
	_preset_save.pressed.connect(_on_preset_save)
	_preset_load.pressed.connect(_on_preset_load)
	_launch.pressed.connect(_on_launch)
	$Margin/Root/Body/StatusPanel/StatusBox/MotionTestButton.pressed.connect(_on_motion_test)

	if _run_state != null:
		_grid.economy = _run_state
		if not _run_state.is_empty():
			_run_state.restore_to_grid(_grid)

	_refresh_credits()
	_refresh_presets()
	_refresh_backpack()
	_on_validation_changed(_grid.result())


func _on_organ_pressed(button: Button) -> void:
	var id: StringName = button.get_meta("organ_id", &"")
	if _catalog.has(id):
		_pending_backpack = -1
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
	_grid.set_selected(organ)
	_on_notice("从胃里取出 %s，点击网格放置" % organ.display_name)


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
	_launch.disabled = not result.get("alive", false)

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


## Separate temporary route: never saves, rebuilds, charges, heals or awards anything.
func _on_motion_test() -> void:
	var prepared := preload("res://scripts/build/motion_test_bridge.gd").prepare(_grid)
	if not prepared.errors.is_empty():
		$MotionTestError.dialog_text = "无法进入运动测试（原拼装未修改）：\n\n" + "\n".join(prepared.errors)
		$MotionTestError.popup_centered()
		return
	var room := preload("res://scenes/build/motion_test_room.tscn").instantiate()
	var errors: Array = room.prepare(prepared.spec)
	if not errors.is_empty():
		room.free()
		$MotionTestError.dialog_text = "运动资源创建失败；原拼装未修改：\n" + "; ".join(errors)
		$MotionTestError.popup_centered()
		return
	room.enter_from(self)


func _on_launch() -> void:
	if _run_state != null:
		_run_state.save_from_grid(_grid)
	get_tree().change_scene_to_file("res://scenes/arena/arena.tscn")
