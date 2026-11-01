extends "res://tests/procedural_walk_check.gd"
## Isolated-only: fake RunState uses real snapshot methods, but overrides ALL disk hooks.
const Bridge = preload("res://scripts/build/motion_test_bridge.gd")
class MemoryState extends "res://scripts/run/run_state.gd":
	var saves := 0
	func _ready() -> void:
		pass
	func save_session() -> void:
		saves += 1
	func load_session() -> bool:
		return false
	func preset_names() -> Array[String]:
		return []

func state_bytes(state) -> PackedByteArray:
	return var_to_bytes({"credits": state.credits, "meta": state.meta_credits, "progress": state.progress, "backpack": state.backpack, "organs": state.organs, "links": state.links})

func grid_bytes(grid: AssemblyGrid) -> PackedByteArray:
	var entries: Array[Dictionary] = []
	for p in grid.organs():
		entries.append({"data": p.data.resource_path, "anchor": p.anchor, "rotation": p.rotation, "hp": p.hp, "cells": p.cells})
	return var_to_bytes({"organs": entries, "links": grid.link_snapshot()})

func link(grid: AssemblyGrid, a, auid: StringName, b, buid: StringName, kind: int) -> void:
	var from := AssemblyGrid.Endpoint.new()
	from.organ = a
	from.port_uid = auid
	from.type = kind
	var to := AssemblyGrid.Endpoint.new()
	to.organ = b
	to.port_uid = buid
	to.type = kind
	check(grid._try_link(from, to), "fixture link accepted")

func _run() -> void:
	check(root.get_child_count() == 0, "isolated no real autoload")
	var state := MemoryState.new()
	state.name = "RunState"
	state.credits = 777
	state.meta_credits = 43
	state.progress = 3
	state.backpack.assign([{"id": &"fat", "hp": 12.5}, {"id": &"leg", "hp": 7.0}])
	root.add_child(state)
	var build = load("res://scenes/build/build_screen.tscn").instantiate()
	root.add_child(build)
	current_scene = build
	await process_frame
	var grid: AssemblyGrid = build._grid
	var old_state := state_bytes(state)
	var old_grid := grid_bytes(grid)
	var saves := state.saves
	build._on_motion_test()
	check(current_scene == build and grid_bytes(grid) == old_grid and state_bytes(state) == old_state and state.saves == saves, "invalid empty entry leaves scene/grid/state/save callbacks unchanged")
	check(build.get_node("MotionTestError").visible, "actionable pre-entry error visible")
	build.get_node("MotionTestError").hide()
	var lib := OrganLibrary.catalog()
	for entry in [[&"fat", Vector2i(1, 1)], [&"fat", Vector2i(3, 1)], [&"heart", Vector2i(5, 2)], [&"brain", Vector2i(5, 0)], [&"parasite", Vector2i(4, 0)], [&"leg", Vector2i(5, 3)], [&"leg", Vector2i(1, 3)]]:
		check(grid.place(entry[1], lib[entry[0]], 0, true), "fixture organ placed")
	var organs := grid.organs()
	var heart = organs[2]
	var brain = organs[3]
	link(grid, organs[4], &"nerve", brain, &"nerve_in", OrganData.NERVE)
	for index in [5, 6]:
		link(grid, brain, &"nerve_out", organs[index], &"nerve", OrganData.NERVE)
		link(grid, heart, &"blood", organs[index], &"blood", OrganData.BLOOD)
	link(grid, heart, &"blood", brain, &"blood", OrganData.BLOOD)
	for index in [0, 1]:
		link(grid, heart, &"blood", organs[index], &"blood_a", OrganData.BLOOD)
	for i in range(organs.size()):
		organs[i].hp -= 1.25 + i
	build._on_layout_changed()
	check(grid.result().alive, "ordinary full alive validator passes")
	var prepared := Bridge.prepare(grid)
	check(prepared.errors.is_empty(), "actual free-built viable assembly accepted: " + str(prepared.errors))
	if not prepared.errors.is_empty():
		build.free()
		state.free()
		quit(1)
		return
	# Corrupt only temporary fixture properties; preflight must reject and not write.
	old_state = state_bytes(state)
	saves = state.saves
	var old_rotation: int = organs[5].rotation
	organs[5].rotation = 1
	check(not Bridge.prepare(grid).errors.is_empty(), "sideways leg rejected")
	organs[5].rotation = old_rotation
	var old_data: OrganData = organs[5].data
	var unsupported: OrganData = old_data.duplicate()
	unsupported.motion_test_spec = null
	organs[5].data = unsupported
	check(not Bridge.prepare(grid).errors.is_empty(), "missing motion metadata rejected")
	organs[5].data = old_data
	var wrong_size: OrganData = old_data.duplicate()
	wrong_size.motion_test_spec = old_data.motion_test_spec.duplicate()
	wrong_size.motion_test_spec.upper_length = 20.0
	organs[5].data = wrong_size
	check(not Bridge.prepare(grid).errors.is_empty(), "wrong family bone length cannot distort reference size")
	organs[5].data = old_data
	var old_fixed_anchor: Vector2i = organs[3].anchor
	organs[3].anchor = Vector2i(8, 0)
	check(not Bridge.prepare(grid).errors.is_empty(), "disconnected fixed organs cannot become welded torso")
	organs[3].anchor = Vector2i(3, 3)
	check(not Bridge.prepare(grid).errors.is_empty(), "fixed cells intruding below hips rejected by workspace validation")
	organs[3].anchor = old_fixed_anchor
	var missing_leg = grid._order.pop_back()
	check(not Bridge.prepare(grid).errors.is_empty(), "one leg with off-center reference COM rejected")
	grid._order.append(missing_leg)
	var old_anchor: Vector2i = organs[5].anchor
	organs[5].anchor = Vector2i(3, 3)
	check(not Bridge.prepare(grid).errors.is_empty(), "overlapping hip workspaces rejected")
	organs[5].anchor = Vector2i(5, 4)
	check(not Bridge.prepare(grid).errors.is_empty(), "mount detached from real fixed cells rejected")
	organs[5].anchor = old_anchor
	var old_hp: float = organs[5].hp
	organs[5].hp = 0.0
	check(not Bridge.prepare(grid).errors.is_empty(), "destroyed organ rejected without autohealing")
	organs[5].hp = old_hp
	check(state_bytes(state) == old_state and state.saves == saves, "all invalid preflights leave persistent snapshot untouched")
	old_grid = grid_bytes(grid)
	var grid_id := grid.get_instance_id()
	var build_id: int = build.get_instance_id()
	build._on_motion_test()
	lab = current_scene
	check(lab != build and lab.scene_file_path == "res://scenes/build/motion_test_room.tscn", "real separate entrance instantiates native room")
	if lab == build:
		printerr(build.get_node("MotionTestError").dialog_text)
		build.free()
		state.free()
		quit(1)
		return
	walker = lab.walker
	check(build.get_parent() == lab and build.process_mode == Node.PROCESS_MODE_DISABLED, "room temporarily owns suspended exact build instance")
	check(walker.get_script() == preload("res://scripts/labs/blueprint_walker.gd") and walker.get_script().get_base_script() == preload("res://scripts/labs/procedural_walker.gd"), "no new movement implementation")
	check(walker.hit_shapes.size() == 4, "per-leg hit rigs instantiated for two legs")
	check(lab.get_node_or_null("Enemy") == null, "no combat enemy")
	await tick(90)
	check(walker.support_count == 2 and walker.jump_phase == "standing", "actual built creature has stable real ground support")
	var expected_fixed: Array[Vector2i] = []
	for p in organs:
		if p.data.limb == OrganData.Limb.NONE:
			expected_fixed.append_array(p.cells)
	var shapes := 0
	for node in walker.get_children():
		if node is CollisionShape2D:
			shapes += 1
			var cell: Vector2i = node.get_meta("grid_cell")
			check(expected_fixed.has(cell), "only actual fixed cells welded")
			expected_fixed.erase(cell)
			check(node.position == (Vector2(cell) - prepared.spec.frame_origin) * 32.0 and node.shape.size == Vector2(32, 32), "uniform exact cell mapping no COM recenter/shape distortion")
	check(expected_fixed.is_empty() and shapes == 12, "twelve real fixed-cell colliders, six leg cells excluded")
	var x: float = walker.position.x
	walker.set_walk_intent(1.0)
	await tick(240)
	var right: float = walker.position.x - x
	var steps: int = walker.completed_steps.size()
	check(right > 250.0 and steps >= 6, "same controller walks actual assembly >250px/six steps")
	walker.set_walk_intent(0.0)
	await tick(90)
	await jump_check("actual_hatchery")
	x = walker.position.x
	walker.set_walk_intent(-1.0)
	await tick(240)
	var reverse: float = x - walker.position.x
	check(reverse > 250.0, "same controller reverses actual assembly >250px")
	walker.set_walk_intent(0.0)
	check(grid_bytes(grid) == old_grid and state_bytes(state) == old_state and state.saves == saves, "during movement exact HP/links/resources/economy/backpack unchanged with zero saves")
	lab.get_node("HUD/Panel/Box/Return").pressed.emit()
	walker = null
	await process_frame
	await process_frame
	check(current_scene == build and build.get_instance_id() == build_id and grid.get_instance_id() == grid_id, "native return button restores same instance no rebuild callbacks")
	check(build.visible and build.process_mode == Node.PROCESS_MODE_INHERIT, "build visible and interactive after return")
	check(grid_bytes(grid) == old_grid, "byte-identical HP/anchor/rotation/cell/resource/link snapshot after roundtrip")
	check(state_bytes(state) == old_state and state.saves == saves, "byte-identical credits/meta/progress/backpack/persistent blueprint with zero saves")
	# Second entry proves reparenting did not rerun _ready or duplicate signals.
	build._on_motion_test()
	lab = current_scene
	check(lab != build, "repeat entry accepted")
	lab.return_to_build()
	await process_frame
	check(grid_bytes(grid) == old_grid and state_bytes(state) == old_state and state.saves == saves, "repeat roundtrip exact and save-free")
	print("HATCHERY_METRICS frames=", frames, " right=", right, " reverse=", reverse, " steps=", steps, " stance_samples=", checked_stance_frames, " max_drift=", max_stance_drift, " bone_error=", max_length_error, " hit_error=", max_hit_error, " saves_during_test=", state.saves - saves, " grid_bytes=", old_grid.size(), " state_bytes=", old_state.size())
	print("HATCHERY_MOTION_CHECK ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	build.free()
	state.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
