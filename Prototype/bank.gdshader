shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Water drift in world units: one render texel per displayed frame (flight_view.gd).
global uniform float water_flow;
// The water pattern repeats exactly every WATER_PERIOD units along the course (3000 rows,
// WATER_PERIOD_ROWS in flight_view.gd): the drift wraps there without any visible jump.
const float WATER_PERIOD = 900.0;
// Meander: 24 whole waves per period (0.1676 rad/unit).
const float MEANDER = 24.0 * 6.28318530718 / WATER_PERIOD;

varying vec2 ground_position;
uniform sampler2D shore_map : filter_linear, repeat_disable;
uniform vec2 shore_origin = vec2(0.0, 57.6);
uniform float course_offset = 0.0;
uniform float region_length = 921.6;
uniform float region_blend = 144.0;
uniform vec4 town_weights;
uniform vec4 rock_weights;
varying vec2 land_region;

vec2 region_weights(float distance) {
	float block = max(0.0, floor(distance / region_length));
	int current = int(mod(block, 4.0));
	int previous = int(mod(max(0.0, block - 1.0), 4.0));
	float blend = smoothstep(0.0, region_blend, distance - block * region_length);
	return mix(vec2(town_weights[previous], rock_weights[previous]),
		vec2(town_weights[current], rock_weights[current]), blend);
}

vec2 shore_uv(vec2 p) {
	float course_z = p.y + course_offset;
	p.x += sin(course_z * 0.11) * 0.45 + sin(course_z * 0.47) * 0.12;
	return (vec2(p.x - shore_origin.x, shore_origin.y - p.y) / 0.6 + 0.5) / vec2(textureSize(shore_map, 0));
}

float shore_distance(vec2 p) {
	float beyond_map = max(-p.x, p.x - 91.2);
	if (beyond_map >= 2.4) {
		return 6.0;
	}
	float shore = (texture(shore_map, shore_uv(p)).r - 0.5) * 12.0;
	return mix(shore, 6.0, smoothstep(0.0, 2.4, beyond_map));
}

float ground_height(float shore) {
	return smoothstep(-0.15, 1.55, shore) * 0.26;
}

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
	float distance = -(ground_position.y + course_offset);
	land_region = region_weights(distance);
	if (ground_position.x <= -3.0 || ground_position.x >= 94.2) {
		VERTEX.y = 0.26;
		NORMAL = vec3(0.0, 1.0, 0.0);
	} else {
		float center;
		float east;
		float south;
		if (ground_position.x < 0.0 || ground_position.x > 91.2) {
			center = ground_height(shore_distance(ground_position));
			east = ground_height(shore_distance(ground_position + vec2(0.6, 0.0)));
			south = ground_height(shore_distance(ground_position - vec2(0.0, 0.6)));
		} else {
			vec2 uv = shore_uv(ground_position);
			vec2 step_uv = 1.0 / vec2(textureSize(shore_map, 0));
			center = ground_height((texture(shore_map, uv).r - 0.5) * 12.0);
			east = ground_height((texture(shore_map, uv + vec2(step_uv.x, 0.0)).r - 0.5) * 12.0);
			south = ground_height((texture(shore_map, uv + vec2(0.0, step_uv.y)).r - 0.5) * 12.0);
		}
		VERTEX.y = center;
		NORMAL = normalize(vec3((center - east) / 0.6, 1.0, (south - center) / 0.6));
	}
}

// Value noise that tiles along y every period cells.
float water_noise(vec2 point, float period) {
	vec2 cell = floor(point);
	vec2 t = fract(point);
	t = t * t * (3.0 - 2.0 * t);
	float y0 = mod(cell.y, period);
	float y1 = mod(cell.y + 1.0, period);
	return mix(mix(hash(vec2(cell.x, y0)), hash(vec2(cell.x + 1.0, y0)), t.x),
		mix(hash(vec2(cell.x, y1)), hash(vec2(cell.x + 1.0, y1)), t.x), t.y);
}

void fragment() {
	vec2 p = ground_position;
	float shore = shore_distance(p);
	p.y += course_offset;
	if (shore < 0.0) {
		float distance_to_bank = -shore;
		// The meander follows the drifting water, so the whole surface is a rigid translation.
		vec2 current = p + vec2(0.0, water_flow);
		current.x += sin(current.y * MEANDER) * 0.38;
		// Periods in cells: WATER_PERIOD times each y frequency (117, 522 and 1530).
		float broad = water_noise(current * vec2(0.34, 0.13), 117.0);
		float curl = water_noise(current * vec2(1.65, 0.58) + broad * 3.5, 522.0);
		float ripple = water_noise(current * vec2(4.2, 1.7) + vec2(curl * 2.0, -broad), 1530.0);
		float crest = smoothstep(0.71, 0.96, ripple * 0.68 + curl * 0.32);
		float shallows = 1.0 - smoothstep(0.18, 3.35, distance_to_bank);
		float variation = broad * 0.50 + curl * 0.35 + ripple * 0.15;
		vec3 channel = mix(vec3(0.025, 0.081, 0.109), vec3(0.057, 0.152, 0.182), variation);
		vec3 shallow = mix(vec3(0.070, 0.127, 0.102), vec3(0.155, 0.226, 0.151), variation);
		float bend = fract(distance_to_bank * 0.65 + curl * 0.77 + broad * 0.27);
		float eddies = (1.0 - smoothstep(0.06, 0.23, abs(bend - 0.5))) * smoothstep(0.40, 0.73, curl);
		float foam = (1.0 - smoothstep(0.26, 1.90, distance_to_bank)) * eddies;
		ALBEDO = mix(channel, shallow, shallows) + crest * vec3(0.055, 0.073, 0.078)
			+ foam * vec3(0.105, 0.145, 0.137);
		ROUGHNESS = 0.38;
	} else {
		float meadow = noise(p * 0.15) * 0.6 + noise(p * 0.63) * 0.27 + noise(p * 2.7) * 0.13;
		float grain = (hash(floor(p * 29.0)) - 0.5) * 0.047;
		vec3 grass = mix(vec3(0.075, 0.135, 0.057), vec3(0.29, 0.34, 0.16), meadow);
		grass = mix(grass, grass * vec3(1.23, 1.02, 0.77), land_region.x);
		vec3 exposed_rock = mix(vec3(0.18, 0.15, 0.12), vec3(0.35, 0.31, 0.25), meadow);
		grass = mix(grass, exposed_rock, land_region.y * smoothstep(0.25, 0.67, meadow));
		vec3 silt = mix(vec3(0.17, 0.14, 0.087), vec3(0.39, 0.34, 0.235), meadow);
		ALBEDO = mix(silt, grass, smoothstep(0.2, 2.0, shore + grain)) + grain;
		ROUGHNESS = 0.96;
	}
	SPECULAR = 0.0;
}
