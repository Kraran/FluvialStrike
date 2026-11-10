shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

varying vec2 ground_position;

float hash(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 t = fract(point);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), t.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), t.x), t.y);
}

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = ground_position;
	float meadow = noise(p * 0.15) * 0.6 + noise(p * 0.63) * 0.27 + noise(p * 2.7) * 0.13;
	float grain = (hash(floor(p * 29.0)) - 0.5) * 0.047;
	vec3 grass = mix(vec3(0.065, 0.103, 0.046), vec3(0.24, 0.27, 0.125), meadow);
	vec3 silt = mix(vec3(0.17, 0.14, 0.087), vec3(0.39, 0.34, 0.235), meadow);
	ALBEDO = mix(grass, silt, smoothstep(0.18, 0.9, COLOR.r + grain)) + grain;
	ROUGHNESS = 0.96;
}
