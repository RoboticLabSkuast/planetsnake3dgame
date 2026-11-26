shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded;

uniform vec3 rim_color : source_color = vec3(0.28, 0.62, 1.0);
uniform vec3 sun_dir = vec3(-0.75, 0.52, 0.40);
uniform float intensity : hint_range(0.0, 3.0) = 1.05;
uniform float power : hint_range(1.0, 8.0) = 3.4;

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndotv = clamp(abs(dot(n, normalize(VIEW))), 0.0, 1.0);
	float outer_fade = smoothstep(0.0, 0.44, ndotv);
	float inner_glow = pow(clamp(1.0 - ndotv, 0.0, 1.0), power);
	// Sunlit hemisphere scatters brightly while night hemisphere fades into twilight
	float sun_scatter = smoothstep(-0.45, 0.65, dot(-n, normalize(sun_dir)));
	float halo = outer_fade * inner_glow * 2.2 * (0.28 + 0.92 * sun_scatter);
	ALBEDO = rim_color * intensity * halo;
	ALPHA = clamp(halo * 0.68, 0.0, 1.0);
}
