extends RigidBody2D
## GodotPhysics2D returns WORLD-space positions and normals despite the
## get_contact_local_* names (verified by a rotated-body regression probe).
var ground_contacts: Array[Dictionary] = []

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	ground_contacts.clear()
	for i in state.get_contact_count():
		var collider := state.get_contact_collider_object(i)
		if collider is StaticBody2D and collider.is_in_group("lab_ground"):
			ground_contacts.append({
				"point": state.get_contact_local_position(i),
				"local_point": state.get_contact_local_position(i),
				"normal": state.get_contact_local_normal(i),
				"shape": state.get_contact_local_shape(i)})
