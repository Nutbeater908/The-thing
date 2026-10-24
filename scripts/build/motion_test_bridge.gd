extends RefCounted
## Pure preflight: never touches economy, snapshots, grid contents, or disk.
const Spec = preload("res://scripts/labs/blueprint_walk_spec.gd")
const Walker = preload("res://scripts/labs/blueprint_walker.gd")
const CELL := 32.0

static func prepare(grid: AssemblyGrid) -> Dictionary:
	var errors: Array[String] = []
	if not grid.result().get("alive", false):
		errors.append("请先通过原有存活校验：接好寄生虫、大脑、血路和结构。")
	var spec := Spec.new()
	spec.cell_size = CELL
	var mounts: Array[Vector2] = []
	for placed in grid.organs():
		var data: OrganData = placed.data
		var entry := {"data": data, "anchor": placed.anchor, "rotation": placed.rotation}
		if not is_finite(placed.hp) or placed.hp <= 0.0:
			errors.append("%s 已损毁或 HP 无效；请在孵化池处理后再试。" % data.display_name)
		if data.limb == OrganData.Limb.CLAW:
			errors.append("当前只支持固定器官和两条向下腿；请自行移除爪后再试（不会自动修改）。")
		if data.limb == OrganData.Limb.LEG:
			var family: Resource = data.motion_test_spec
			if family == null or family.get_script() != preload("res://scripts/labs/blueprint_leg_motion.gd"):
				errors.append("%s 缺少明确腿族运动资源，不能推测挂点或替换腿。" % data.display_name)
				continue
			if family.reference_cells != data.cells or family.reference_cell_size != CELL:
				errors.append("%s 的格形/尺寸不匹配固定腿族资源；需要专用运动定义，不能拉伸。" % data.display_name)
				continue
			if placed.rotation != 0 or family.direction != Vector2.DOWN:
				errors.append("腿必须保持向下（旋转 0）；请自行旋转、重新放置并检查连接。")
			var motion: Resource = family.duplicate()
			motion.organ = data
			entry.motion = motion
			mounts.append(Vector2(placed.anchor) + motion.mount)
		spec.organs.append(entry)
	if mounts.size() != 2:
		errors.append("运动测试恰好需要两条有运动资源的向下腿。")
	if not errors.is_empty():
		return {"errors": errors}
	# Translate only: preserve every anchor, rotation, cell and relative organ offset.
	# Hips at local y=8 retain the verified controller's support-height convention.
	spec.frame_origin = (mounts[0] + mounts[1]) * 0.5 - Vector2(0, 8.0 / CELL)
	# Controller leg indices are spatial left/right, never purchase/drawing order.
	var fixed_entries: Array[Dictionary] = []
	var leg_entries: Array[Dictionary] = []
	for entry in spec.organs:
		if entry.has("motion"):
			leg_entries.append(entry)
		else:
			fixed_entries.append(entry)
	leg_entries.sort_custom(func(a, b): return a.anchor.x < b.anchor.x)
	spec.organs.assign(fixed_entries + leg_entries)
	var body := Walker.new()
	var compile_errors: Array = body.configure(spec)
	if not compile_errors.is_empty():
		body.free()
		return {"errors": ["布局不兼容：两腿需同高、挂点紧贴真实固定格下边中点，固定格需直接连通；不能靠骨骼线焊接悬空器官。详情：" + "; ".join(compile_errors)]}
	var layout: Dictionary = body.layout
	var tuning: Resource = body.tuning
	var radius: float = tuning.limb_radius + tuning.clearance
	var workspace: float = maxf(tuning.upper_length, tuning.lower_length) + radius
	for leg in layout.legs:
		var data: OrganData = spec.organs[leg.organ].data
		var reference_height: float = data.bounds(0).size.y * CELL
		if not is_equal_approx(leg.motion.upper_length + leg.motion.lower_length + tuning.foot_radius, reference_height):
			errors.append("腿族骨长与三格参考高度不一致；需要匹配的运动资源，不能单独拉长或缩短腿。")
	if layout.legs[1].mount.x - layout.legs[0].mount.x < 2.0 * workspace:
		errors.append("两髋工作区重叠：当前固定腿族要求挂点水平间距至少 %.0f 像素（至少 4 格）；请自行调整躯干和腿。" % (2.0 * workspace))
	for leg in layout.legs:
		var hip: Vector2 = leg.mount
		# Conservative swept-knee envelope; socket itself may meet its parent cell.
		var envelope := Rect2(hip + Vector2(-workspace, radius), Vector2(2.0 * workspace, tuning.upper_length + tuning.lower_length))
		for cell in layout.fixed:
			var rect := Rect2(cell.position - Vector2.ONE * CELL * 0.5, Vector2.ONE * CELL)
			if envelope.intersects(rect):
				errors.append("腿下方/膝部工作区被固定器官占用；请清空两髋下方各约 2 格宽的活动空间。")
				break
		# Use the same IK and reach predicate as live motion, including stride/crouch/tuck.
		for target in [Vector2(-6, 73), Vector2(6, 73), Vector2(-40, 73), Vector2(40, 73), Vector2(0, hip.y + tuning.jump_tuck_distance), Vector2(0, hip.y + tuning.jump_extend_distance)]:
			var foot := Vector2(hip.x + target.x, target.y)
			if not body._reachable(hip, foot):
				errors.append("骨长不足以覆盖现有控制器的站立/步幅/跳跃姿态；需要专用腿族调参，不能偷偷缩放。")
				break
	for cell in layout.fixed:
		if cell.position.y + CELL * 0.5 >= tuning.jump_landing_height - tuning.clearance:
			errors.append("固定器官过低，会在下蹲/落地时撞地；请自行抬高。")
			break
	if layout.com.x < layout.legs[0].mount.x or layout.com.x > layout.legs[1].mount.x:
		errors.append("参考重心落在两髋支撑区之外；请自行调整固定器官配重。")
	body.free()
	return {"errors": errors, "spec": spec}
