shader_type spatial;
render_mode cull_back;

// The dome cap is modelled once at full size. Shrinking it is done here rather
// than by regenerating the mesh: every vertex past the live rim is pulled back
// onto it and dropped onto the sphere at that radius. Regenerating the mesh in
// GDScript cost ~10 ms a time, several times a second, which a phone cannot
// afford in the middle of the busiest part of a round.

uniform float play_radius = 13.5;
uniform float dome_radius = 48.0;
uniform float band_width = 1.6;

// Plain vec3s, not source_color: the old path fed these through vertex colours
// with vertex_color_is_srgb off, i.e. used them raw. Keeping that preserves the
// exact look.
uniform vec3 color_inner = vec3(0.184, 0.310, 0.478);
uniform vec3 color_mid = vec3(0.239, 0.431, 0.659);
uniform vec3 color_edge = vec3(0.910, 0.400, 0.247);

varying float v_radius;

void vertex() {
	float r = length(VERTEX.xz);
	if (r > play_radius && r > 0.0001) {
		VERTEX.xz *= play_radius / r;
		r = play_radius;
	}
	VERTEX.y = sqrt(dome_radius * dome_radius - r * r) - dome_radius;
	NORMAL = normalize(VERTEX - vec3(0.0, -dome_radius, 0.0));
	v_radius = r;
}

void fragment() {
	float t = clamp(v_radius / max(play_radius, 0.001), 0.0, 1.0);
	vec3 c = mix(color_inner, color_mid, smoothstep(0.0, 0.8, t));
	c = mix(c, color_edge, smoothstep(0.80, 1.0, t));
	// Concentric bands for reading distance to the edge and your own speed. The
	// per-vertex version was interpolated into soft bands; this matches it.
	float band = 0.5 + 0.5 * cos(v_radius / band_width * PI);
	c *= 1.0 - 0.12 * band;
	ALBEDO = c;
	ROUGHNESS = 0.62;
	METALLIC = 0.08;
	RIM = 0.45;
	RIM_TINT = 0.5;
}
