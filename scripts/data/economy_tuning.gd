## 代币经济参数。改价格曲线只动这个资源。
class_name EconomyTuning
extends Resource

const PATH := "res://resources/tuning/economy.tres"

@export var start_credits := 100
@export var repair_rate := 0.6       ## 修复费用 = 价格 × 缺失比例 × 该倍率
@export var clear_reward_rate := 0.5 ## 通关奖励 = 存活器官原价 × 该倍率
@export var total_levels := 3        ## 本轮总关卡数，用于死亡时折算进度

static var _cached: EconomyTuning


static func get_tuning() -> EconomyTuning:
	if _cached == null:
		_cached = load(PATH)
	return _cached
