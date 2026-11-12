shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Water drift in world units: one render texel per displayed frame (flight_view.gd).
global uniform float water_flow;
// Same exact period as bank.gdshader (WATER_PERIOD_ROWS in flight_view.gd).
const float WATER_PERIOD = 900.0;
const float MEANDER = 24.0 * 6.28318530718 / WATER_PERIOD;

varying vec2 river_position;

float hash(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Value noise that tiles along y every period cells.
float water_wavelet(vec2 p, float period) {
	vec2 cell = floor(p);
	vec2 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float y0 = mod(cell.y, period);
	float y1 = mod(cell.y + 1.0, period);
	return mix(mix(hash(vec2(cell.x, y0)), hash(vec2(cell.x + 1.0, y0)), blend.x),
		mix(hash(vec2(cell.x, y1)), hash(vec2(cell.x + 1.0, y1)), blend.x), blend.y);
}

void vertex() {
	river_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = river_position;
	vec2 drift = p + vec2(0.0, water_flow);
	drift.x += sin(drift.y * MEANDER) * 0.45;
	float broad = water_wavelet(drift * vec2(0.31, 0.15), 135.0);
	float curl = water_wavelet(drift * vec2(1.8, 0.65) + broad * 4.1, 585.0);
	float ripple = water_wavelet(drift * vec2(4.5, 2.1) + vec2(curl * 2.0, -broad), 1890.0);
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
