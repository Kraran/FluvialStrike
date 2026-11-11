shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform int shape = 0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float opacity;
	if (shape == 1) {
		opacity = smoothstep(0.69, 0.86, radius) * (1.0 - smoothstep(0.86, 1.0, radius));
	} else if (shape == 2) {
		float head = 1.0 - UV.y;
		float width = mix(0.16, 0.85, head);
		opacity = head * (1.0 - smoothstep(width * 0.2, width, abs(p.x)));
	} else {
		opacity = 1.0 - smoothstep(0.05, 1.0, radius + 0.035 * sin(p.x * 13.0) * sin(p.y * 11.0));
	}
	ALBEDO = tint.rgb * COLOR.rgb;
	ALPHA = opacity * tint.a * COLOR.a;
}
