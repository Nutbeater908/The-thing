## 复用已验收原型的控制/瞄准/补绘；地图在 .tscn 中手工模块化组织。
extends "res://scripts/prototypes/depth_range.gd"

func _build_range() -> void:
	for node in $Actors.get_children():
		if node is StaticBody3D:
			node.set_meta("hits", 0)
			targets.append(node)
