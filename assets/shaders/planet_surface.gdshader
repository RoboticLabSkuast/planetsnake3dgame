shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform int biome_id = 0; // 0 = Terra, 1 = Volcanic, 2 = Desert
uniform float normal_scale : hint_range(0.0, 3.0) = 1.65;
uniform float grid_n = 10.0;

uniform vec3 food_dirs[12];
uniform int food_count = 0;
uniform vec3 bonus_dir = vec3(0.0, 1.0, 0.0);
uniform float bonus_active = 0.0;
uniform vec3 lamp_dirs[16];
uniform int lamp_count = 0;
uniform float cell_arc = 0.157;
uniform vec3 sun_dir = vec3(-0.75, 0.52, 0.40);
uniform vec3 atmosphere_tint : source_color = vec3(0.28, 0.62, 1.0);

varying vec3 v_sphere_pos;

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

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3d(p);
		p = p * 2.07 + vec3(3.1, 1.7, 2.3);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_sphere_pos = normalize(VERTEX);
}

void fragment() {
	vec3 base_col = texture(albedo_tex, UV).rgb;
	vec3 norm_map = texture(normal_tex, UV).rgb;
	float rough = texture(roughness_tex, UV).r;

	// Seamless 3D macro variation across the entire sphere
	float macro_a = fbm3(v_sphere_pos * 3.8);
	float macro_b = fbm3(v_sphere_pos * 9.5 + vec3(4.2));
	float seam_dist = min(min(fract(UV.x), 1.0 - fract(UV.x)), min(fract(UV.y), 1.0 - fract(UV.y)));
	float seam_factor = 1.0 - smoothstep(0.015, 0.095, seam_dist);

	vec3 emission = vec3(0.0);
	float ao_val = mix(1.0, 0.52, seam_factor);

	if (biome_id == 0) {
		// Mossy Terra: damp slate rock & rich forest moss blooms
		float moss_mask = smoothstep(0.42, 0.72, macro_a * 0.75 + macro_b * 0.25 + seam_factor * 0.28);
		vec3 lush_moss = vec3(0.036, 0.095, 0.024) * (0.68 + 0.62 * macro_b);
		base_col = mix(base_col * (0.50 + 0.42 * macro_a), lush_moss, moss_mask * 0.62);
		rough = mix(rough, 0.90, moss_mask * 0.35);
		// Damp specular sheen on stone flats
		rough = mix(rough, 0.24, smoothstep(0.58, 0.85, 1.0 - macro_b) * 0.45 * (1.0 - moss_mask));
	} else if (biome_id == 1) {
		// Volcanic Basalt: dark obsidian stone & glowing pulsing magma veins
		float heat = smoothstep(0.30, 0.78, macro_a) * (0.72 + 0.28 * sin(TIME * 2.1 + macro_b * 6.2831));
		float magma_seam = seam_factor * (0.45 + 0.55 * heat);
		base_col *= (0.68 + 0.44 * macro_b);
		emission = vec3(1.55, 0.36, 0.04) * magma_seam * 0.95;
		rough = mix(rough, 0.22, (1.0 - seam_factor) * smoothstep(0.52, 0.85, macro_a) * 0.5);
	} else {
		// Desert Sandstone: warm ochre weathered rock & rippled sand seams
		float dune = smoothstep(0.36, 0.74, macro_a * 0.7 + macro_b * 0.3);
		base_col = mix(base_col * 0.56, base_col * vec3(0.78, 0.69, 0.56), dune);
		rough = mix(rough, 0.88, seam_factor * 0.35);
	}

	// Subtle contact shadow + soft warm beacon ring beneath all active apples
	float pulse = 0.70 + 0.30 * sin(TIME * 4.0);
	for (int i = 0; i < 12; i++) {
		if (i >= food_count) {
			break;
		}
		float ang = acos(clamp(dot(v_sphere_pos, normalize(food_dirs[i])), -1.0, 1.0));
		if (ang < cell_arc * 0.95) {
			float contact = exp(-pow(ang / (cell_arc * 0.26), 2.0));
			ao_val *= (1.0 - 0.38 * contact);
			float ring = exp(-pow((ang - cell_arc * 0.52) / (cell_arc * 0.11), 2.0));
			emission += vec3(0.85, 0.16, 0.12) * ring * 0.34 * pulse;
		}
	}

	if (bonus_active > 0.5) {
		float ang_b = acos(clamp(dot(v_sphere_pos, normalize(bonus_dir)), -1.0, 1.0));
		float ring_b = exp(-pow((ang_b - cell_arc * 0.58) / (cell_arc * 0.13), 2.0));
		float pulse_b = 0.65 + 0.35 * sin(TIME * 6.5);
		emission += vec3(1.2, 0.82, 0.15) * ring_b * 0.58 * pulse_b;
	}

	// Keep grid rows legible across twilight and midnight hemispheres
	float sun_ndotl = dot(v_sphere_pos, normalize(sun_dir));
	float sun_facing = smoothstep(-0.35, 0.55, sun_ndotl);
	float night_factor = 1.0 - smoothstep(-0.20, 0.30, sun_ndotl);
	vec3 seam_guide_col = (biome_id == 1) ? vec3(0.85, 0.32, 0.08) : ((biome_id == 2) ? vec3(0.45, 0.38, 0.25) : vec3(0.20, 0.48, 0.68));
	emission += seam_guide_col * seam_factor * night_factor * 0.22;

	// Warm street lamp glow pools illuminating tiles and grid rows softly on the dark side
	for (int i = 0; i < 16; i++) {
		if (i >= lamp_count) {
			break;
		}
		float ang_l = acos(clamp(dot(v_sphere_pos, normalize(lamp_dirs[i])), -1.0, 1.0));
		if (ang_l < cell_arc * 2.1) {
			float lamp_pool = exp(-pow(ang_l / (cell_arc * 0.88), 2.0));
			float row_boost = mix(0.18, 0.62, seam_factor);
			base_col += vec3(0.09, 0.06, 0.02) * lamp_pool * (0.30 + 0.70 * night_factor);
			emission += vec3(0.56, 0.38, 0.14) * lamp_pool * row_boost * (0.10 + 0.24 * night_factor);
		}
	}

	// Realistic atmospheric Rayleigh scattering at grazing sunlit limb angles
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float limb_haze = pow(1.0 - ndotv, 3.4) * (0.25 + 0.75 * sun_facing);
	base_col = mix(base_col, atmosphere_tint, limb_haze * 0.24);

	ALBEDO = clamp(base_col, vec3(0.0), vec3(1.0));
	NORMAL_MAP = norm_map;
	NORMAL_MAP_DEPTH = normal_scale;
	ROUGHNESS = clamp(rough, 0.12, 0.96);
	METALLIC = (biome_id == 1) ? 0.14 : 0.04;
	SPECULAR = 0.55;
	AO = ao_val;
	EMISSION = emission + atmosphere_tint * limb_haze * 0.12;
}
