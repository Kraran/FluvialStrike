shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Animation clock advanced by whole displayed frames (flight_view.gd), unlike TIME.
global uniform float game_time;

varying vec2 river_position;

float hash(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float wavelet(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), blend.x), blend.y);
}

void vertex() {
	river_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = river_position;
	vec2 drift = p + vec2(sin(p.y * 0.17) * 0.45, game_time * 2.4);
	float broad = wavelet(drift * vec2(0.31, 0.15));
	float curl = wavelet(drift * vec2(1.8, 0.65) + broad * 4.1);
	float ripple = wavelet(drift * vec2(4.5, 2.1) + vec2(curl * 2.0, -broad));
	float crest = smoothstep(0.70, 0.97, ripple * 0.76 + curl * 0.24);
	float depth = clamp(COLOR.r, 0.0, 1.0);
	float variation = broad * 0.5 + curl * 0.35 + ripple * 0.15;
	vec3 channel = mix(vec3(0.025, 0.085, 0.11), vec3(0.058, 0.168, 0.205), variation);
	vec3 shallow = mix(vec3(0.095, 0.125, 0.082), vec3(0.19, 0.23, 0.15), variation);
	float foam = smoothstep(0.78, 1.0, depth) * smoothstep(0.26, 0.85, ripple);
	ALBEDO = mix(channel, shallow, depth) + crest * vec3(0.064, 0.077, 0.078)
		+ foam * vec3(0.18, 0.22, 0.18);
	ROUGHNESS = 0.38;
	SPECULAR = 0.0;
}
