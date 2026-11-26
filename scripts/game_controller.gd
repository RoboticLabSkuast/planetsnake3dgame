class_name GameController
extends Node3D
## Main 3D world controller for Planet Snake 3D.
## Manages the realistic PBR planet, parallel-transport & 3D chase cameras,
## dynamic scaly snake mesh, sculpted head/tongue animation, particles, audio, and persistence.

signal game_state_changed(state: int)
signal hud_updated(data: Dictionary)
signal floating_popup(screen_pos: Vector2, text: String, color: Color)
signal milestone_banner(title: String, color: Color)

enum PlayState { MENU = 0, PLAYING = 1, PAUSED = 2, GAME_OVER = 3, VICTORY = 4 }
enum CameraMode { GLOBE_4WAY = 0, CHASE_3D = 1 }
enum TouchMode { AUTO = 0, SWIPE_ONLY = 1, DPAD_AND_SWIPE = 2 }
enum Biome { TERRA = 0, VOLCANIC = 1, DESERT = 2 }
enum SnakeSkin { EMERALD = 0, MAGMA = 1, FROST = 2, GOLD = 3 }

const PLANET_RADIUS := 4.0
const SAVE_PATH := "user://save_data.cfg"
const MAX_FOOD_POOL := 12
const SUN_DIR := Vector3(-0.74, 0.50, 0.44)
const MIN_GRID_N := 2
const MAX_GRID_N := 14

const GRID_SIZES := [8, 10, 14]
const BIOME_NAMES := ["terra", "volcanic", "desert"]
const BIOME_RIM_COLORS := [
	Color(0.28, 0.68, 1.0),
	Color(1.0, 0.36, 0.10),
	Color(0.95, 0.72, 0.38),
]
const BIOME_DUST_COLORS := [
	Color(0.55, 0.92, 0.45),
	Color(1.0, 0.48, 0.16),
	Color(0.98, 0.84, 0.52),
]
const SKIN_EYE_COLORS := [
	Color(0.95, 0.68, 0.14),
	Color(1.0, 0.38, 0.12),
	Color(0.52, 0.92, 1.0),
	Color(1.0, 0.86, 0.25),
]
const POWERUP_COLORS := [
	Color(0.24, 0.96, 0.66),
	Color(0.84, 0.34, 1.0),
	Color(0.32, 0.84, 1.0),
]

var play_state: int = PlayState.MENU
var selected_mode: int = SnakeLogic.GameMode.CLASSIC
var selected_biome: int = Biome.TERRA
var selected_size_idx: int = 1
var selected_grid_n: int = 10
var selected_speed_idx: int = SnakeLogic.SpeedTier.CLASSIC
var selected_skin: int = SnakeSkin.EMERALD
var camera_mode: int = CameraMode.GLOBE_4WAY
var touch_mode: int = TouchMode.AUTO
var audio_muted: bool = false
var high_quality: bool = true
var save_disabled: bool = false

var best_scores := {
	"classic": 0,
	"arcade": 0,
}
var stats := {
	"games_played": 0,
	"total_apples": 0,
	"max_length": 4,
	"best_combo": 1,
	"total_time": 0.0,
}

var grid: SphereGrid
var logic: SnakeLogic

# Scene visual nodes
var world_env: WorldEnvironment
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var cam_fill_light: DirectionalLight3D
var camera: Camera3D

var planet_mesh_inst: MeshInstance3D
var planet_shader_mat: ShaderMaterial
var clouds_mesh_inst: MeshInstance3D
var clouds_mat: ShaderMaterial
var atmosphere_mesh_inst: MeshInstance3D
var atmosphere_mat: ShaderMaterial
var moon_mesh_inst: MeshInstance3D
var space_dust_particles: GPUParticles3D

var snake_body_inst: MeshInstance3D
var snake_body_mesh: ArrayMesh
var snake_head_parts: Dictionary = {}
var snake_skin_mat: ShaderMaterial
var shield_head_aura: MeshInstance3D

var food_root: Node3D
var _food_nodes: Array[Node3D] = []
var bonus_node: Node3D
var powerup_node: Node3D
var _powerup_meshes: Array[MeshInstance3D] = []
var boulders_root: Node3D
var lamps_root: Node3D
var _lamp_dirs: PackedVector3Array = PackedVector3Array()
var eat_particles: GPUParticles3D
var gold_particles: GPUParticles3D
var boost_particles: GPUParticles3D
var slither_dust_particles: GPUParticles3D
var bonus_aura_particles: GPUParticles3D
var powerup_aura_particles: GPUParticles3D
var powerup_burst_particles: GPUParticles3D
var crash_particles: GPUParticles3D
var _shockwave_mesh: ArrayMesh
var _shockwaves: Array[Dictionary] = []
var _shooting_stars: Array[Dictionary] = []

# Audio players
var sfx_eat: AudioStreamPlayer
var sfx_eat_gold: AudioStreamPlayer
var sfx_turn: AudioStreamPlayer
var sfx_crash: AudioStreamPlayer
var sfx_ui_click: AudioStreamPlayer
var sfx_milestone: AudioStreamPlayer
var sfx_powerup: AudioStreamPlayer
var sfx_shield_break: AudioStreamPlayer
var ambient_player: AudioStreamPlayer

# Simulation & animation state
var _tick_accum: float = 0.0
var _slither_phase: float = 0.0
var _tongue_timer: float = 0.0
var _jaw_open_amt: float = 0.0
var _cam_zoom_factor: float = 1.0
var _cam_shake: float = 0.0
var _cam_transition: float = 1.0
var _menu_orbit_angle: float = 0.0
var _boosting: bool = false
var _boost_fx: float = 0.0
var _run_peak_combo: int = 1
var _last_milestone_len: int = 0

# Parallel-transport camera basis on sphere
var _cam_normal: Vector3 = Vector3(0.0, 0.0, 1.0)
var _cam_up: Vector3 = Vector3(0.0, 1.0, 0.0)
var _cam_right: Vector3 = Vector3(1.0, 0.0, 0.0)

# Cached resources
var _textures := {}
var _eye_mat: StandardMaterial3D
var _apple_mat: StandardMaterial3D
var _gold_apple_mat: StandardMaterial3D
var _stem_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _boulder_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _lamp_pole_mat: StandardMaterial3D
var _lamp_bulb_mat: StandardMaterial3D
var _powerup_burst_mat: StandardMaterial3D
var _powerup_aura_mat: StandardMaterial3D
var _slither_dust_mat: StandardMaterial3D
var _boost_mat: StandardMaterial3D


func _ready() -> void:
	_load_save_data()
	_load_assets()
	_build_environment_and_lights()
	_build_world_nodes()
	_build_audio()
	_apply_quality_settings()
	_update_camera_aspect()
	get_viewport().size_changed.connect(_update_camera_aspect)
	rebuild_world(true)
	set_play_state(PlayState.MENU)


func _process(delta: float) -> void:
	if not is_node_ready():
		return
	_slither_phase += delta * (9.5 if _boosting else 6.2)
	_tongue_timer += delta
	if _cam_shake > 0.0:
		_cam_shake = maxf(0.0, _cam_shake - delta * 2.8)

	if moon_mesh_inst != null:
		moon_mesh_inst.rotate_y(delta * 0.04)

	_update_shockwaves(delta)
	_update_shooting_stars(delta)
	_update_snake_fx_uniforms(delta)

	if play_state == PlayState.MENU:
		_menu_orbit_angle += delta * 0.18
		_animate_fruits(delta)
		_animate_snake_head(delta, 0.5)
		_update_menu_camera(delta)
		return

	if play_state != PlayState.PLAYING:
		_animate_fruits(delta)
		return

	logic.update_timers(delta)
	var interval := logic.get_tick_interval(_boosting)
	_tick_accum += delta

	while _tick_accum >= interval and play_state == PlayState.PLAYING:
		_tick_accum -= interval
		var events := logic.step_tick()
		_handle_tick_events(events)
		interval = logic.get_tick_interval(_boosting)

	var tick_alpha := clampf(_tick_accum / maxf(interval, 0.001), 0.0, 1.0)
	if not logic.alive or logic.won:
		tick_alpha = 1.0

	_update_snake_visuals(tick_alpha)
	_animate_snake_head(delta, tick_alpha)
	_animate_fruits(delta)
	_update_food_positions()
	_update_food_shader_uniforms()
	_update_gameplay_camera(delta, tick_alpha)
	_emit_hud_update()


func start_new_game() -> void:
	_tick_accum = 0.0
	_boosting = false
	_boost_fx = 0.0
	_cam_shake = 0.0
	_cam_transition = 0.0
	_run_peak_combo = 1
	_last_milestone_len = 4
	rebuild_world(false)
	set_play_state(PlayState.PLAYING)
	_emit_hud_update()


func play_ui_click() -> void:
	if not audio_muted and sfx_ui_click != null:
		sfx_ui_click.pitch_scale = randf_range(0.96, 1.04)
		sfx_ui_click.play()


func reset_stats() -> void:
	best_scores["classic"] = 0
	best_scores["arcade"] = 0
	stats = {
		"games_played": 0,
		"total_apples": 0,
		"max_length": 4,
		"best_combo": 1,
		"total_time": 0.0,
	}
	_save_data()
	_emit_hud_update()


func set_play_state(new_state: int) -> void:
	play_state = new_state
	if play_state != PlayState.PLAYING:
		_boosting = false
		if boost_particles != null:
			boost_particles.emitting = false
		if slither_dust_particles != null:
			slither_dust_particles.emitting = false
	emit_signal("game_state_changed", play_state)
	_emit_hud_update()


func toggle_pause() -> void:
	if play_state == PlayState.PLAYING:
		set_play_state(PlayState.PAUSED)
	elif play_state == PlayState.PAUSED:
		set_play_state(PlayState.PLAYING)


func set_boosting(active: bool) -> void:
	_boosting = active


func adjust_zoom(delta_steps: float) -> void:
	_cam_zoom_factor = clampf(_cam_zoom_factor - delta_steps * 0.08, 0.72, 1.48)


func apply_directional_input(screen_vec: Vector2) -> void:
	## Screen-space swipe / D-pad / WASD direction vector: x = right, y = up (+Y).
	if play_state != PlayState.PLAYING or not logic.alive:
		return
	if camera_mode == CameraMode.CHASE_3D:
		if absf(screen_vec.x) > 0.35 and absf(screen_vec.x) >= absf(screen_vec.y) * 0.55:
			logic.queue_relative_turn(1 if screen_vec.x > 0.0 else -1)
		return

	# Classic Globe 4-way: map screen vector into camera world basis
	var world_desired := (_cam_right * screen_vec.x + _cam_up * screen_vec.y)
	logic.queue_screen_direction(world_desired)


func apply_relative_turn(rel: int) -> void:
	if play_state != PlayState.PLAYING or not logic.alive:
		return
	logic.queue_relative_turn(rel)


func apply_settings(
	p_mode: int,
	p_biome: int,
	p_size_idx: int,
	p_speed_idx: int,
	p_cam_mode: int,
	p_touch_mode: int,
	p_muted: bool,
	p_high_quality: bool,
	p_skin_idx: int = -1
) -> void:
	var prev_biome := selected_biome
	var prev_skin := selected_skin
	var next_skin := p_skin_idx if p_skin_idx >= 0 else selected_skin
	var next_grid_n := selected_grid_n
	if p_size_idx >= 0 and p_size_idx != selected_size_idx and p_size_idx < GRID_SIZES.size():
		next_grid_n = GRID_SIZES[p_size_idx]
	var need_rebuild := (
		p_mode != selected_mode
		or p_biome != selected_biome
		or next_grid_n != selected_grid_n
		or p_speed_idx != selected_speed_idx
	)
	selected_mode = p_mode
	selected_biome = p_biome
	if p_size_idx >= 0 and p_size_idx < GRID_SIZES.size():
		selected_size_idx = p_size_idx
	selected_grid_n = clampi(next_grid_n, MIN_GRID_N, MAX_GRID_N)
	selected_speed_idx = p_speed_idx
	selected_skin = clampi(next_skin, 0, SKIN_EYE_COLORS.size() - 1)
	camera_mode = p_cam_mode
	touch_mode = p_touch_mode
	audio_muted = p_muted
	high_quality = p_high_quality

	_apply_audio_mute()
	_apply_quality_settings()
	_apply_skin_visuals()
	_save_data()
	if need_rebuild and play_state == PlayState.MENU:
		rebuild_world(true)
	elif prev_biome != selected_biome or prev_skin != selected_skin:
		_apply_biome_visuals()
		_apply_skin_visuals()


func set_grid_size(n: int) -> void:
	var clamped := clampi(n, MIN_GRID_N, MAX_GRID_N)
	if clamped == selected_grid_n:
		return
	selected_grid_n = clamped
	selected_size_idx = 0 if clamped <= 8 else (1 if clamped <= 11 else 2)
	_save_data()
	if play_state == PlayState.MENU:
		rebuild_world(true)
	_emit_hud_update()


func toggle_mute() -> bool:
	audio_muted = not audio_muted
	_apply_audio_mute()
	_save_data()
	_emit_hud_update()
	return audio_muted


func _entity_cell_len() -> float:
	if grid == null:
		return 0.628
	return minf(PLANET_RADIUS * grid.cell_arc_angle, 1.15)


func rebuild_world(preview_only: bool) -> void:
	var n: int = clampi(selected_grid_n, MIN_GRID_N, MAX_GRID_N)
	grid = SphereGrid.new(n)
	logic = SnakeLogic.new(grid)
	logic.reset(selected_mode, selected_speed_idx)

	# Scale mesh subdivision smoothly for smaller 2x2..5x5 spheres as well as large 14x14 globes
	var sub_per_cell := maxi(3, ceili(36.0 / float(n)))
	planet_mesh_inst.mesh = grid.build_planet_mesh(PLANET_RADIUS, sub_per_cell)
	_apply_biome_visuals()

	# Rebuild snake head scaled to entity visual cap
	for ch in snake_head_parts.values():
		if ch is Node and ch.get_parent() == self:
			ch.queue_free()
	var cell_world_len := _entity_cell_len()
	var body_r := cell_world_len * 0.27
	_eye_mat = _create_eye_mat()
	snake_head_parts = ProceduralMeshes.build_snake_head_node(
		body_r,
		snake_skin_mat,
		_eye_mat,
		_create_pupil_mat(),
		_create_tongue_mat()
	)
	_attach_shield_head_aura(snake_head_parts["root"], body_r)
	add_child(snake_head_parts["root"])
	_apply_skin_visuals()

	# Rebuild sculpted food, obstacles, & dark-side street lamps proportional to cell size
	_rebuild_fruit_nodes(cell_world_len)
	_rebuild_boulder_nodes(cell_world_len)
	_rebuild_street_lamps(cell_world_len)

	# Reset parallel-transport camera basis directly over starting snake head
	var start_norm := grid.cell_normals[logic.snake_cells[0]]
	var start_fwd := grid.get_edge_tangent(logic.snake_cells[0], logic.head_dir)
	_cam_normal = start_norm
	_cam_up = (start_fwd - _cam_normal * start_fwd.dot(_cam_normal)).normalized()
	_cam_right = _cam_up.cross(_cam_normal).normalized()

	_update_snake_visuals(1.0)
	_update_food_positions()
	_update_food_shader_uniforms()
	if preview_only:
		_menu_orbit_angle = 0.0
		_update_menu_camera(0.0)
	else:
		_update_gameplay_camera(1.0, 1.0)


func is_mobile_platform() -> bool:
	var os_name := OS.get_name()
	return os_name == "Android" or os_name == "iOS"


func _is_mobile_gpu() -> bool:
	return is_mobile_platform() or RenderingServer.get_current_rendering_method() == "mobile"


func should_show_dpad() -> bool:
	if touch_mode == TouchMode.DPAD_AND_SWIPE:
		return true
	if touch_mode == TouchMode.SWIPE_ONLY:
		return false
	return is_mobile_platform()


func _handle_tick_events(events: Dictionary) -> void:
	if events["turned"] and not audio_muted and sfx_turn:
		sfx_turn.pitch_scale = randf_range(0.94, 1.08)
		sfx_turn.play()

	if events["shield_smashed"]:
		var smash_cid: int = int(events["smash_cell"])
		_cam_shake = 0.42
		if not audio_muted and sfx_shield_break:
			sfx_shield_break.play()
		_rebuild_boulder_nodes(_entity_cell_len())
		_trigger_color_burst(powerup_burst_particles, _powerup_burst_mat, smash_cid, POWERUP_COLORS[0])
		_trigger_shockwave(smash_cid, POWERUP_COLORS[0], 3.2)
		_spawn_score_popup(smash_cid, "SHIELD SMASH!", POWERUP_COLORS[0])
		emit_signal("milestone_banner", "SHIELD SHATTERED OBSTACLE!", POWERUP_COLORS[0])
		_vibrate(45)

	var ptype: int = int(events["collected_powerup"])
	if ptype != SnakeLogic.PowerUpType.NONE:
		var p_cid: int = int(events["powerup_cell"])
		var p_col: Color = POWERUP_COLORS[clampi(ptype, 0, 2)]
		var p_titles := ["SHIELD READY!", "MAGNET 2X!", "FROST SLOW!"]
		if not audio_muted and sfx_powerup:
			sfx_powerup.pitch_scale = randf_range(0.96, 1.06)
			sfx_powerup.play()
		_trigger_color_burst(powerup_burst_particles, _powerup_burst_mat, p_cid, p_col)
		_trigger_shockwave(p_cid, p_col, 2.8)
		_spawn_score_popup(p_cid, "%s +25" % p_titles[clampi(ptype, 0, 2)], p_col)
		emit_signal("milestone_banner", p_titles[clampi(ptype, 0, 2)], p_col)
		_vibrate(28)

	var pulled: Array = events.get("magnet_pulled_cells", [])
	for m_cid in pulled:
		_trigger_shockwave(int(m_cid), POWERUP_COLORS[1], 1.9)

	if events["ate_food"]:
		_jaw_open_amt = 1.0
		if not audio_muted and sfx_eat:
			sfx_eat.pitch_scale = randf_range(0.95, 1.08)
			sfx_eat.play()
		var eat_c: int = int(events["eat_cell"])
		var eat_col := Color(0.86, 0.42, 1.0) if logic.magnet_time_left > 0.0 else Color(1.0, 0.34, 0.28)
		_trigger_particles(eat_particles, eat_c)
		_trigger_shockwave(eat_c, eat_col, 2.1)
		var pts_txt := "2X +%d" % int(events["points_gained"]) if logic.magnet_time_left > 0.0 else "+%d" % int(events["points_gained"])
		_spawn_score_popup(eat_c, pts_txt, eat_col)
		_vibrate(18)

	elif events["ate_bonus"]:
		_jaw_open_amt = 1.0
		_cam_shake = 0.16
		if not audio_muted and sfx_eat_gold:
			sfx_eat_gold.play()
		var bonus_c: int = int(events["eat_cell"])
		_trigger_particles(gold_particles, bonus_c)
		_trigger_shockwave(bonus_c, Color(1.0, 0.86, 0.25), 2.8)
		_spawn_score_popup(bonus_c, "GOLDEN +%d!" % int(events["points_gained"]), Color(1.0, 0.86, 0.25))
		_vibrate(32)

	if events["ate_food"] or events["ate_bonus"] or ptype != SnakeLogic.PowerUpType.NONE:
		_update_food_positions()
		_record_best_score()
		if logic.combo > _run_peak_combo:
			_run_peak_combo = logic.combo
			if _run_peak_combo == 5:
				emit_signal("milestone_banner", "MAX COMBO x5!", Color(1.0, 0.85, 0.25))

		var cur_len := logic.snake_cells.size()
		for m_len in [10, 20, 35, 50, 75, 100]:
			if cur_len >= m_len and _last_milestone_len < m_len:
				_last_milestone_len = m_len
				if not audio_muted and sfx_milestone != null:
					sfx_milestone.play()
				emit_signal("milestone_banner", "LENGTH %d REACHED!" % m_len, Color(0.42, 0.96, 0.62))
				break

		if events["ate_food"] and logic.bonus_food_cell >= 0 and logic.bonus_time_left >= logic.bonus_max_time - 0.15:
			emit_signal("milestone_banner", "GOLDEN FRUIT APPEARED!", Color(1.0, 0.86, 0.28))

	if events["died"]:
		_cam_shake = 0.55
		if not logic.snake_cells.is_empty():
			var head_cid := logic.snake_cells[0]
			_trigger_particles(crash_particles, head_cid)
			_trigger_shockwave(head_cid, Color(1.0, 0.30, 0.12), 5.8)
		if not audio_muted and sfx_crash:
			sfx_crash.play()
		_vibrate(65)
		_record_run_stats()
		set_play_state(PlayState.GAME_OVER)
	elif events["won"]:
		_cam_shake = 0.25
		if not logic.snake_cells.is_empty():
			_trigger_shockwave(logic.snake_cells[0], Color(0.40, 1.0, 0.62), 6.0)
		if not audio_muted and sfx_milestone:
			sfx_milestone.play()
		_vibrate(45)
		_record_run_stats()
		set_play_state(PlayState.VICTORY)


func _record_best_score() -> void:
	var key := "arcade" if selected_mode == SnakeLogic.GameMode.ARCADE else "classic"
	if logic.score > int(best_scores[key]):
		best_scores[key] = logic.score
		_save_data()


func _record_run_stats() -> void:
	_record_best_score()
	stats["games_played"] = int(stats["games_played"]) + 1
	stats["total_apples"] = int(stats["total_apples"]) + logic.apples_eaten
	stats["max_length"] = maxi(int(stats["max_length"]), logic.snake_cells.size())
	stats["best_combo"] = maxi(int(stats["best_combo"]), _run_peak_combo)
	stats["total_time"] = float(stats["total_time"]) + logic.elapsed_time
	_save_data()


func _update_snake_visuals(tick_alpha: float) -> void:
	if logic == null or logic.snake_cells.is_empty():
		return
	var curr := logic.snake_cells
	var prev := logic.prev_cells
	if prev.size() < curr.size():
		prev = prev.duplicate()
		while prev.size() < curr.size():
			prev.append(prev[prev.size() - 1])

	var spine_dirs := PackedVector3Array()
	spine_dirs.resize(curr.size())
	for i in range(curr.size()):
		var p_a := grid.cell_normals[prev[i]]
		var p_b := grid.cell_normals[curr[i]]
		spine_dirs[i] = grid.slerp_surface(p_a, p_b, tick_alpha)

	var cell_world_len := _entity_cell_len()
	var body_r := cell_world_len * 0.27
	ProceduralMeshes.update_snake_body_mesh(
		snake_body_mesh,
		spine_dirs,
		PLANET_RADIUS,
		body_r,
		cell_world_len,
		_slither_phase
	)

	# Position and orient sculpted viper head smoothly at spine_dirs[0]
	var head_root: Node3D = snake_head_parts.get("root")
	if head_root == null:
		return
	var head_up := spine_dirs[0]
	var fwd_a := grid.get_edge_tangent(prev[0], logic.prev_head_dir)
	var fwd_b := grid.get_edge_tangent(curr[0], logic.head_dir)
	var head_fwd := fwd_a.lerp(fwd_b, tick_alpha)
	head_fwd = (head_fwd - head_up * head_fwd.dot(head_up))
	if head_fwd.length_squared() < 1e-6:
		head_fwd = grid.get_edge_tangent(curr[0], logic.head_dir)
	head_fwd = head_fwd.normalized()

	var right := head_fwd.cross(head_up).normalized()
	var ortho_fwd := head_up.cross(right).normalized()
	var head_surf_r := PLANET_RADIUS + SphereGrid.surface_bump(head_up)
	head_root.global_position = head_up * (head_surf_r + body_r * 0.68)
	# Head mesh faces -Z with +Y up
	head_root.global_basis = Basis(right, head_up, -ortho_fwd).orthonormalized()

	if slither_dust_particles != null:
		slither_dust_particles.global_position = head_up * (head_surf_r + body_r * 0.18)
		slither_dust_particles.emitting = (play_state == PlayState.PLAYING and logic.alive and not logic.won)
	if boost_particles != null:
		boost_particles.global_position = head_up * (head_surf_r + body_r * 0.60) - ortho_fwd * (body_r * 0.85)
		boost_particles.emitting = (_boosting and play_state == PlayState.PLAYING and logic.alive and not logic.won)
	if shield_head_aura != null:
		shield_head_aura.visible = logic.shield_active
		if shield_head_aura.visible:
			var pulse := 1.0 + 0.08 * sin(_slither_phase * 1.4)
			shield_head_aura.scale = Vector3(pulse, pulse, pulse)


func _animate_snake_head(delta: float, _tick_alpha: float) -> void:
	var jaw_pivot: Node3D = snake_head_parts.get("jaw_pivot")
	var tongue_pivot: Node3D = snake_head_parts.get("tongue_pivot")
	if jaw_pivot == null or tongue_pivot == null:
		return

	# Subtle anticipation mouth opening when close to any active apple
	var target_jaw := 0.0
	if play_state == PlayState.PLAYING and logic != null and not logic.food_cells.is_empty():
		var head_n := (snake_head_parts["root"] as Node3D).global_position.normalized()
		var thresh := grid.cell_arc_angle * 1.65
		for fc in logic.food_cells:
			if head_n.angle_to(grid.cell_normals[fc]) < thresh:
				target_jaw = 0.24
				break

	_jaw_open_amt = maxf(target_jaw, _jaw_open_amt - delta * 3.8)
	jaw_pivot.rotation_degrees.x = -_jaw_open_amt * 24.0

	# Periodic flicking forked tongue
	var cycle := fmod(_tongue_timer, 2.4)
	if cycle < 0.42:
		var t_env := sin((cycle / 0.42) * PI)
		tongue_pivot.visible = true
		tongue_pivot.scale.z = 0.25 + 0.95 * t_env
		tongue_pivot.rotation_degrees.x = sin(cycle * 44.0) * 14.0
	else:
		tongue_pivot.visible = false


func _orient_basis_on_normal(n: Vector3) -> Basis:
	var up_ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var right := up_ref.cross(n).normalized()
	var fwd := n.cross(right).normalized()
	return Basis(right, n, fwd).orthonormalized()


func _place_on_cell(node: Node3D, cid: int, lift: float) -> void:
	var n := grid.cell_normals[cid]
	node.global_position = n * (PLANET_RADIUS + SphereGrid.surface_bump(n) + lift)
	node.global_basis = _orient_basis_on_normal(n)


func _update_food_positions() -> void:
	var cell_r := _entity_cell_len() * 0.36
	var active_count := mini(logic.food_cells.size(), _food_nodes.size())
	for i in range(_food_nodes.size()):
		var fnode := _food_nodes[i]
		if i < active_count:
			fnode.visible = true
			_place_on_cell(fnode, logic.food_cells[i], cell_r * 0.96)
			fnode.rotate_object_local(Vector3.UP, float(logic.food_cells[i] % 11) * 0.57)
		else:
			fnode.visible = false

	if logic.bonus_food_cell >= 0:
		bonus_node.visible = true
		var cell_r_b := _entity_cell_len() * 0.40
		_place_on_cell(bonus_node, logic.bonus_food_cell, cell_r_b * 1.05)
	else:
		bonus_node.visible = false
	if bonus_aura_particles != null:
		bonus_aura_particles.emitting = bonus_node.visible

	if powerup_node != null:
		var has_p := (logic.powerup_cell >= 0 and logic.powerup_type != SnakeLogic.PowerUpType.NONE)
		powerup_node.visible = has_p
		if has_p:
			var p_r := _entity_cell_len() * 0.42
			_place_on_cell(powerup_node, logic.powerup_cell, p_r * 1.05)
			for k in range(_powerup_meshes.size()):
				_powerup_meshes[k].visible = (k == logic.powerup_type)
			if _powerup_aura_mat != null:
				var col: Color = POWERUP_COLORS[clampi(logic.powerup_type, 0, 2)]
				_powerup_aura_mat.albedo_color = col
				_powerup_aura_mat.emission = col
		if powerup_aura_particles != null:
			powerup_aura_particles.emitting = has_p


func _animate_fruits(delta: float) -> void:
	var cell_r := _entity_cell_len() * 0.36
	var active_count := mini(logic.food_cells.size(), _food_nodes.size())
	for i in range(active_count):
		var fnode := _food_nodes[i]
		if not fnode.visible:
			continue
		var fn := grid.cell_normals[logic.food_cells[i]]
		var bob := sin(_slither_phase * 0.65 + float(i) * 0.85) * cell_r * 0.13
		fnode.global_position = fn * (PLANET_RADIUS + SphereGrid.surface_bump(fn) + cell_r * 0.96 + bob)
		fnode.rotate_object_local(Vector3.UP, delta * (1.1 + 0.15 * float(i % 3)))

	if bonus_node.visible and logic.bonus_food_cell >= 0:
		var bn := grid.cell_normals[logic.bonus_food_cell]
		var bob_b := sin(_slither_phase * 0.95) * cell_r * 0.15
		bonus_node.global_position = bn * (PLANET_RADIUS + SphereGrid.surface_bump(bn) + cell_r * 1.10 + bob_b)
		bonus_node.rotate_object_local(Vector3.UP, delta * 2.4)

	if powerup_node != null and powerup_node.visible and logic.powerup_cell >= 0:
		var pn := grid.cell_normals[logic.powerup_cell]
		var bob_p := sin(_slither_phase * 1.15) * cell_r * 0.18
		powerup_node.global_position = pn * (PLANET_RADIUS + SphereGrid.surface_bump(pn) + cell_r * 1.24 + bob_p)
		powerup_node.rotate_object_local(Vector3.UP, delta * 2.8)


func _update_food_shader_uniforms() -> void:
	if planet_shader_mat == null:
		return
	var dirs := PackedVector3Array()
	dirs.resize(MAX_FOOD_POOL)
	var count := mini(logic.food_cells.size(), MAX_FOOD_POOL)
	for i in range(MAX_FOOD_POOL):
		dirs[i] = grid.cell_normals[logic.food_cells[i]] if i < count else Vector3.UP
	planet_shader_mat.set_shader_parameter("food_dirs", dirs)
	planet_shader_mat.set_shader_parameter("food_count", count)

	if logic.bonus_food_cell >= 0:
		planet_shader_mat.set_shader_parameter("bonus_dir", grid.cell_normals[logic.bonus_food_cell])
		planet_shader_mat.set_shader_parameter("bonus_active", 1.0)
	else:
		planet_shader_mat.set_shader_parameter("bonus_active", 0.0)


func _update_menu_camera(delta: float) -> void:
	# Dramatic Subway-Surfers-style hero horizon close-up over the sunlit snake & globe
	var yaw := 0.24 + sin(_menu_orbit_angle * 0.7) * 0.26
	var pitch := 0.36 + cos(_menu_orbit_angle * 0.5) * 0.05
	var vp_size := get_viewport().get_visible_rect().size
	var is_portrait := vp_size.x < vp_size.y

	var dist := PLANET_RADIUS * (2.42 if is_portrait else 2.24)
	var orbit_dir := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	).normalized()
	var desired_pos := orbit_dir * dist

	if delta == 0.0:
		camera.global_position = desired_pos
	else:
		camera.global_position = camera.global_position.lerp(desired_pos, clampf(delta * 4.5, 0.0, 1.0))

	# Look slightly above center so curved planet fills lower/mid hero zone and stars fill upper sky
	var look_target := Vector3(0.0, 0.72 if is_portrait else 0.45, 0.0)
	camera.look_at(look_target, Vector3.UP)
	if delta > 0.0:
		camera.fov = lerpf(camera.fov, 44.0, clampf(delta * 6.0, 0.0, 1.0))
	_sync_cam_fill_light()


func _update_gameplay_camera(delta: float, _tick_alpha: float) -> void:
	var head_root: Node3D = snake_head_parts.get("root")
	if head_root == null:
		return
	var target_n := head_root.global_position.normalized()
	var head_fwd := -head_root.global_basis.z.normalized()
	_cam_transition = minf(1.0, _cam_transition + delta * 1.8)
	var swoop_blend := clampf(delta * (5.8 if _cam_transition >= 0.99 else 7.5), 0.0, 1.0)
	var target_fov := 49.5 if (_boosting and play_state == PlayState.PLAYING) else 44.0
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 7.2, 0.0, 1.0))

	var dist := PLANET_RADIUS * 2.85 * _cam_zoom_factor
	if camera_mode == CameraMode.CHASE_3D:
		# Close-up behind-the-head 3D chase camera with clear sightline ahead over the horizon
		var cam_alt := 2.35 * _cam_zoom_factor
		var chase_dir := (target_n * 0.88 - head_fwd * 0.47).normalized()
		var desired_pos := chase_dir * (PLANET_RADIUS + cam_alt)
		var look_ahead := (target_n + head_fwd * 0.25).normalized() * (PLANET_RADIUS * 0.92)
		if _cam_shake > 0.0:
			desired_pos += (head_fwd.cross(target_n).normalized() * randf_range(-1.0, 1.0) + target_n * randf_range(-1.0, 1.0)) * (_cam_shake * 0.12)
		camera.global_position = camera.global_position.lerp(desired_pos, clampf(delta * 7.5, 0.0, 1.0))
		camera.look_at(look_ahead, target_n)
		_cam_normal = camera.global_position.normalized()
		_cam_up = camera.global_basis.y.normalized()
		_cam_right = camera.global_basis.x.normalized()
	else:
		# Parallel-transport minimal-arc rotation so screen Up/Down/Left/Right stays rock-steady
		var step_n := _cam_normal.slerp(target_n, swoop_blend).normalized()
		var rot := Quaternion(_cam_normal, step_n)
		_cam_normal = step_n
		_cam_up = (rot * _cam_up).normalized()
		_cam_up = (_cam_up - _cam_normal * _cam_up.dot(_cam_normal)).normalized()
		_cam_right = _cam_up.cross(_cam_normal).normalized()

		# Subtle forward look-ahead bias so player sees slightly farther ahead
		var cam_dir := (_cam_normal + head_fwd * 0.06).normalized()
		var desired_pos := cam_dir * dist
		if _cam_shake > 0.0:
			desired_pos += (_cam_right * randf_range(-1.0, 1.0) + _cam_up * randf_range(-1.0, 1.0)) * (_cam_shake * 0.16)
		if _cam_transition < 0.99:
			camera.global_position = camera.global_position.lerp(desired_pos, swoop_blend)
		else:
			camera.global_position = desired_pos
		camera.look_at(Vector3.ZERO, _cam_up)

	_sync_cam_fill_light()


func _sync_cam_fill_light() -> void:
	if cam_fill_light == null or camera == null:
		return
	var cam_dir := camera.global_position.normalized()
	cam_fill_light.global_position = camera.global_position
	cam_fill_light.look_at(Vector3.ZERO, Vector3.UP if absf(cam_dir.y) < 0.9 else Vector3.RIGHT)


func _load_assets() -> void:
	var tex_names := [
		"terra_albedo", "terra_normal", "terra_roughness",
		"volcanic_albedo", "volcanic_normal", "volcanic_roughness",
		"desert_albedo", "desert_normal", "desert_roughness",
		"snake_albedo", "snake_normal", "snake_roughness",
		"apple_albedo", "apple_normal", "apple_roughness", "gold_apple_albedo",
		"boulder_albedo", "boulder_normal", "boulder_roughness",
	]
	for tname in tex_names:
		_textures[tname] = load("res://assets/textures/%s.png" % tname)

	snake_skin_mat = ShaderMaterial.new()
	snake_skin_mat.shader = load("res://assets/shaders/snake_skin.gdshader")
	snake_skin_mat.set_shader_parameter("albedo_tex", _textures["snake_albedo"])
	snake_skin_mat.set_shader_parameter("normal_tex", _textures["snake_normal"])
	snake_skin_mat.set_shader_parameter("roughness_tex", _textures["snake_roughness"])
	snake_skin_mat.set_shader_parameter("skin_id", selected_skin)

	_apple_mat = StandardMaterial3D.new()
	_apple_mat.albedo_texture = _textures["apple_albedo"]
	_apple_mat.normal_enabled = true
	_apple_mat.normal_texture = _textures["apple_normal"]
	_apple_mat.normal_scale = 0.65
	_apple_mat.roughness_texture = _textures["apple_roughness"]
	_apple_mat.roughness = 0.72
	_apple_mat.clearcoat_enabled = true
	_apple_mat.clearcoat = 0.55
	_apple_mat.clearcoat_roughness = 0.14
	_apple_mat.emission_enabled = true
	_apple_mat.emission = Color(0.32, 0.03, 0.02)
	_apple_mat.emission_energy_multiplier = 0.45

	_gold_apple_mat = StandardMaterial3D.new()
	_gold_apple_mat.albedo_texture = _textures["gold_apple_albedo"]
	_gold_apple_mat.normal_enabled = true
	_gold_apple_mat.normal_texture = _textures["apple_normal"]
	_gold_apple_mat.metallic = 0.78
	_gold_apple_mat.roughness = 0.18
	_gold_apple_mat.emission_enabled = true
	_gold_apple_mat.emission = Color(0.95, 0.66, 0.12)
	_gold_apple_mat.emission_energy_multiplier = 0.55

	_stem_mat = StandardMaterial3D.new()
	_stem_mat.albedo_color = Color(0.32, 0.21, 0.12)
	_stem_mat.roughness = 0.86

	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_color = Color(0.22, 0.58, 0.20)
	_leaf_mat.roughness = 0.42
	_leaf_mat.subsurf_scatter_enabled = not _is_mobile_gpu()

	_boulder_mat = StandardMaterial3D.new()
	_boulder_mat.albedo_texture = _textures["boulder_albedo"]
	_boulder_mat.normal_enabled = true
	_boulder_mat.normal_texture = _textures["boulder_normal"]
	_boulder_mat.normal_scale = 1.4
	_boulder_mat.roughness_texture = _textures["boulder_roughness"]
	_boulder_mat.roughness = 0.95

	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_texture = _textures["terra_albedo"]
	_wall_mat.normal_enabled = true
	_wall_mat.normal_texture = _textures["terra_normal"]
	_wall_mat.normal_scale = 1.5
	_wall_mat.roughness_texture = _textures["terra_roughness"]
	_wall_mat.roughness = 0.86
	_wall_mat.albedo_color = Color(0.84, 0.86, 0.84)

	_lamp_pole_mat = StandardMaterial3D.new()
	_lamp_pole_mat.albedo_color = Color(0.20, 0.22, 0.26)
	_lamp_pole_mat.metallic = 0.72
	_lamp_pole_mat.roughness = 0.36

	_lamp_bulb_mat = StandardMaterial3D.new()
	_lamp_bulb_mat.albedo_color = Color(1.0, 0.88, 0.54)
	_lamp_bulb_mat.emission_enabled = true
	_lamp_bulb_mat.emission = Color(1.0, 0.72, 0.26)
	_lamp_bulb_mat.emission_energy_multiplier = 1.75


func _build_environment_and_lights() -> void:
	var sun_n := SUN_DIR.normalized()
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/starfield.gdshader")
	sky_mat.set_shader_parameter("sun_dir", sun_n)
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.10
	env.ssao_radius = 0.55
	env.ssao_intensity = 2.2
	env.glow_enabled = true
	env.glow_intensity = 0.46
	env.glow_bloom = 0.16
	env.glow_hdr_threshold = 0.96
	world_env.environment = env
	add_child(world_env)

	# Grazing 3/4 golden Sun key light with tight orthogonal frustum for silky crisp shadows
	sun_light = DirectionalLight3D.new()
	sun_light.light_color = Color(1.0, 0.94, 0.84)
	sun_light.light_energy = 2.10
	sun_light.shadow_enabled = true
	sun_light.shadow_bias = 0.015
	sun_light.shadow_normal_bias = 0.45
	sun_light.shadow_blur = 2.2
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun_light.directional_shadow_max_distance = 22.0
	sun_light.look_at_from_position(sun_n * 14.0, Vector3.ZERO, Vector3.UP)
	add_child(sun_light)

	# Cool planetary starlight/moonlight rim bounce from opposite hemisphere
	fill_light = DirectionalLight3D.new()
	fill_light.light_color = Color(0.40, 0.62, 1.0)
	fill_light.light_energy = 0.86
	fill_light.shadow_enabled = false
	fill_light.look_at_from_position(-sun_n * 14.0, Vector3.ZERO, Vector3.UP)
	add_child(fill_light)

	# Subtle camera-side readability fill (keeps twilight playable without flattening shadows)
	cam_fill_light = DirectionalLight3D.new()
	cam_fill_light.light_color = Color(0.75, 0.85, 1.0)
	cam_fill_light.light_energy = 0.16
	cam_fill_light.shadow_enabled = false
	add_child(cam_fill_light)

	camera = Camera3D.new()
	camera.fov = 44.0
	camera.near = 0.1
	camera.far = 150.0
	camera.current = true
	add_child(camera)


func _update_camera_aspect() -> void:
	var vp := get_viewport()
	if vp == null or camera == null:
		return
	var sz := vp.get_visible_rect().size
	camera.keep_aspect = Camera3D.KEEP_WIDTH if sz.x < sz.y else Camera3D.KEEP_HEIGHT


func _build_world_nodes() -> void:
	planet_shader_mat = ShaderMaterial.new()
	planet_shader_mat.shader = load("res://assets/shaders/planet_surface.gdshader")

	planet_mesh_inst = MeshInstance3D.new()
	planet_mesh_inst.name = "PlanetSphere"
	planet_mesh_inst.material_override = planet_shader_mat
	planet_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(planet_mesh_inst)

	clouds_mat = ShaderMaterial.new()
	clouds_mat.shader = load("res://assets/shaders/planet_clouds.gdshader")
	var cloud_sphere := SphereMesh.new()
	cloud_sphere.radius = PLANET_RADIUS * 1.028
	cloud_sphere.height = PLANET_RADIUS * 2.056
	cloud_sphere.radial_segments = 40
	cloud_sphere.rings = 20
	clouds_mesh_inst = MeshInstance3D.new()
	clouds_mesh_inst.name = "CloudShell"
	clouds_mesh_inst.mesh = cloud_sphere
	clouds_mesh_inst.material_override = clouds_mat
	clouds_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(clouds_mesh_inst)

	atmosphere_mat = ShaderMaterial.new()
	atmosphere_mat.shader = load("res://assets/shaders/atmosphere.gdshader")
	var atmo_sphere := SphereMesh.new()
	atmo_sphere.radius = PLANET_RADIUS * 1.045
	atmo_sphere.height = PLANET_RADIUS * 2.09
	atmo_sphere.radial_segments = 48
	atmo_sphere.rings = 24
	atmosphere_mesh_inst = MeshInstance3D.new()
	atmosphere_mesh_inst.name = "AtmosphereShell"
	atmosphere_mesh_inst.mesh = atmo_sphere
	atmosphere_mesh_inst.material_override = atmosphere_mat
	atmosphere_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atmosphere_mesh_inst)

	snake_body_mesh = ArrayMesh.new()
	snake_body_inst = MeshInstance3D.new()
	snake_body_inst.name = "SnakeBody"
	snake_body_inst.mesh = snake_body_mesh
	snake_body_inst.material_override = snake_skin_mat
	snake_body_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(snake_body_inst)

	boulders_root = Node3D.new()
	boulders_root.name = "Boulders"
	add_child(boulders_root)

	lamps_root = Node3D.new()
	lamps_root.name = "StreetLamps"
	add_child(lamps_root)

	food_root = Node3D.new()
	food_root.name = "FoodRoot"
	add_child(food_root)

	bonus_node = Node3D.new()
	bonus_node.name = "BonusRoot"
	add_child(bonus_node)

	powerup_node = Node3D.new()
	powerup_node.name = "PowerUpRoot"
	add_child(powerup_node)

	eat_particles = _create_burst_particles(Color(1.0, 0.24, 0.20))
	gold_particles = _create_burst_particles(Color(1.0, 0.85, 0.22))
	crash_particles = _create_burst_particles(Color(1.0, 0.42, 0.16), 44, 2.0, 5.2, 0.72)
	powerup_burst_particles = _create_burst_particles(Color(0.28, 0.96, 0.72), 34, 1.8, 4.4, 0.62)
	_powerup_burst_mat = ((powerup_burst_particles.draw_pass_1 as SphereMesh).material) as StandardMaterial3D
	add_child(eat_particles)
	add_child(gold_particles)
	add_child(crash_particles)
	add_child(powerup_burst_particles)

	slither_dust_particles = _create_trail_particles(Color(0.55, 0.92, 0.45), 24, 0.45, Vector2(0.015, 0.032), 0.55)
	_slither_dust_mat = ((slither_dust_particles.draw_pass_1 as SphereMesh).material) as StandardMaterial3D
	add_child(slither_dust_particles)

	boost_particles = _create_trail_particles(Color(0.22, 0.96, 0.72), 44, 0.34, Vector2(0.022, 0.044), 1.45)
	_boost_mat = ((boost_particles.draw_pass_1 as SphereMesh).material) as StandardMaterial3D
	add_child(boost_particles)

	bonus_aura_particles = _create_orbit_particles(Color(1.0, 0.88, 0.28), 18, 0.34)
	bonus_node.add_child(bonus_aura_particles)

	powerup_aura_particles = _create_orbit_particles(Color(0.28, 0.96, 0.72), 18, 0.32)
	_powerup_aura_mat = ((powerup_aura_particles.draw_pass_1 as SphereMesh).material) as StandardMaterial3D
	powerup_node.add_child(powerup_aura_particles)

	_init_shockwave_pool()
	_init_shooting_stars()

	# Distant cratered Moon and drifting cosmic dust motes for orbital depth
	var moon_sphere := SphereMesh.new()
	moon_sphere.radius = 1.25
	moon_sphere.height = 2.50
	moon_sphere.radial_segments = 32
	moon_sphere.rings = 16
	var moon_mat := StandardMaterial3D.new()
	moon_mat.albedo_texture = _textures["boulder_albedo"]
	moon_mat.normal_enabled = true
	moon_mat.normal_texture = _textures["boulder_normal"]
	moon_mat.roughness_texture = _textures["boulder_roughness"]
	moon_mat.albedo_color = Color(0.76, 0.78, 0.84)
	moon_mat.uv1_scale = Vector3(3.0, 2.0, 1.0)
	moon_mesh_inst = MeshInstance3D.new()
	moon_mesh_inst.name = "DistantMoon"
	moon_mesh_inst.mesh = moon_sphere
	moon_mesh_inst.material_override = moon_mat
	moon_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon_mesh_inst.position = Vector3(-9.2, 8.6, -15.5)
	add_child(moon_mesh_inst)

	space_dust_particles = _create_space_dust_particles()
	add_child(space_dust_particles)


func _create_burst_particles(col: Color, amt: int = 24, spd_min: float = 1.4, spd_max: float = 3.2, life: float = 0.55) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amt
	p.lifetime = life
	p.emitting = false

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 180.0
	pmat.initial_velocity_min = spd_min
	pmat.initial_velocity_max = spd_max
	pmat.gravity = Vector3.ZERO
	pmat.damping_min = 2.0
	pmat.damping_max = 3.5
	pmat.scale_min = 0.045
	pmat.scale_max = 0.11
	p.process_material = pmat

	p.draw_pass_1 = _make_glow_speck_mesh(col, 2.2)
	return p


func _create_trail_particles(col: Color, amt: int, life: float, scale_rng: Vector2, spd_max: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amt
	p.lifetime = life
	p.local_coords = false
	p.emitting = false

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = 0.14
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 180.0
	pmat.initial_velocity_min = spd_max * 0.25
	pmat.initial_velocity_max = spd_max
	pmat.gravity = Vector3.ZERO
	pmat.damping_min = 1.4
	pmat.damping_max = 2.6
	pmat.scale_min = scale_rng.x
	pmat.scale_max = scale_rng.y
	p.process_material = pmat

	p.draw_pass_1 = _make_glow_speck_mesh(col, 2.0)
	return p


func _create_orbit_particles(col: Color, amt: int, rad: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amt
	p.lifetime = 0.85
	p.local_coords = true
	p.emitting = false

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = rad
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 180.0
	pmat.initial_velocity_min = 0.10
	pmat.initial_velocity_max = 0.36
	pmat.gravity = Vector3.ZERO
	pmat.scale_min = 0.025
	pmat.scale_max = 0.055
	p.process_material = pmat

	p.draw_pass_1 = _make_glow_speck_mesh(col, 2.3)
	return p


func _make_glow_speck_mesh(col: Color, glow: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 4
	var smat := StandardMaterial3D.new()
	smat.albedo_color = col
	smat.emission_enabled = true
	smat.emission = col
	smat.emission_energy_multiplier = glow
	sphere.material = smat
	return sphere


func _trigger_color_burst(p: GPUParticles3D, mat: StandardMaterial3D, cell_id: int, col: Color) -> void:
	if mat != null:
		mat.albedo_color = col
		mat.emission = col
	_trigger_particles(p, cell_id)


func _init_shockwave_pool() -> void:
	_shockwave_mesh = ProceduralMeshes.build_shockwave_ring_mesh(0.24, 0.31)
	for _i in range(5):
		var inst := MeshInstance3D.new()
		inst.mesh = _shockwave_mesh
		inst.visible = false
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = false
		inst.material_override = mat
		add_child(inst)
		_shockwaves.append({"node": inst, "mat": mat, "active": false, "t": 0.0, "dur": 0.45, "max_s": 3.5, "col": Color.WHITE})


func _trigger_shockwave(cell_id: int, col: Color, max_scale: float = 3.4) -> void:
	if cell_id < 0 or _shockwaves.is_empty():
		return
	var chosen: Dictionary = _shockwaves[0]
	for entry in _shockwaves:
		if not bool(entry["active"]):
			chosen = entry
			break
		if float(entry["t"]) > float(chosen["t"]):
			chosen = entry
	var inst: MeshInstance3D = chosen["node"]
	var n := grid.cell_normals[cell_id]
	var lift := PLANET_RADIUS * grid.cell_arc_angle * 0.08
	inst.global_position = n * (PLANET_RADIUS + SphereGrid.surface_bump(n) + lift)
	inst.global_basis = _orient_basis_on_normal(n)
	inst.scale = Vector3(0.55, 1.0, 0.55)
	inst.visible = true
	chosen["active"] = true
	chosen["t"] = 0.0
	chosen["dur"] = 0.44
	chosen["max_s"] = max_scale
	chosen["col"] = col


func _update_shockwaves(delta: float) -> void:
	for entry in _shockwaves:
		if not bool(entry["active"]):
			continue
		var t: float = float(entry["t"]) + delta
		var dur: float = float(entry["dur"])
		entry["t"] = t
		var inst: MeshInstance3D = entry["node"]
		if t >= dur:
			entry["active"] = false
			inst.visible = false
			continue
		var u := t / dur
		var s := lerpf(0.55, float(entry["max_s"]), 1.0 - pow(1.0 - u, 2.2))
		inst.scale = Vector3(s, 1.0, s)
		var col: Color = entry["col"]
		var mat: StandardMaterial3D = entry["mat"]
		mat.albedo_color = Color(col.r, col.g, col.b, (1.0 - u) * 0.82)


func _init_shooting_stars() -> void:
	var streak_mesh := BoxMesh.new()
	streak_mesh.size = Vector3(0.04, 0.04, 1.9)
	for i in range(2):
		var inst := MeshInstance3D.new()
		inst.mesh = streak_mesh
		inst.visible = false
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.85, 0.95, 1.0, 0.0)
		inst.material_override = mat
		add_child(inst)
		_shooting_stars.append({
			"node": inst,
			"mat": mat,
			"cooldown": 1.6 + float(i) * 2.8,
			"t": 0.0,
			"dur": 0.85,
			"start": Vector3.ZERO,
			"end": Vector3.ZERO,
			"active": false,
		})


func _update_shooting_stars(delta: float) -> void:
	for s in _shooting_stars:
		var inst: MeshInstance3D = s["node"]
		var mat: StandardMaterial3D = s["mat"]
		if not bool(s["active"]):
			s["cooldown"] = float(s["cooldown"]) - delta
			if float(s["cooldown"]) <= 0.0:
				var p0 := Vector3(randf_range(-16.0, 16.0), randf_range(4.0, 15.0), randf_range(-24.0, -13.0))
				var p1 := p0 + Vector3(randf_range(8.0, 14.0), randf_range(-6.0, -2.0), randf_range(-3.0, 3.0))
				s["start"] = p0
				s["end"] = p1
				s["t"] = 0.0
				s["dur"] = randf_range(0.65, 1.05)
				s["active"] = true
				inst.global_position = p0
				inst.look_at(p1, Vector3.UP)
				inst.visible = true
			continue

		var t := float(s["t"]) + delta
		var dur := float(s["dur"])
		s["t"] = t
		if t >= dur:
			s["active"] = false
			s["cooldown"] = randf_range(2.6, 6.2)
			inst.visible = false
			continue
		var u := t / dur
		inst.global_position = (s["start"] as Vector3).lerp(s["end"] as Vector3, u)
		var alpha := sin(u * PI) * 0.90
		mat.albedo_color = Color(0.82, 0.94, 1.0, alpha)


func _attach_shield_head_aura(head_root: Node3D, body_r: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = body_r * 1.48
	sphere.height = body_r * 2.96
	sphere.radial_segments = 16
	sphere.rings = 10
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.24, 0.98, 0.68, 0.22)
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	shield_head_aura = MeshInstance3D.new()
	shield_head_aura.mesh = sphere
	shield_head_aura.material_override = mat
	shield_head_aura.visible = false
	shield_head_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head_root.add_child(shield_head_aura)


func _create_space_dust_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 70
	p.lifetime = 8.0
	p.preprocess = 4.0
	p.emitting = true

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(14.0, 14.0, 14.0)
	pmat.direction = Vector3(0.4, 0.15, 0.2)
	pmat.spread = 35.0
	pmat.initial_velocity_min = 0.08
	pmat.initial_velocity_max = 0.24
	pmat.gravity = Vector3.ZERO
	pmat.scale_min = 0.025
	pmat.scale_max = 0.06
	p.process_material = pmat

	var speck := SphereMesh.new()
	speck.radius = 0.5
	speck.height = 1.0
	speck.radial_segments = 6
	speck.rings = 4
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.92, 1.0)
	smat.emission_enabled = true
	smat.emission = Color(0.75, 0.88, 1.0)
	smat.emission_energy_multiplier = 1.8
	speck.material = smat
	p.draw_pass_1 = speck
	return p


func _trigger_particles(p: GPUParticles3D, cell_id: int) -> void:
	if cell_id < 0:
		return
	var n := grid.cell_normals[cell_id]
	p.global_position = n * (PLANET_RADIUS + PLANET_RADIUS * grid.cell_arc_angle * 0.4)
	p.restart()
	p.emitting = true


func _spawn_score_popup(cell_id: int, text: String, color: Color) -> void:
	if cell_id < 0 or camera == null:
		return
	var world_pos := grid.cell_normals[cell_id] * (PLANET_RADIUS + 0.55)
	if not camera.is_position_behind(world_pos):
		var s_pos := camera.unproject_position(world_pos)
		emit_signal("floating_popup", s_pos, text, color)


func _rebuild_fruit_nodes(cell_world_len: float) -> void:
	for c in food_root.get_children():
		c.queue_free()
	_food_nodes.clear()
	for c in bonus_node.get_children():
		if c != bonus_aura_particles:
			c.queue_free()
	if powerup_node != null:
		for c in powerup_node.get_children():
			if c != powerup_aura_particles:
				c.queue_free()
	_powerup_meshes.clear()

	for _i in range(MAX_FOOD_POOL):
		var apple := ProceduralMeshes.build_apple_node(cell_world_len * 0.36, _apple_mat, _stem_mat, _leaf_mat)
		apple.visible = false
		food_root.add_child(apple)
		_food_nodes.append(apple)

	var gold := ProceduralMeshes.build_apple_node(cell_world_len * 0.40, _gold_apple_mat, _stem_mat, _leaf_mat)
	bonus_node.add_child(gold)

	if powerup_node != null:
		for ptype in range(3):
			var col: Color = POWERUP_COLORS[ptype]
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = col
			pmat.metallic = 0.65
			pmat.roughness = 0.18
			pmat.emission_enabled = true
			pmat.emission = col
			pmat.emission_energy_multiplier = 0.85
			var inst := MeshInstance3D.new()
			inst.mesh = ProceduralMeshes.build_powerup_mesh(cell_world_len * 0.34, ptype)
			inst.material_override = pmat
			inst.visible = false
			powerup_node.add_child(inst)
			_powerup_meshes.append(inst)


func _exit_tree() -> void:
	if ambient_player != null:
		ambient_player.stop()


func _rebuild_boulder_nodes(cell_world_len: float) -> void:
	for c in boulders_root.get_children():
		c.queue_free()

	# 1. Build sculpted continuous ancient stone walls
	for cid_key in logic.wall_cells.keys():
		var cid := int(cid_key)
		var mask := 0
		if logic.wall_cells.has(grid.get_neighbor(cid, 0)):
			mask |= 4
		if logic.wall_cells.has(grid.get_neighbor(cid, 1)):
			mask |= 2
		if logic.wall_cells.has(grid.get_neighbor(cid, 2)):
			mask |= 1
		if logic.wall_cells.has(grid.get_neighbor(cid, 3)):
			mask |= 8

		var n := grid.cell_normals[cid]
		var t_up := grid.get_edge_tangent(cid, 0)
		var t_right := grid.get_edge_tangent(cid, 1)
		var w_inst := MeshInstance3D.new()
		w_inst.mesh = ProceduralMeshes.build_wall_mesh(cell_world_len, mask, cid + 31)
		w_inst.material_override = _wall_mat
		w_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		boulders_root.add_child(w_inst)
		w_inst.global_position = n * (PLANET_RADIUS + SphereGrid.surface_bump(n))
		w_inst.global_basis = Basis(t_right, n, -t_up).orthonormalized()

	# 2. Build craggy rocky terrain mound bumps
	for cid_key in logic.bump_cells.keys():
		var cid := int(cid_key)
		var b_inst := MeshInstance3D.new()
		b_inst.mesh = ProceduralMeshes.build_boulder_mesh(cell_world_len * 0.44, cid + 17)
		b_inst.material_override = _boulder_mat
		b_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		boulders_root.add_child(b_inst)
		_place_on_cell(b_inst, cid, cell_world_len * 0.11)
		b_inst.scale = Vector3(1.12, 0.78, 1.12)
		b_inst.rotate_object_local(Vector3.UP, float(cid % 12) * 0.52)


func _rebuild_street_lamps(cell_world_len: float) -> void:
	if lamps_root == null or grid == null:
		return
	for c in lamps_root.get_children():
		c.queue_free()

	var sun_n := SUN_DIR.normalized()
	var n := grid.grid_n
	var div := 1 if n <= 2 else (2 if n <= 5 else (3 if n <= 10 else 4))
	var coords: Array[int] = []
	for k in range(1, div + 1):
		var g := clampi(int(round(float(k) * float(n) / float(div + 1))), 1, n - 1)
		if not coords.has(g):
			coords.append(g)

	# Collect interior grid intersections on the night/twilight hemisphere (deepest night first)
	var candidates: Array[Dictionary] = []
	var step_size := 2.0 / float(n)
	for face in range(SphereGrid.FACE_COUNT):
		for gx in coords:
			for gy in coords:
				var cu := -1.0 + float(gx) * step_size
				var cv := -1.0 + float(gy) * step_size
				var dir := SphereGrid.equiangular_to_sphere(face, cu, cv)
				var ndotl := dir.dot(sun_n)
				if ndotl < 0.25:
					candidates.append({"dir": dir, "ndotl": ndotl})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ndotl"]) < float(b["ndotl"]))

	var min_dot_lamp := cos(grid.cell_arc_angle * (1.2 if n <= 3 else 2.15))
	var min_dot_omni := cos(grid.cell_arc_angle * (1.4 if n <= 3 else 2.90))
	var selected: PackedVector3Array = PackedVector3Array()
	var omni_dirs: PackedVector3Array = PackedVector3Array()

	for cand in candidates:
		if selected.size() >= 16:
			break
		var dir: Vector3 = cand["dir"]
		var too_close := false
		for ex in selected:
			if dir.dot(ex) > min_dot_lamp:
				too_close = true
				break
		if too_close:
			continue
		selected.append(dir)

		var lamp := ProceduralMeshes.build_street_lamp_node(cell_world_len, _lamp_pole_mat, _lamp_bulb_mat)
		lamps_root.add_child(lamp)
		lamp.global_position = dir * (PLANET_RADIUS + SphereGrid.surface_bump(dir))
		lamp.global_basis = _orient_basis_on_normal(dir)

		# Keep up to 6 gentle OmniLight3Ds on darkest well-spaced lamps (fits Forward Mobile 8-light cap)
		if omni_dirs.size() < 6:
			var omni_close := false
			for ox in omni_dirs:
				if dir.dot(ox) > min_dot_omni:
					omni_close = true
					break
			if not omni_close:
				omni_dirs.append(dir)
				var omni := OmniLight3D.new()
				omni.light_color = Color(1.0, 0.74, 0.30)
				omni.light_energy = 0.52
				omni.omni_range = cell_world_len * 2.8
				omni.omni_attenuation = 1.60
				omni.shadow_enabled = false
				omni.position = Vector3(0.0, cell_world_len * 0.56, 0.0)
				lamp.add_child(omni)

	_lamp_dirs = selected
	_sync_lamp_shader_uniforms()


func _sync_lamp_shader_uniforms() -> void:
	if planet_shader_mat == null:
		return
	var padded := PackedVector3Array()
	padded.resize(16)
	var count := mini(_lamp_dirs.size(), 16)
	for i in range(16):
		padded[i] = _lamp_dirs[i] if i < count else Vector3.UP
	planet_shader_mat.set_shader_parameter("lamp_dirs", padded)
	planet_shader_mat.set_shader_parameter("lamp_count", count)


func _apply_biome_visuals() -> void:
	if planet_shader_mat == null:
		return
	var bname: String = BIOME_NAMES[clampi(selected_biome, 0, BIOME_NAMES.size() - 1)]
	var rim_col: Color = BIOME_RIM_COLORS[clampi(selected_biome, 0, 2)]
	var sun_n := SUN_DIR.normalized()
	planet_shader_mat.set_shader_parameter("albedo_tex", _textures[bname + "_albedo"])
	planet_shader_mat.set_shader_parameter("normal_tex", _textures[bname + "_normal"])
	planet_shader_mat.set_shader_parameter("roughness_tex", _textures[bname + "_roughness"])
	planet_shader_mat.set_shader_parameter("biome_id", selected_biome)
	planet_shader_mat.set_shader_parameter("sun_dir", sun_n)
	planet_shader_mat.set_shader_parameter("atmosphere_tint", rim_col)
	_sync_lamp_shader_uniforms()
	if _wall_mat != null:
		_wall_mat.albedo_texture = _textures[bname + "_albedo"]
		_wall_mat.normal_texture = _textures[bname + "_normal"]
		_wall_mat.roughness_texture = _textures[bname + "_roughness"]
		_wall_mat.albedo_color = Color(0.78, 0.78, 0.80) if selected_biome != Biome.VOLCANIC else Color(0.62, 0.56, 0.58)
	if grid != null:
		planet_shader_mat.set_shader_parameter("grid_n", float(grid.grid_n))
		planet_shader_mat.set_shader_parameter("cell_arc", grid.cell_arc_angle)
	atmosphere_mat.set_shader_parameter("rim_color", rim_col)
	atmosphere_mat.set_shader_parameter("sun_dir", sun_n)
	if clouds_mat != null:
		var cloud_cols := [Color(0.90, 0.95, 1.0), Color(0.96, 0.72, 0.56), Color(1.0, 0.92, 0.76)]
		var cloud_op := [0.13, 0.11, 0.10]
		var bi := clampi(selected_biome, 0, 2)
		clouds_mat.set_shader_parameter("cloud_color", cloud_cols[bi])
		clouds_mat.set_shader_parameter("opacity", cloud_op[bi])
		clouds_mat.set_shader_parameter("sun_dir", sun_n)
	if _slither_dust_mat != null:
		var dc: Color = BIOME_DUST_COLORS[clampi(selected_biome, 0, 2)]
		_slither_dust_mat.albedo_color = dc
		_slither_dust_mat.emission = dc


func _apply_skin_visuals() -> void:
	if snake_skin_mat != null:
		snake_skin_mat.set_shader_parameter("skin_id", selected_skin)
	if _eye_mat != null:
		var ec: Color = SKIN_EYE_COLORS[clampi(selected_skin, 0, SKIN_EYE_COLORS.size() - 1)]
		_eye_mat.albedo_color = ec
		_eye_mat.emission = ec * 0.42
	if _boost_mat != null:
		var bc := Color(0.22, 0.96, 0.72) if selected_skin != SnakeSkin.MAGMA else Color(1.0, 0.52, 0.16)
		if selected_skin == SnakeSkin.FROST:
			bc = Color(0.40, 0.90, 1.0)
		elif selected_skin == SnakeSkin.GOLD:
			bc = Color(1.0, 0.85, 0.25)
		_boost_mat.albedo_color = bc
		_boost_mat.emission = bc


func _update_snake_fx_uniforms(delta: float) -> void:
	if snake_skin_mat == null:
		return
	var target_boost := 1.0 if (_boosting and play_state == PlayState.PLAYING) else 0.0
	_boost_fx = move_toward(_boost_fx, target_boost, delta * 6.0)
	snake_skin_mat.set_shader_parameter("boost_amount", _boost_fx)
	if logic != null and play_state == PlayState.PLAYING:
		snake_skin_mat.set_shader_parameter("shield_amount", 1.0 if logic.shield_active else 0.0)
		snake_skin_mat.set_shader_parameter("magnet_amount", 1.0 if logic.magnet_time_left > 0.0 else 0.0)
		snake_skin_mat.set_shader_parameter("frost_amount", 1.0 if logic.frost_time_left > 0.0 else 0.0)
	else:
		snake_skin_mat.set_shader_parameter("shield_amount", 0.0)
		snake_skin_mat.set_shader_parameter("magnet_amount", 0.0)
		snake_skin_mat.set_shader_parameter("frost_amount", 0.0)


func _apply_quality_settings() -> void:
	if sun_light != null:
		sun_light.shadow_enabled = true
	if world_env != null and world_env.environment != null:
		world_env.environment.glow_enabled = high_quality
		if not _is_mobile_gpu():
			world_env.environment.ssao_enabled = high_quality
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = Viewport.MSAA_4X if high_quality else Viewport.MSAA_2X


func _build_audio() -> void:
	sfx_eat = _make_player("res://assets/audio/eat.wav", -4.0)
	sfx_eat_gold = _make_player("res://assets/audio/eat_gold.wav", -3.0)
	sfx_turn = _make_player("res://assets/audio/turn.wav", -14.0)
	sfx_crash = _make_player("res://assets/audio/crash.wav", -2.0)
	sfx_ui_click = _make_player("res://assets/audio/ui_click.wav", -8.0)
	sfx_milestone = _make_player("res://assets/audio/milestone.wav", -4.0)
	sfx_powerup = _make_player("res://assets/audio/powerup.wav", -3.5)
	sfx_shield_break = _make_player("res://assets/audio/shield_break.wav", -2.5)

	ambient_player = AudioStreamPlayer.new()
	var amb_stream: AudioStreamWAV = load("res://assets/audio/ambient_space.wav")
	if amb_stream != null:
		amb_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		amb_stream.loop_end = amb_stream.get_length() * 44100
		ambient_player.stream = amb_stream
	ambient_player.volume_db = -18.0
	add_child(ambient_player)
	_apply_audio_mute()


func _make_player(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	add_child(p)
	return p


func _apply_audio_mute() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, audio_muted)
	if ambient_player != null:
		if audio_muted and ambient_player.playing:
			ambient_player.stop()
		elif not audio_muted and not ambient_player.playing and ambient_player.stream != null:
			ambient_player.play()


func _create_eye_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.68, 0.14)
	m.roughness = 0.08
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.emission_enabled = true
	m.emission = Color(0.38, 0.22, 0.02)
	m.emission_energy_multiplier = 0.35
	return m


func _create_pupil_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02)
	m.roughness = 0.05
	return m


func _create_tongue_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.88, 0.16, 0.26)
	m.roughness = 0.25
	return m


func _vibrate(ms: int) -> void:
	if is_mobile_platform():
		Input.vibrate_handheld(ms)


func _emit_hud_update() -> void:
	if logic == null:
		return
	var key := "arcade" if selected_mode == SnakeLogic.GameMode.ARCADE else "classic"
	emit_signal("hud_updated", {
		"score": logic.score,
		"best_score": maxi(int(best_scores[key]), logic.score),
		"length": logic.snake_cells.size(),
		"apples": logic.apples_eaten,
		"combo": logic.combo,
		"peak_combo": _run_peak_combo,
		"bonus_ratio": clampf(logic.bonus_time_left / logic.bonus_max_time, 0.0, 1.0) if logic.bonus_food_cell >= 0 else 0.0,
		"shield_active": logic.shield_active,
		"magnet_ratio": clampf(logic.magnet_time_left / SnakeLogic.POWERUP_DURATION, 0.0, 1.0),
		"magnet_secs": logic.magnet_time_left,
		"frost_ratio": clampf(logic.frost_time_left / SnakeLogic.POWERUP_DURATION, 0.0, 1.0),
		"frost_secs": logic.frost_time_left,
		"boosting": _boosting,
		"elapsed": logic.elapsed_time,
		"death_reason": logic.death_reason,
		"won": logic.won,
		"muted": audio_muted,
		"show_dpad": should_show_dpad(),
		"camera_mode": camera_mode,
	})


func _load_save_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_scores["classic"] = int(cfg.get_value("scores", "classic", 0))
	best_scores["arcade"] = int(cfg.get_value("scores", "arcade", 0))
	stats["games_played"] = int(cfg.get_value("stats", "games_played", 0))
	stats["total_apples"] = int(cfg.get_value("stats", "total_apples", 0))
	stats["max_length"] = int(cfg.get_value("stats", "max_length", 4))
	stats["best_combo"] = int(cfg.get_value("stats", "best_combo", 1))
	stats["total_time"] = float(cfg.get_value("stats", "total_time", 0.0))
	selected_mode = int(cfg.get_value("settings", "mode", SnakeLogic.GameMode.CLASSIC))
	selected_biome = int(cfg.get_value("settings", "biome", Biome.TERRA))
	selected_size_idx = int(cfg.get_value("settings", "size_idx", 1))
	var fallback_n: int = GRID_SIZES[clampi(selected_size_idx, 0, GRID_SIZES.size() - 1)]
	selected_grid_n = clampi(int(cfg.get_value("settings", "grid_n", fallback_n)), MIN_GRID_N, MAX_GRID_N)
	selected_speed_idx = int(cfg.get_value("settings", "speed_idx", SnakeLogic.SpeedTier.CLASSIC))
	selected_skin = int(cfg.get_value("settings", "skin_idx", SnakeSkin.EMERALD))
	camera_mode = int(cfg.get_value("settings", "camera_mode", CameraMode.GLOBE_4WAY))
	touch_mode = int(cfg.get_value("settings", "touch_mode", TouchMode.AUTO))
	audio_muted = bool(cfg.get_value("settings", "muted", false))
	high_quality = bool(cfg.get_value("settings", "high_quality", true))


func _save_data() -> void:
	if save_disabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "classic", int(best_scores["classic"]))
	cfg.set_value("scores", "arcade", int(best_scores["arcade"]))
	cfg.set_value("stats", "games_played", int(stats["games_played"]))
	cfg.set_value("stats", "total_apples", int(stats["total_apples"]))
	cfg.set_value("stats", "max_length", int(stats["max_length"]))
	cfg.set_value("stats", "best_combo", int(stats["best_combo"]))
	cfg.set_value("stats", "total_time", float(stats["total_time"]))
	cfg.set_value("settings", "mode", selected_mode)
	cfg.set_value("settings", "biome", selected_biome)
	cfg.set_value("settings", "size_idx", selected_size_idx)
	cfg.set_value("settings", "grid_n", selected_grid_n)
	cfg.set_value("settings", "speed_idx", selected_speed_idx)
	cfg.set_value("settings", "skin_idx", selected_skin)
	cfg.set_value("settings", "camera_mode", camera_mode)
	cfg.set_value("settings", "touch_mode", touch_mode)
	cfg.set_value("settings", "muted", audio_muted)
	cfg.set_value("settings", "high_quality", high_quality)
	cfg.save(SAVE_PATH)
