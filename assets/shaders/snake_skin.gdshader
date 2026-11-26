shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform int skin_id = 0; // 0 = Emerald Viper, 1 = Magma Cobra, 2 = Frost Python, 3 = Royal Gold
uniform float boost_amount : hint_range(0.0, 1.0) = 0.0;
uniform float shield_amount : hint_range(0.0, 1.0) = 0.0;
uniform float magnet_amount : hint_range(0.0, 1.0) = 0.0;
uniform float frost_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 tex_col = texture(albedo_tex, UV).rgb;
	vec3 norm_map = texture(normal_tex, UV).rgb;
	float rough = texture(roughness_tex, UV).r * 0.72;

	// Separate belly plates (near u=0 or u=1) from dorsal scales (around u=0.5)
	float dorsal = 0.5 - 0.5 * cos(UV.x * 6.2831853);
	float lum = dot(tex_col, vec3(0.299, 0.587, 0.114));

	vec3 col = tex_col;
	float metallic = 0.08;
	if (skin_id == 1) {
		// Magma Cobra: obsidian charcoal scales with glowing crimson-orange flanks
		vec3 dark_scale = vec3(0.09, 0.06, 0.07) * (0.6 + 0.8 * lum);
		vec3 ember = vec3(0.95, 0.28, 0.06) * (0.45 + 0.75 * tex_col.r);
		vec3 belly = vec3(0.45, 0.24, 0.18) * (0.7 + 0.5 * lum);
		col = mix(belly, mix(dark_scale, ember, smoothstep(0.18, 0.42, tex_col.r) * (1.0 - smoothstep(0.55, 0.88, dorsal))), smoothstep(0.20, 0.40, dorsal));
	} else if (skin_id == 2) {
		// Frost Python: glacial sapphire & silver-cyan diamond scales
		vec3 ice_blue = vec3(0.08, 0.42, 0.78) * (0.55 + 0.85 * lum);
		vec3 silver = vec3(0.68, 0.86, 0.96) * (0.7 + 0.4 * lum);
		col = mix(silver, ice_blue, smoothstep(0.22, 0.45, dorsal));
		metallic = 0.14;
	} else if (skin_id == 3) {
		// Royal Gold Mamba: metallic burnished gold & bronze diamond scales
		vec3 bronze = vec3(0.45, 0.26, 0.05) * (0.6 + 0.8 * lum);
		vec3 gold = vec3(0.96, 0.74, 0.20) * (0.7 + 0.45 * lum);
		col = mix(gold * 1.05, mix(bronze, gold, smoothstep(0.30, 0.55, lum)), smoothstep(0.20, 0.42, dorsal));
		metallic = 0.42;
		rough *= 0.78;
	}

	// Dynamic shimmer pulses along spine for Boost and Power-Ups (kept strictly to outer rim & scale glints)
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim_pow = pow(1.0 - ndotv, 4.2);
	float spine_wave = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin(UV.y * 5.0 - TIME * 12.0));
	float scale_ridge = smoothstep(0.52, 0.90, norm_map.b);

	vec3 emission = vec3(0.0);
	if (skin_id == 1) {
		emission += vec3(0.42, 0.08, 0.01) * (1.0 - smoothstep(0.28, 0.78, dorsal)) * 0.48;
	}

	vec3 fx_glow = vec3(0.0);
	float fx_w = 0.0;
	if (boost_amount > 0.01) {
		fx_glow += vec3(0.18, 0.95, 0.58) * boost_amount;
		fx_w += boost_amount;
	}
	if (shield_amount > 0.01) {
		fx_glow += vec3(0.20, 0.98, 0.65) * shield_amount;
		fx_w += shield_amount;
	}
	if (magnet_amount > 0.01) {
		fx_glow += vec3(0.84, 0.28, 1.0) * magnet_amount;
		fx_w += magnet_amount;
	}
	if (frost_amount > 0.01) {
		fx_glow += vec3(0.25, 0.84, 1.0) * frost_amount;
		fx_w += frost_amount;
	}
	if (fx_w > 0.001) {
		vec3 fx_tint = fx_glow / max(fx_w, 1.0);
		float intensity = min(fx_w, 1.25);
		emission += fx_tint * intensity * (0.58 * rim_pow + 0.14 * spine_wave * scale_ridge);
	}

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	NORMAL_MAP = norm_map;
	NORMAL_MAP_DEPTH = 1.45;
	ROUGHNESS = clamp(rough, 0.14, 0.85);
	METALLIC = metallic;
	CLEARCOAT = 0.38;
	CLEARCOAT_ROUGHNESS = 0.20;
	RIM = 0.30;
	RIM_TINT = 0.45;
	EMISSION = emission;
}
