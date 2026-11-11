shader_type canvas_item;
render_mode unshaded;

uniform float sharpness = 0.0;

void fragment() {
	vec3 center = texture(TEXTURE, UV).rgb;
	if (sharpness > 0.0) {
		vec2 dx = vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
		vec2 dy = vec2(0.0, TEXTURE_PIXEL_SIZE.y);
		vec3 west = texture(TEXTURE, UV - dx).rgb;
		vec3 east = texture(TEXTURE, UV + dx).rgb;
		vec3 north = texture(TEXTURE, UV - dy).rgb;
		vec3 south = texture(TEXTURE, UV + dy).rgb;
		vec3 low = min(center, min(min(west, east), min(north, south)));
		vec3 high = max(center, max(max(west, east), max(north, south)));
		vec3 detail = center - (west + east + north + south) * 0.25;
		center = clamp(center + detail * sharpness, low, high);
	}
	COLOR = vec4(center, 1.0);
}
