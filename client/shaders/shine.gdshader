// One pass of light across a piece of gold (the splash's game logo): a soft
// diagonal band, only where the texture is opaque, at `sweep` (0 to 1).
shader_type canvas_item;

uniform float sweep = -1.0;
uniform float width = 0.12;
uniform float strength = 0.55;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float along = (UV.x + UV.y * 0.6) / 1.6;
	float band = 1.0 - smoothstep(0.0, width, abs(along - sweep));
	c.rgb += vec3(1.0, 0.95, 0.8) * band * strength * c.a;
	COLOR = c * COLOR;
}
