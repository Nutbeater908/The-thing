extends Node2D
## 一关：读取拼装算能力，清场搜刮后结算进度。关卡之间的休息处复用孵化池场景。
## 胜利才把局内收获写进 RunState；失败不改变进度，重试从本关开始。

var suspended_build: Control
var previous_process_mode: int
## 进入时锁定的身体能力快照；重试沿用同一份，不回读拼装。
var profile: SliceBodyProfile
var held: Dictionary = {}
var finished := false
var leaving := false
var won := false
var recovered := 0
var credits := 0
## 结算后的代币（含器官价值奖励），仅用于回执显示
var reward_total := 0
var reward_bonus := 0
var settled := false
## 当前关卡序号，从 1 开始
var level := 1
var run_state: Node
var nearest: Enemy
var active: Dictionary = {}
@onready var player = $Player
@onready var camera: Camera2D = $Camera2D
@onready var enemies: Node2D = $Enemies
@onready var pack: BackpackPanel = $HUD/Pack/Box/Pack
@onready var notice: Label = $HUD/Margin/Box/Notice
@onready var body_label: Label = $HUD/Margin/Box/Body

func enter_from(build: Control, body: SliceBodyProfile = null, lvl: int = 1) -> void:
	profile = body
	level = maxi(1, lvl)
	suspended_build = build
	previous_process_mode = build.process_mode
	var tree := build.get_tree()
	build.get_parent().remove_child(build)
	build.process_mode = Node.PROCESS_MODE_DISABLED
	build.hide()
	add_child(build)
	tree.root.add_child(self)
	tree.current_scene = self

func _ready() -> void:
	run_state = get_node_or_null("/root/RunState")
	for enemy in enemies.get_children():
		enemy.set_physics_process(false)
	player.died.connect(_on_death)
	player.attacked.connect(_on_attack)
	player.hurt.connect(_on_hurt)
	$HUD/Margin/Box/Row/PackToggle.pressed.connect(_toggle_pack)
	$HUD/Margin/Box/Row/Return.pressed.connect(return_to_build)
	$HUD/Result/Box/Return.pressed.connect(return_to_build)
	$HUD/Result/Box/Retry.pressed.connect(retry)
	# 能力先注入，再按关卡强化敌人：tuning 是每帧实时读取的
	if profile != null:
		player.apply_profile(profile)
		body_label.text = profile.summary_line()
		notice.text = profile.entry_notice()
	else:
		body_label.text = "身体：未读取拼装（固定演示能力）"
		notice.text = "先越过缓坡与小障碍，再靠近敌人。"
	# 拼装盘还挂在树上（只是禁用），可以直接解析肢体链
	if suspended_build != null:
		var grid = suspended_build.get_node_or_null("Margin/Root/Body/GridPanel/AssemblyGrid")
		if grid != null:
			var chains: Array = LimbChainBuilder.build_units(grid)
			if chains.is_empty():
				chains = LimbChainBuilder.build(grid)
			var layout := BodyLayout.from_grid(grid, chains)
			player.setup_limbs(chains, layout)
			var valid := 0
			var reasons: Array[String] = []
			for c in chains:
				if c.valid:
					valid += 1
				elif not c.reason.is_empty() and not reasons.has(c.reason):
					reasons.append(c.reason)
			if chains.is_empty():
				notice.text = "没有可用的肢体链：先把「脑」和「臂/爪」用骨骼线连起来。"
			elif valid == 0:
				notice.text = "肢体链 %d 条，全部无效：%s" % [chains.size(), "；".join(reasons)]
			else:
				notice.text = "肢体链 %d 条（有效 %d）：按 J 甩击 / K 突刺。" % [chains.size(), valid]
			print("[limb] chains=%d valid=%d reasons=%s" % [chains.size(), valid, str(reasons)])
			# 详细日志：每次装配进关卡都把链的构成打出来，方便定位为什么无效
			for c in chains:
				var ids: Array[String] = []
				for s in c.segments:
					ids.append(String(s.organ.id))
				print("[limb]  chain %s valid=%s bind=%s reason=%s" % [
					str(ids), str(c.valid), String(c.bind_action), c.reason])
			if chains.is_empty():
				var limbs: Array[String] = []
				for p in grid.organs():
					if p.data.limb != OrganData.Limb.NONE:
						limbs.append(String(p.data.id))
				var bones: Array[String] = []
				for l in grid.links():
					if l.type == OrganData.BONE:
						bones.append("%s.%s -> %s.%s" % [
							String(l.a.organ.data.id), String(l.a.port_uid),
							String(l.b.organ.data.id), String(l.b.port_uid)])
				print("[limb]  limb organs=%s" % str(limbs))
				print("[limb]  bone links=%s" % str(bones))
	$HUD/Margin/Box/Title.text = level_title()
	for enemy in enemies.get_children():
		enemy.apply_tier(level, player.tuning.enemy_hp_step, player.tuning.enemy_damage_step)

func total_levels() -> int:
	var total := 3
	if run_state != null:
		total = EconomyTuning.get_tuning().total_levels
	return total

func level_title() -> String:
	return "第 %d/%d 关 · 肢体测试场" % [level, total_levels()]

func _physics_process(_delta: float) -> void:
	$Camera2D.position.x = player.position.x
	if finished:
		return
	for enemy in enemies.get_children():
		if not enemy.dead and not active.has(enemy.get_instance_id()) and absf(enemy.position.x - player.position.x) < player.tuning.enemy_activation_distance:
			active[enemy.get_instance_id()] = true
			enemy.set_physics_process(true)
	var candidate: Enemy
	var distance: float = player.tuning.interact_range
	for enemy in enemies.get_children():
		if enemy.dead:
			var d: float = player.global_position.distance_to(enemy.global_position)
			if d < distance:
				candidate = enemy
				distance = d
	if nearest != candidate:
		if is_instance_valid(nearest):
			nearest.set_highlighted(false)
		nearest = candidate
		if is_instance_valid(nearest):
			nearest.set_highlighted(true)
	var defeated := 0
	for enemy in enemies.get_children():
		if enemy.dead:
			defeated += 1
	$HUD/Margin/Box/Status.text = "生命 %.0f/%.0f  |  击败 %d/%d  |  局内器官 %d  |  局内代币 %d" % [player.hp, player.tuning.max_hp, defeated, enemies.get_child_count(), pack.snapshot().size(), credits]
	if player.position.y > 1000.0:
		player.take_hit(player.tuning.max_hp, player.position + Vector2.UP)
	if $Exit.overlaps_body(player):
		try_finish()

## 镜头：人物中心永远保持屏幕正中（不做平滑，战斗中不拖影）
func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var center_y := 0.0
	if player._layout != null:
		center_y = -(player._layout.leg_drop + player._layout.bounds.size.y) * 0.5
	camera.global_position = player.global_position + Vector2(0, center_y)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	var key: int = event.physical_keycode
	if key in [KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT]:
		held[key] = event.pressed and not finished
		_update_intent()
	elif event.pressed and not finished:
		if key == KEY_SPACE:
			player.request_jump()
		elif key == KEY_J:
			# 有肢体链时 J 只甩肢体；没有肢体时才退回旧的近战判定
			if not player.has_limbs():
				player.attack()
		elif key == KEY_E:
			interact()
		elif key == KEY_H:
			player.toggle_xray()
		elif key == KEY_TAB:
			_toggle_pack()
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()

func _update_intent() -> void:
	var right := bool(held.get(KEY_D, false)) or bool(held.get(KEY_RIGHT, false))
	var left := bool(held.get(KEY_A, false)) or bool(held.get(KEY_LEFT, false))
	player.set_walk_intent(float(right) - float(left))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held.clear()
		if is_instance_valid(player):
			player.set_walk_intent(0.0)

func interact() -> bool:
	if finished or not is_instance_valid(nearest):
		return false
	if not nearest.loot.is_empty():
		var id: StringName = nearest.loot[0]
		var organ: OrganData = OrganLibrary.catalog().get(id)
		if organ == null:
			return false
		if not pack.add_organ(organ):
			notice.text = "局内胃装不下了：按 Tab 查看；掉落仍在尸体内。"
			return false
		nearest.remove_loot(id)
		recovered += 1
		notice.text = "获得 %s！按 Tab 查看局内胃，继续向右到出口。" % organ.display_name
		return true
	if not nearest.absorbed and nearest.data.absorb_credits > 0:
		nearest.absorbed = true
		credits += nearest.data.absorb_credits
		notice.text = "吸收尸体：局内代币 +%d（过关才结算）" % nearest.data.absorb_credits
		return true
	notice.text = "这具尸体已经搜刮完了。"
	return false

func try_finish() -> bool:
	if finished:
		return false
	for enemy in enemies.get_children():
		if not enemy.dead:
			notice.text = "出口未开启：先击败全部敌人。"
			return false
	if recovered == 0 or pack.is_empty():
		notice.text = "先靠近精英尸体按 E，带走至少一个器官。"
		return false
	_finish(true)
	return true

func _finish(success: bool) -> void:
	if finished:
		return
	finished = true
	won = success
	held.clear()
	player.set_walk_intent(0.0)
	player.set_physics_process(false)
	for enemy in enemies.get_children():
		enemy.set_physics_process(false)
	if success:
		_settle_success()
	$HUD/Result.show()
	if success:
		$HUD/Result/Box/Title.text = "第 %d 关完成 · 回休息处" % level
		$HUD/Result/Box/Detail.text = "带回 %d 个器官，结算 %d 代币（含身体价值奖励 %d）。\n在休息处可以拆装、修复，并把胃里的器官装上再出发。" % [pack.snapshot().size(), reward_total, reward_bonus]
	else:
		$HUD/Result/Box/Title.text = "第 %d 关失败 · 可以重试" % level
		$HUD/Result/Box/Detail.text = "本关收获丢失：局内器官 %d，代币 %d。\n进度不变，原拼装仍在孵化池。" % [pack.snapshot().size(), credits]

## 胜利结算：进度 + 代币 + 胃，一次性写进 RunState
func _settle_success() -> void:
	if settled:
		return
	settled = true
	reward_bonus = 0
	if profile != null:
		reward_bonus = int(float(profile.organ_value) * EconomyTuning.get_tuning().clear_reward_rate)
	reward_total = credits + reward_bonus
	if run_state == null:
		return
	run_state.progress = maxi(int(run_state.progress), level)
	for entry in pack.snapshot():
		run_state.backpack.append(entry)
	run_state.earn(reward_total)
	run_state.save_session()

func _on_death() -> void:
	_finish(false)

func _on_attack(hits: int) -> void:
	notice.text = "命中 %d 个敌人" % hits if hits > 0 else "挥爪未命中：靠近并面朝敌人，再按 J。"

func _on_hurt() -> void:
	notice.text = "宿主受伤！短暂无敌与击退生效。"

func _toggle_pack() -> void:
	$HUD/Pack.visible = not $HUD/Pack.visible

func retry() -> void:
	if leaving:
		return
	leaving = true
	var tree := get_tree()
	var replacement = load(scene_file_path).instantiate()
	replacement.profile = profile
	replacement.level = level
	if is_instance_valid(suspended_build):
		var build := suspended_build
		suspended_build = null
		remove_child(build)
		replacement.suspended_build = build
		replacement.previous_process_mode = previous_process_mode
		replacement.add_child(build)
	tree.root.add_child(replacement)
	tree.current_scene = replacement
	queue_free()

func return_to_build() -> void:
	if leaving:
		return
	leaving = true
	if not is_instance_valid(suspended_build):
		get_tree().change_scene_to_file("res://scenes/build/build_screen.tscn")
		return
	var tree := get_tree()
	var build := suspended_build
	suspended_build = null
	remove_child(build)
	tree.root.add_child(build)
	build.process_mode = previous_process_mode
	build.show()
	tree.current_scene = build
	if won:
		build.on_run_finished("第 %d 关完成：结算 %d 代币，带回 %d 个器官。" % [level, reward_total, pack.snapshot().size()])
	elif finished:
		build.on_run_finished("第 %d 关失败：本关收获丢失，进度未变。" % level)
	else:
		build.on_run_finished("已撤离第 %d 关：进度未变，本关收获未结算。" % level)
	queue_free()
