shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform int shape = 0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float opacity;
	vec3 color = tint.rgb * COLOR.rgb;
	if (shape == 1) {
		opacity = smoothstep(0.69, 0.86, radius) * (1.0 - smoothstep(0.86, 1.0, radius));
	} else if (shape == 2) {
		float head = 1.0 - UV.y;
		float width = mix(0.16, 0.85, head);
		opacity = head * (1.0 - smoothstep(width * 0.2, width, abs(p.x)));
	} else if (shape == 3) {
		float angle = atan(p.y + 0.0001, p.x + 0.0001);
		float edge = radius + 0.10 * sin(angle * 6.0 + radius * 8.0) * radius;
		float heat = 1.0 - smoothstep(0.12, 0.78, edge);
		color = mix(color * vec3(1.0, 0.56, 0.35), mix(color, vec3(1.0, 0.94, 0.72), 0.7), heat);
		opacity = 1.0 - smoothstep(0.24, 1.0, edge);
	} else {
		opacity = 1.0 - smoothstep(0.05, 1.0, radius + 0.035 * sin(p.x * 13.0) * sin(p.y * 11.0));
	}
	ALBEDO = color;
	ALPHA = opacity * tint.a * COLOR.a;
}
