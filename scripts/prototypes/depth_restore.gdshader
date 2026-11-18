shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;

uniform sampler2D sprite_texture : source_color, filter_linear_mipmap;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 ground_position = vec3(0.0);
uniform vec3 ground_view_back = vec3(0.0, 0.0, 1.0);
uniform float depth_tolerance = 0.015;

void fragment() {
	vec4 ink = texture(sprite_texture, UV);
	if (ink.a < 0.5) { discard; }
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec3 ndc;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	#else
		ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#endif
	vec4 view_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_position /= view_position.w;
	vec3 surface_world = (INV_VIEW_MATRIX * view_position).xyz;
	// Camera looks from +Z: only restore pixels over surfaces deeper than the feet.
	if (dot(surface_world - ground_position, ground_view_back) >= -depth_tolerance) { discard; }
	ALBEDO = ink.rgb;
	ALPHA = 1.0;
}
