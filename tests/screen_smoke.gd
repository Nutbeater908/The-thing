extends SceneTree
## 新拼装屏幕的冒烟测试：能实例化、能拼装、校验与日志正常。

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load("res://scenes/assembly/assembly_screen.tscn")
	if packed == null:
		printerr("SCREEN_SMOKE FAIL scene missing")
		quit(1)
		return
	var screen: Control = packed.instantiate()
	root.add_child(screen)
	await process_frame

	var failures := 0
	if screen.palette == null or screen.palette.get_child_count() != 9:
		printerr("SCREEN_SMOKE FAIL palette = ", screen.palette.get_child_count() if screen.palette else -1)
		failures += 1

	var view: AssemblyView = screen.view
	var lib := PartsLibrary.catalog()
	view.assembly.add_root(lib[&"chassis"], Vector2.ZERO)
	var chassis_index := view.assembly.root_index()
	view.assembly.attach(lib[&"arm_standard"], chassis_index, &"right_top")
	view.assembly.attach(lib[&"leg_standard"], chassis_index, &"right_bottom")
	view.assembly.attach(lib[&"head_shell"], chassis_index, &"top")
	var head := view.assembly.parts.size() - 1
	view.assembly.attach(lib[&"cpu"], head, &"cpu")
	view.assembly.attach(lib[&"power_core"], chassis_index, &"inner_a")
	view.assembly.attach(lib[&"control_core"], chassis_index, &"inner_b")
	view.assembly.bind_tool(1, lib[&"claw_tool"])
	view.queue_redraw()
	await process_frame
	await process_frame

	if view.assembly.parts.size() != 7:
		printerr("SCREEN_SMOKE FAIL parts = ", view.assembly.parts.size())
		failures += 1
	if not AssemblyRules.all_ok(view.assembly):
		printerr("SCREEN_SMOKE FAIL rules: ", AssemblyRules.check_all(view.assembly))
		failures += 1

	# 日志与撤销：从空装配起步
	view.journal.reset({})
	view._record("测试操作")
	if view.journal.entries.size() != 1:
		printerr("SCREEN_SMOKE FAIL journal size")
		failures += 1
	view.undo()
	await process_frame
	if view.assembly.parts.size() != 0:
		printerr("SCREEN_SMOKE FAIL undo did not clear parts = ", view.assembly.parts.size())
		failures += 1
	view.redo()
	await process_frame
	if view.assembly.parts.size() != 7:
		printerr("SCREEN_SMOKE FAIL redo did not restore parts = ", view.assembly.parts.size())
		failures += 1

	print("SCREEN_SMOKE ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
