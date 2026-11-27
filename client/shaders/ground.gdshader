// The map's ground (MapGround): each vertex carries its terrain colour and,
// in alpha, its height. Two noise textures give the ground grain and broad
// variation; the slope of the blended height, lit from the north-west, gives
// relief where land rises; low ground is water, darker, with a soft sheen.
shader_type canvas_item;

uniform sampler2D detail : repeat_enable, filter_linear_mipmap;
uniform sampler2D macro : repeat_enable, filter_linear_mipmap;
uniform float detail_scale = 0.0045;
uniform float macro_scale = 0.0013;
uniform vec2 light = vec2(-0.62, -0.78);
uniform float relief = 10.0;
// The season (data/seasons.json order): 0 spring (as it is), 1 summer
// (sun-gold grass), 2 autumn (rust and ochre where it was green), 3 winter
// (snow in drifts on the land, ice-grey water).
uniform int season = 0;

varying vec2 world;
varying float height;

void vertex() {
	world = VERTEX;
	height = COLOR.a;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float d = texture(detail, world * detail_scale).r;
	float dx = texture(detail, (world + vec2(6.0, 0.0)) * detail_scale).r - d;
	float dy = texture(detail, (world + vec2(0.0, 6.0)) * detail_scale).r - d;
	float m = texture(macro, world * macro_scale).r;
	// Height per world unit, from how fast it changes across the screen.
	float scale = max(abs(dFdx(world.x)), 1e-4);
	vec2 slope = vec2(dFdx(height), dFdy(height)) / scale;
	float water = 1.0 - smoothstep(0.06, 0.13, height);
	float land = 1.0 - water;
	// Gentle slopes between terrains, rugged grain where the land is high.
	float rugged = 0.35 + 1.5 * height * height;
	float lit = dot(slope * relief * land + vec2(dx, dy) * rugged * land, -light);
	float shade = clamp(1.0 + lit, 0.62, 1.32);
	vec3 col = base * (0.9 + 0.16 * d) * (0.88 + 0.24 * m) * shade;
	// Water: calmer grain, darker in the deep, a sheen where the light falls.
	float sheen = smoothstep(0.55, 0.85, m) * 0.12 + smoothstep(0.6, 0.9, d) * 0.06;
	vec3 wet = base * (0.86 + 0.18 * m) + vec3(sheen);
	col = mix(col, wet, water);
	// The season over the land (spring as it is).
	// Grass and leaves: green over blue, not much redder than green.
	float green = clamp((col.g - col.b) * 3.0 - max(0.0, col.r - col.g) * 4.0, 0.0, 1.0) * land;
	if (season == 1) {
		col = mix(col, col * vec3(1.1, 1.04, 0.8), 0.5 * land);
		col = mix(col, vec3(dot(col, vec3(0.4, 0.45, 0.15))) * vec3(1.3, 1.12, 0.55), 0.45 * green);
	} else if (season == 2) {
		vec3 rust = vec3(dot(col, vec3(0.45, 0.45, 0.1))) * mix(vec3(1.35, 0.78, 0.38), vec3(1.15, 0.95, 0.45), m);
		col = mix(col, rust, 0.8 * green);
		col = mix(col, col * vec3(1.04, 0.96, 0.86), 0.4 * land);
	} else if (season == 3) {
		float drift = smoothstep(0.38, 0.62, m * 0.65 + d * 0.35 + height * 0.25);
		vec3 snow = vec3(0.9, 0.93, 0.97) * clamp(shade, 0.8, 1.1);
		col = mix(col, snow, (0.35 + 0.55 * drift) * land);
		col = mix(col, vec3(0.62, 0.72, 0.8) * (0.9 + 0.15 * m), 0.45 * water);
	}
	COLOR = vec4(col, 1.0);
}
