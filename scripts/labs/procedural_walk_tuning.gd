extends Resource
## The only source of bone lengths and controller/gait tuning. Pixels, seconds, kg.
@export_group("Skeleton")
@export var upper_length: float = 46.0
@export var lower_length: float = 46.0
@export var hip_half_spacing: float = 9.0
@export var hip_drop: float = 8.0
@export var limb_radius: float = 3.0
@export var foot_radius: float = 4.0
@export var clearance: float = 1.0
@export var reach_margin: float = 2.0
@export var rest_foot_spacing: float = 15.0
@export_group("Torso controller")
@export var body_mass: float = 6.0
@export var body_inertia: float = 1800.0
@export var support_height: float = 86.0
@export var walk_speed: float = 95.0
@export var velocity_gain: float = 12.0
@export var height_gain: float = 110.0
@export var height_damping: float = 21.0
@export var max_horizontal_accel: float = 650.0
@export var max_support_accel: float = 2200.0
@export var upright_gain: float = 65.0
@export var upright_damping: float = 14.0
@export var max_angular_accel: float = 100.0
@export_group("Gait")
@export var step_trigger: float = 16.0
@export var step_lead: float = 24.0
@export var swing_duration: float = 0.30
@export var swing_height: float = 24.0
@export var minimum_step: float = 8.0
@export var step_cooldown: float = 0.06
@export var landing_speed: float = 40.0
@export_group("Jump")
@export var jump_crouch_duration: float = 0.16
@export var jump_crouch_height: float = 74.0
@export var jump_crouch_tolerance: float = 5.0
@export var jump_impulse_speed: float = 350.0
@export var jump_tuck_distance: float = 48.0
@export var jump_extend_distance: float = 88.0
@export var jump_prepare_distance: float = 77.0
@export var jump_pose_speed: float = 300.0
@export var jump_tuck_delay: float = 0.06
@export var jump_prepare_velocity: float = -35.0
@export var jump_landing_height: float = 73.0
@export var jump_landing_duration: float = 0.16
@export var jump_recover_duration: float = 0.28
@export var jump_stable_speed: float = 12.0
@export var jump_pose_search_offsets: PackedFloat32Array = PackedFloat32Array([0.0, -18.0, 18.0, -36.0, 36.0])
@export_group("World queries")
@export_flags_2d_physics var ground_mask: int = 256
@export var probe_up: float = 100.0
@export var probe_down: float = 180.0
@export var contact_tolerance: float = 2.0
@export var min_ground_normal: float = 0.80
@export var path_samples: int = 24
@export var sweep_spacing: float = 2.0
@export var max_sweep_samples: int = 80
@export var landing_search_offsets: PackedFloat32Array = PackedFloat32Array([0.0, -8.0, 8.0, -16.0, 16.0])
