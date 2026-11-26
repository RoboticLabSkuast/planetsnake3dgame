shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform vec3 cloud_color : source_color = vec3(0.88, 0.94, 1.0);
uniform vec3 sun_dir = vec3(-0.74, 0.50, 0.44);
uniform float opacity : hint_range(0.0, 0.4) = 0.13;

varying vec3 v_obj_pos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3d(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y),
		f.z
	);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3d(p);
		p = p * 2.04 + vec3(5.3, 2.7, 7.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_obj_pos = normalize(VERTEX);
}

void fragment() {
	// Gently drift clouds around the planet without obscuring gameplay
	float ang = TIME * 0.025;
	float c = cos(ang);
	float s = sin(ang);
	vec3 p = vec3(v_obj_pos.x * c - v_obj_pos.z * s, v_obj_pos.y, v_obj_pos.x * s + v_obj_pos.z * c);

	float n1 = fbm(p * 3.1 + vec3(2.4));
	float n2 = fbm(p * 6.4 - vec3(TIME * 0.012, 1.1, 0.5));
	float wisp = smoothstep(0.54, 0.80, n1 * 0.7 + n2 * 0.3);

	float sun_lit = smoothstep(-0.35, 0.60, dot(v_obj_pos, normalize(sun_dir)));
	vec3 col = cloud_color * (0.25 + 0.85 * sun_lit);

	// Fade near center view angle so foreground snake/apples remain crisp, stronger near limbs
	float ndotv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float limb = mix(0.45, 1.25, pow(1.0 - ndotv, 1.6));

	ALBEDO = col;
	ALPHA = clamp(wisp * opacity * limb, 0.0, 0.25);
}
