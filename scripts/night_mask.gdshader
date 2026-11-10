shader_type canvas_item;
render_mode unshaded;

// Night-regime vision mask (issue #367, rework v3 — owner 2026-11-07:
// "you should make a new layer that will hide all beyond characters'
// vision; all beyond characters' vision must be totally black").
//
// The overlay is a plain black quad; this fragment shader decides per
// pixel whether a vision wedge or a light source reveals it. Everything
// else stays pure black — terrain, figures AND the background layer
// (a CanvasModulate could never darken that).

// Vision wedges: one per player-team figure. xy = world origin,
// zw = the figure's live aim direction (unit vector).
const int MAX_WEDGES = 12;
uniform int wedge_count : hint_range(0, 12) = 0;
uniform vec4 wedges[MAX_WEDGES];

// Shared wedge geometry (world pixels / radians).
uniform float vision_radius : hint_range(16.0, 4096.0) = 300.0;
uniform float vision_half_angle : hint_range(0.05, 1.55) = 0.349066;

// Light sources: every active ShotLight (muzzle flashes, projectiles,
// mines, explosions). xy = world position, z = radius.
const int MAX_LIGHTS = 16;
uniform int light_count : hint_range(0, 16) = 0;
uniform vec3 lights[MAX_LIGHTS];

// Screen (canvas) pixels -> world coordinates: the inverse of the
// viewport's canvas transform, updated by NightRegime every frame.
uniform vec2 cam_ix = vec2(1.0, 0.0);
uniform vec2 cam_iy = vec2(0.0, 1.0);
uniform vec2 cam_io = vec2(0.0, 0.0);
uniform vec2 screen_size = vec2(1152.0, 648.0);

// Soft edges so the wedge borders don't alias.
const float EDGE_PX = 24.0;
const float EDGE_ANG = 0.05;
// Small fully-visible disc so the figure itself is always inside its
// own vision.
const float SELF_PX = 28.0;

float wedge_visibility(vec2 world) {
	float vis = 0.0;
	for (int i = 0; i < MAX_WEDGES; i++) {
		if (i >= wedge_count) {
			break;
		}
		vec2 delta = world - wedges[i].xy;
		float dist = length(delta);
		if (dist < SELF_PX) {
			return 1.0;
		}
		if (dist > vision_radius + EDGE_PX) {
			continue;
		}
		vec2 dir = normalize(wedges[i].zw);
		float ang = acos(clamp(dot(delta / dist, dir), -1.0, 1.0));
		float radial = 1.0 - smoothstep(vision_radius - EDGE_PX, vision_radius, dist);
		float angular = 1.0 - smoothstep(vision_half_angle - EDGE_ANG, vision_half_angle + EDGE_ANG, ang);
		vis = max(vis, radial * angular);
	}
	return vis;
}

float light_visibility(vec2 world) {
	float vis = 0.0;
	for (int j = 0; j < MAX_LIGHTS; j++) {
		if (j >= light_count) {
			break;
		}
		float radius = max(lights[j].z, SELF_PX);
		float dist = distance(world, lights[j].xy);
		vis = max(vis, 1.0 - smoothstep(radius - EDGE_PX, radius, dist));
	}
	return vis;
}

void fragment() {
	vec2 canvas_pos = SCREEN_UV * screen_size;
	vec2 world = vec2(dot(cam_ix, canvas_pos), dot(cam_iy, canvas_pos)) + cam_io;
	float visible = max(wedge_visibility(world), light_visibility(world));
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - visible);
}
