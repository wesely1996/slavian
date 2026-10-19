// The light grade over the map (MapGrade; game-assets-enhancement skill,
// docs/art-style.md): a low warm wash from the light in the north-west,
// cloud shadows drifting a little faster than the ground when the map pans
// (they float above it, so they sell its depth), and a gentle vignette round
// the part of the map in view. It fuses the separately drawn pieces into one
// lit world. Drawn with alpha over the map, under the interface.
shader_type canvas_item;

uniform sampler2D clouds : repeat_enable, filter_linear_mipmap;
// The camera: its position and zoom, and where on screen its position shows.
uniform vec2 camera = vec2(0.0);
uniform float zoom = 1.0;
uniform vec2 focus = vec2(0.5);
uniform vec2 screen = vec2(720.0, 1280.0);
// Clouds are this much nearer the eye than the ground.
uniform float cloud_parallax = 1.15;
uniform float cloud_scale = 0.0006;
uniform vec2 cloud_drift = vec2(6.0, 2.5);
uniform float cloud_shadow = 0.12;
uniform float warmth = 0.09;
uniform float vignette = 0.32;
const vec3 WARM = vec3(1.0, 0.84, 0.58);
const vec3 COOL_SHADOW = vec3(0.06, 0.08, 0.12);

void fragment() {
	vec2 px = SCREEN_UV * screen;
	vec2 from_focus = px - focus * screen;
	// The world under this pixel, as the clouds see it.
	vec2 world = camera * cloud_parallax + from_focus / zoom;
	float c = texture(clouds, (world + TIME * cloud_drift) * cloud_scale).r;
	float shade = smoothstep(0.52, 0.72, c) * cloud_shadow;
	// The vignette, round the map in view.
	vec2 v = from_focus / (0.5 * screen);
	float dark = smoothstep(0.55, 1.45, length(v)) * vignette;
	// The warm light from the upper left.
	float warm = (1.0 - clamp(length(SCREEN_UV - vec2(0.0, 0.0)) / 1.3, 0.0, 1.0)) * warmth;
	float a = clamp(shade + dark + warm, 0.0, 1.0);
	vec3 tint = (COOL_SHADOW * (shade + dark) + WARM * warm) / max(a, 1e-4);
	COLOR = vec4(tint, a);
}
