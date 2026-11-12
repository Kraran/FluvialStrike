shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Animation clock advanced by whole displayed frames (flight_view.gd), unlike TIME.
global uniform float game_time;

varying vec3 crown_position;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	crown_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bunch = sin(VERTEX.x * 29.0 + VERTEX.z * 23.0 + crown_position.x * 2.3);
	VERTEX += NORMAL * bunch * 0.026;
	float wind = sin(game_time * 1.15 + crown_position.x * 0.27 + crown_position.z * 0.19);
	VERTEX.xz += vec2(0.045, 0.022) * wind * COLOR.a * smoothstep(0.4, 2.8, VERTEX.y);
}

void fragment() {
	float bunch = hash(floor(crown_position * 8.6));
	float leaf = hash(floor(crown_position * 27.5));
	ALBEDO = COLOR.rgb * (0.69 + bunch * 0.36 + leaf * 0.21);
	ROUGHNESS = 0.96;
}
