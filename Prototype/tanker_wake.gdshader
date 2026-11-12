shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Animation clock advanced by whole displayed frames (flight_view.gd), unlike TIME.
global uniform float game_time;

void fragment() {
	float distance_aft = UV.y;
	float across = abs(UV.x * 2.0 - 1.0);
	float spread = mix(0.22, 0.86, distance_aft);
	float flow = distance_aft * 21.0 - game_time * 4.5;
	float broken_edge = sin(flow * 1.7 + UV.x * 12.0) * 0.022;
	float bow_wave = 1.0 - smoothstep(0.022, 0.068, abs(across - spread + broken_edge));
	float wash_width = mix(0.24, 0.38, distance_aft);
	float prop_wash = (1.0 - smoothstep(0.0, wash_width, across)) * exp(-distance_aft * 2.8);
	float turbulence = sin(flow * 2.1 + sin(UV.x * 51.0)) * sin(UV.x * 91.0 - flow);
	float fade = smoothstep(0.0, 0.10, distance_aft) * (1.0 - smoothstep(0.12, 1.0, distance_aft));
	ALBEDO = mix(vec3(0.29, 0.57, 0.61), vec3(0.72, 0.87, 0.84), turbulence * 0.32 + 0.5);
	ALPHA = fade * (bow_wave * 0.57 + prop_wash * 0.65) * (0.69 + turbulence * 0.26);
}
