shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform float sharpness = 0.0;
uniform float scanline_strength = 0.0;
uniform float crt_line_count = 161.0;

// Smooth beam profile inspired by CRT-Lottes and CRT-Easymode.
// Broaden the bright beams and preserve the average gain over one period.
float crt_gain(float phase, vec3 rgb) {
	float distance_to_beam = abs(phase * 2.0 - 1.0);
	float gap = smoothstep(0.0, 1.0, distance_to_beam);
	float beam_spread = 0.65 * dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	float weighted_gap = mix(gap, gap * gap, beam_spread);
	float mean_gap = mix(0.5, 13.0 / 35.0, beam_spread);
	return 1.0 + scanline_strength * (mean_gap - weighted_gap);
}

void fragment() {
	vec3 center = texture(TEXTURE, UV).rgb;
	if (sharpness > 0.0) {
		vec2 dx = vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
		vec3 west = texture(TEXTURE, UV - dx).rgb;
		vec3 east = texture(TEXTURE, UV + dx).rgb;
		vec3 low = min(center, min(west, east));
		vec3 high = max(center, max(west, east));
		vec3 neighbors = (west + east) * 0.5;
		// With CRT enabled, the beam already adds vertical definition.
		if (scanline_strength == 0.0) {
			vec2 dy = vec2(0.0, TEXTURE_PIXEL_SIZE.y);
			vec3 north = texture(TEXTURE, UV - dy).rgb;
			vec3 south = texture(TEXTURE, UV + dy).rgb;
			low = min(low, min(north, south));
			high = max(high, max(north, south));
			neighbors = (west + east + north + south) * 0.25;
		}
		center = clamp(center + (center - neighbors) * sharpness, low, high);
	}
	if (scanline_strength > 0.0) {
		center *= crt_gain(fract(UV.y * crt_line_count), center);
	}
	COLOR = vec4(center, 1.0);
}
