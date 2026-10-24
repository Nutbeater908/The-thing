## 进度折算与通关判定自检。
##   godot --headless --path <项目> --script res://tests/progress_check.gd
extends SceneTree

var _failed := 0


func _initialize() -> void:
	var total := EconomyTuning.get_tuning().total_levels
	var rs = load("res://scripts/run/run_state.gd").new()

	# 第一关就死：进度 0 → 没有局外收益
	rs.credits = 100
	rs.progress = 0
	_expect("第一关死亡收益", rs.bank_progress(), 0)
	_expect("局外代币", rs.meta_credits, 0)

	# 通过两关后死亡：2/3 折算
	rs.meta_credits = 0
	rs.credits = 90
	rs.progress = 2
	_expect("两关进度收益", rs.bank_progress(), 60)   # floor(90 * 2/3)
	_expect("局外累计", rs.meta_credits, 60)

	# 通关：100%
	rs.meta_credits = 0
	rs.credits = 50
	rs.progress = total
	_expect("通关收益", rs.bank_progress(), 50)

	# 通关判定
	_expect("已通关", rs.is_run_complete(), true)
	rs.progress = total - 1
	_expect("未通关", rs.is_run_complete(), false)

	rs.free()

	print("")
	print("全部通过" if _failed == 0 else "失败 %d 项" % _failed)
	quit(1 if _failed > 0 else 0)


func _expect(title: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s %-22s 实际=%s 期望=%s" % ["✓" if ok else "✗", title, actual, expected])
