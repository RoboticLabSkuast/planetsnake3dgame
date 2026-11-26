shader_type sky;

uniform vec3 nebula_color_a : source_color = vec3(0.025, 0.065, 0.165);
uniform vec3 nebula_color_b : source_color = vec3(0.085, 0.042, 0.175);
uniform vec3 nebula_color_c : source_color = vec3(0.022, 0.115, 0.155);
uniform vec3 sun_dir = vec3(-0.74, 0.50, 0.44);

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yxz + 19.19);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3d(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i + vec3(0, 0, 0)), hash31(i + vec3(1, 0, 0)), f.x),
			mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
			mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y),
		f.z
	);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3d(p);
		p = p * 2.03 + vec3(11.3, 7.7, 13.1);
		a *= 0.5;
	}
	return v;
}

vec3 star_layer(vec3 dir, float density, float threshold, float min_rad, float max_rad, float brightness, float twinkle_spd) {
	vec3 p = dir * density;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	vec3 rnd = hash33(id + vec3(17.3, 29.1, 41.7));
	float h = hash31(id + vec3(7.13, 19.7, 3.1));
	if (h < threshold) {
		return vec3(0.0);
	}
	// Keep star center well inside voxel so circular halo never touches cell borders
	vec3 offset = (rnd - 0.5) * 0.34;
	float d = length(f - offset);
	float rad = mix(min_rad, max_rad, fract(h * 73.1));
	float core = smoothstep(rad, 0.0, d);
	float cell_fade = smoothstep(0.32, 0.06, d);
	float halo = exp(-d / max(rad * 0.75, 0.001)) * 0.38 * cell_fade;
	float tw = 0.80 + 0.20 * sin(TIME * twinkle_spd + h * 62.83);
	vec3 tint = mix(vec3(0.72, 0.86, 1.0), vec3(1.0, 0.92, 0.76), rnd.x);
	if (rnd.y > 0.85) {
		tint = vec3(1.0, 0.78, 0.62);
	}
	return tint * (core * core + halo) * brightness * tw;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	// Smooth tilted Milky Way galactic dust plane + seamless multi-octave nebula
	float gal_plane = dot(dir, normalize(vec3(0.28, 0.82, -0.50)));
	float band = exp(-gal_plane * gal_plane * 3.4);
	float neb_a = fbm(dir * 2.2 + vec3(15.5, 12.4, 18.2));
	float neb_b = fbm(dir * 4.4 + vec3(23.1, 19.3, 14.8));

	vec3 bg = vec3(0.007, 0.011, 0.022);
	vec3 neb = mix(nebula_color_a, nebula_color_b, smoothstep(0.25, 0.75, neb_a));
	neb = mix(neb, nebula_color_c, smoothstep(0.35, 0.80, neb_b) * 0.55);
	vec3 col = bg + neb * (0.24 + 0.85 * band) * (0.45 + 0.85 * neb_a);

	// Distant solar disc + warm corona glare
	float sun_dot = max(dot(dir, normalize(sun_dir)), 0.0);
	col += vec3(1.0, 0.92, 0.76) * pow(sun_dot, 520.0) * 4.5;
	col += vec3(1.0, 0.74, 0.44) * pow(sun_dot, 22.0) * 0.16;

	// Multi-scale circular twinkling stars with zero cell clipping
	col += star_layer(dir, 34.0, 0.915, 0.055, 0.110, 2.3, 2.1);
	col += star_layer(dir + vec3(3.37), 72.0, 0.875, 0.080, 0.145, 1.4, 3.0);
	col += star_layer(dir + vec3(7.71), 132.0, 0.840, 0.100, 0.175, 0.72 * (0.45 + 0.85 * band), 1.4);

	COLOR = col;
}
