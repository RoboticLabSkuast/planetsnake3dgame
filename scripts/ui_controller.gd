class_name UIController
extends CanvasLayer
## Cross-platform responsive UI featuring a Subway-Surfers-inspired open live-3D
## start screen, crisp icon pills, multi-screen modals, HUD, and touch controls.

@export var controller_path: NodePath = NodePath("..")

var game: GameController

var _safe_root: MarginContainer
var _root_box: Control
var _popup_layer: Control
var _hud_layer: Control
var _touch_controls: Control

# Subway-Surfers-style open 3D Home Screen
var _home_layer: Control
var _tap_anywhere_btn: Button
var _home_best_btn: Button
var _home_apples_btn: Button
var _home_sound_btn: Button
var _home_mode_chip: Label
var _tap_play_btn: Button
var _pulse_time: float = 0.0

# Modal Overlays
var _modal_backdrop: ColorRect
var _customize_overlay: CenterContainer
var _stats_overlay: CenterContainer
var _guide_overlay: CenterContainer
var _settings_overlay: CenterContainer
var _pause_overlay: CenterContainer
var _gameover_overlay: CenterContainer

# HUD Elements
var _lbl_score: Label
var _lbl_best: Label
var _lbl_length: Label
var _lbl_combo: Label
var _bonus_bar_box: VBoxContainer
var _bonus_bar: ProgressBar
var _powerup_row: HBoxContainer
var _badge_shield: PanelContainer
var _badge_magnet: PanelContainer
var _magnet_bar: ProgressBar
var _magnet_lbl: Label
var _badge_frost: PanelContainer
var _frost_bar: ProgressBar
var _frost_lbl: Label
var _btn_mute: Button
var _btn_pause: Button
var _lbl_cam_hint: Label
var _milestone_panel: PanelContainer
var _milestone_lbl: Label
var _milestone_tween: Tween

# Selector button groups
var _mode_btns: Array[Button] = []
var _biome_btns: Array[Button] = []
var _skin_btns: Array[Button] = []
var _btn_size_dec: Button
var _lbl_size_val: Label
var _btn_size_inc: Button
var _speed_btns: Array[Button] = []
var _cam_btns: Array[Button] = []
var _touch_btns: Array[Button] = []
var _gfx_btns: Array[Button] = []
var _audio_btns: Array[Button] = []

var _modal_return_target: String = "home"
var _stats_body_lbl: Label

# Game Over labels
var _go_title: Label
var _go_reason: Label
var _go_stats: Label
var _go_new_best: Label

# Cached UI icon textures
var _icons := {}

# Touch swipe & pinch tracking
var _touches: Dictionary = {}
var _swipe_finger_id: int = -1
var _swipe_anchor: Vector2 = Vector2.ZERO
var _pinch_prev_dist: float = 0.0
const SWIPE_THRESHOLD := 28.0


func _ready() -> void:
	game = get_node(controller_path) as GameController
	_load_icons()
	_build_ui()
	_connect_game()
	_apply_responsive_ui_scale()
	get_viewport().size_changed.connect(_apply_responsive_ui_scale)
	_refresh_selector_states()
	_on_game_state_changed(game.play_state)


func _process(delta: float) -> void:
	if _home_layer != null and _home_layer.visible and _tap_play_btn != null:
		_pulse_time += delta * 3.2
		var s := 1.0 + 0.045 * sin(_pulse_time)
		_tap_play_btn.pivot_offset = _tap_play_btn.size * 0.5
		_tap_play_btn.scale = Vector2(s, s)


func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("pause_game"):
			if game.play_state == GameController.PlayState.PLAYING or game.play_state == GameController.PlayState.PAUSED:
				game.toggle_pause()
				get_viewport().set_input_as_handled()
				return

		if game.play_state == GameController.PlayState.MENU and _home_layer.visible:
			if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				game.play_ui_click()
				game.start_new_game()
				get_viewport().set_input_as_handled()
				return

		if game.play_state == GameController.PlayState.GAME_OVER or game.play_state == GameController.PlayState.VICTORY:
			if event.keycode == KEY_R or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				game.start_new_game()
				get_viewport().set_input_as_handled()
				return

		if game.play_state == GameController.PlayState.PLAYING:
			if event.is_action("turn_up"):
				game.apply_directional_input(Vector2(0.0, 1.0))
				get_viewport().set_input_as_handled()
			elif event.is_action("turn_down"):
				game.apply_directional_input(Vector2(0.0, -1.0))
				get_viewport().set_input_as_handled()
			elif event.is_action("turn_left"):
				game.apply_directional_input(Vector2(-1.0, 0.0))
				get_viewport().set_input_as_handled()
			elif event.is_action("turn_right"):
				game.apply_directional_input(Vector2(1.0, 0.0))
				get_viewport().set_input_as_handled()

	if event.is_action("boost") and game.play_state == GameController.PlayState.PLAYING:
		game.set_boosting(event.is_pressed())

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			game.adjust_zoom(1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			game.adjust_zoom(-1.0)

	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_swipe_finger_id = event.index
				_swipe_anchor = event.position
			elif _touches.size() == 2:
				_swipe_finger_id = -1
				var keys := _touches.keys()
				_pinch_prev_dist = (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]] as Vector2)
		else:
			_touches.erase(event.index)
			if event.index == _swipe_finger_id:
				_swipe_finger_id = -1
			if _touches.size() < 2:
				_pinch_prev_dist = 0.0

	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			var keys := _touches.keys()
			var dist := (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]] as Vector2)
			if _pinch_prev_dist > 1.0:
				game.adjust_zoom((dist - _pinch_prev_dist) * 0.015)
			_pinch_prev_dist = dist
		elif _touches.size() == 1 and event.index == _swipe_finger_id and game.play_state == GameController.PlayState.PLAYING:
			var delta_v: Vector2 = event.position - _swipe_anchor
			if delta_v.length() >= SWIPE_THRESHOLD:
				if absf(delta_v.x) >= absf(delta_v.y):
					game.apply_directional_input(Vector2(1.0 if delta_v.x > 0.0 else -1.0, 0.0))
				else:
					game.apply_directional_input(Vector2(0.0, -1.0 if delta_v.y > 0.0 else 1.0))
				_swipe_anchor = event.position


func _load_icons() -> void:
	for k in ["trophy", "apple", "globe", "gear", "guide", "sound_on", "sound_off", "play", "shield", "magnet", "frost"]:
		_icons[k] = load("res://assets/textures/ui/%s.png" % k)


func _connect_game() -> void:
	game.game_state_changed.connect(_on_game_state_changed)
	game.hud_updated.connect(_on_hud_updated)
	game.floating_popup.connect(_on_floating_popup)
	game.milestone_banner.connect(_on_milestone_banner)


func _apply_responsive_ui_scale() -> void:
	var win_size := Vector2(DisplayServer.window_get_size())
	var is_portrait := win_size.x < win_size.y
	var target_scale := 1.0
	if is_portrait:
		# Boost UI & font scale on narrow mobile portrait screens for comfortable reading & touch
		target_scale = 1.42
	elif game != null and game.is_mobile_platform():
		target_scale = 1.22

	var root_win := get_tree().root
	if root_win != null and not is_equal_approx(root_win.content_scale_factor, target_scale):
		root_win.content_scale_factor = target_scale
		_update_safe_area.call_deferred()
	else:
		_update_safe_area()


func _update_safe_area() -> void:
	if _safe_root == null:
		return
	var win_size := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var vp_size := get_viewport().get_visible_rect().size
	var scale_x := vp_size.x / maxf(win_size.x, 1.0)
	var scale_y := vp_size.y / maxf(win_size.y, 1.0)

	var left_pad := maxi(14, int(float(safe.position.x) * scale_x) + 10)
	var top_pad := maxi(14, int(float(safe.position.y) * scale_y) + 10)
	var right_pad := maxi(14, int((win_size.x - float(safe.end.x)) * scale_x) + 10)
	var bot_pad := maxi(14, int((win_size.y - float(safe.end.y)) * scale_y) + 10)

	_safe_root.add_theme_constant_override("margin_left", left_pad)
	_safe_root.add_theme_constant_override("margin_top", top_pad)
	_safe_root.add_theme_constant_override("margin_right", right_pad)
	_safe_root.add_theme_constant_override("margin_bottom", bot_pad)


func _build_ui() -> void:
	_popup_layer = Control.new()
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popup_layer)

	_modal_backdrop = ColorRect.new()
	_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.color = Color(0.015, 0.025, 0.055, 0.58)
	_modal_backdrop.visible = false
	add_child(_modal_backdrop)

	_safe_root = MarginContainer.new()
	_safe_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_safe_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe_root)

	_root_box = Control.new()
	_root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_root.add_child(_root_box)

	_build_hud(_root_box)
	_build_touch_dpad(_root_box)
	_build_home_screen(_root_box)
	_build_customize_modal(_root_box)
	_build_stats_modal(_root_box)
	_build_guide_modal(_root_box)
	_build_settings_modal(_root_box)
	_build_pause_modal(_root_box)
	_build_gameover_modal(_root_box)


func _build_hud(parent: Control) -> void:
	_hud_layer = Control.new()
	_hud_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_hud_layer)

	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.add_theme_constant_override("separation", 10)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(top_bar)

	var score_panel := _make_glass_panel(Color(0.04, 0.07, 0.13, 0.80), 12)
	top_bar.add_child(score_panel)

	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 16)
	score_panel.add_child(score_row)

	_lbl_score = _make_label("SCORE 0", 21, Color(0.97, 0.98, 1.0))
	_lbl_best = _make_label("BEST 0", 15, Color(0.72, 0.82, 0.95))
	_lbl_length = _make_label("LEN 4", 15, Color(0.42, 0.95, 0.62))
	_lbl_combo = _make_label("", 15, Color(1.0, 0.84, 0.25))
	score_row.add_child(_lbl_score)
	score_row.add_child(_lbl_best)
	score_row.add_child(_lbl_length)
	score_row.add_child(_lbl_combo)

	_bonus_bar_box = VBoxContainer.new()
	_bonus_bar_box.visible = false
	_bonus_bar_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_bonus_bar_box)

	var b_lbl := _make_label("GOLDEN FRUIT", 13, Color(1.0, 0.86, 0.28))
	b_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bonus_bar_box.add_child(b_lbl)

	_bonus_bar = ProgressBar.new()
	_bonus_bar.max_value = 1.0
	_bonus_bar.value = 1.0
	_bonus_bar.show_percentage = false
	_bonus_bar.custom_minimum_size = Vector2(130, 11)
	_bonus_bar_box.add_child(_bonus_bar)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(spacer)

	var right_row := HBoxContainer.new()
	right_row.add_theme_constant_override("separation", 8)
	top_bar.add_child(right_row)

	_btn_mute = _make_pill_button("", 14, Color(0.10, 0.16, 0.26, 0.86), "sound_on")
	_btn_mute.custom_minimum_size = Vector2(52, 42)
	_btn_mute.pressed.connect(func() -> void:
		game.play_ui_click()
		game.toggle_mute()
	)
	right_row.add_child(_btn_mute)

	_btn_pause = _make_pill_button("PAUSE", 14, Color(0.10, 0.16, 0.26, 0.86))
	_btn_pause.custom_minimum_size = Vector2(84, 42)
	_btn_pause.pressed.connect(func() -> void:
		game.play_ui_click()
		game.toggle_pause()
	)
	right_row.add_child(_btn_pause)

	_powerup_row = HBoxContainer.new()
	_powerup_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_powerup_row.offset_left = 0.0
	_powerup_row.offset_top = 56.0
	_powerup_row.add_theme_constant_override("separation", 8)
	_powerup_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_powerup_row)

	var sh := _make_powerup_badge("shield", "SHIELD READY", Color(0.24, 0.96, 0.66), false)
	_badge_shield = sh["panel"]
	_powerup_row.add_child(_badge_shield)

	var mg := _make_powerup_badge("magnet", "MAGNET 2X", Color(0.84, 0.34, 1.0), true)
	_badge_magnet = mg["panel"]
	_magnet_lbl = mg["label"]
	_magnet_bar = mg["bar"]
	_powerup_row.add_child(_badge_magnet)

	var fr := _make_powerup_badge("frost", "FROST", Color(0.32, 0.84, 1.0), true)
	_badge_frost = fr["panel"]
	_frost_lbl = fr["label"]
	_frost_bar = fr["bar"]
	_powerup_row.add_child(_badge_frost)

	_milestone_panel = _make_glass_panel(Color(0.06, 0.11, 0.19, 0.90), 10)
	_milestone_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_milestone_panel.offset_left = -160.0
	_milestone_panel.offset_right = 160.0
	_milestone_panel.offset_top = 66.0
	_milestone_panel.offset_bottom = 108.0
	_milestone_panel.visible = false
	_milestone_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_milestone_panel)

	_milestone_lbl = _make_label("", 17, Color(0.45, 0.96, 0.65))
	_milestone_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_milestone_panel.add_child(_milestone_lbl)

	_lbl_cam_hint = _make_label("WASD / Arrows: Turn  •  Space: Boost  •  Scroll: Zoom", 13, Color(0.75, 0.84, 0.95, 0.72))
	_lbl_cam_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_lbl_cam_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_layer.add_child(_lbl_cam_hint)


func _build_touch_dpad(parent: Control) -> void:
	_touch_controls = Control.new()
	_touch_controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_touch_controls)

	var dpad := GridContainer.new()
	dpad.columns = 3
	dpad.add_theme_constant_override("h_separation", 8)
	dpad.add_theme_constant_override("v_separation", 8)
	dpad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dpad.offset_left = 10
	dpad.offset_top = -198
	dpad.offset_right = 202
	dpad.offset_bottom = -10
	_touch_controls.add_child(dpad)

	var cells := [
		["", Vector2.ZERO], ["▲", Vector2(0, 1)], ["", Vector2.ZERO],
		["◀", Vector2(-1, 0)], ["", Vector2.ZERO], ["▶", Vector2(1, 0)],
		["", Vector2.ZERO], ["▼", Vector2(0, -1)], ["", Vector2.ZERO],
	]
	for item in cells:
		var lbl_txt: String = item[0]
		var dir_vec: Vector2 = item[1]
		if lbl_txt == "":
			var empty := Control.new()
			empty.custom_minimum_size = Vector2(58, 58)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dpad.add_child(empty)
		else:
			var b := _make_pill_button(lbl_txt, 22, Color(0.08, 0.14, 0.22, 0.65))
			b.custom_minimum_size = Vector2(58, 58)
			b.focus_mode = Control.FOCUS_NONE
			b.button_down.connect(func() -> void: game.apply_directional_input(dir_vec))
			dpad.add_child(b)

	var boost_btn := _make_pill_button("BOOST", 16, Color(0.16, 0.56, 0.36, 0.78))
	boost_btn.custom_minimum_size = Vector2(96, 96)
	boost_btn.focus_mode = Control.FOCUS_NONE
	boost_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	boost_btn.offset_left = -114
	boost_btn.offset_top = -114
	boost_btn.offset_right = -18
	boost_btn.offset_bottom = -18
	boost_btn.button_down.connect(func() -> void: game.set_boosting(true))
	boost_btn.button_up.connect(func() -> void: game.set_boosting(false))
	_touch_controls.add_child(boost_btn)


func _build_home_screen(parent: Control) -> void:
	_home_layer = Control.new()
	_home_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_home_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_home_layer)

	# Full-screen invisible button behind pills so tapping anywhere on the 3D scene starts the game
	_tap_anywhere_btn = Button.new()
	_tap_anywhere_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_anywhere_btn.flat = true
	_tap_anywhere_btn.focus_mode = Control.FOCUS_NONE
	var empty_sb := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		_tap_anywhere_btn.add_theme_stylebox_override(st, empty_sb)
	_tap_anywhere_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		game.start_new_game()
	)
	_home_layer.add_child(_tap_anywhere_btn)

	# 1. Top Floating Corner Resource & Utility Pills (like Subway Surfers top corners)
	var top_row := HBoxContainer.new()
	top_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_row.add_theme_constant_override("separation", 10)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home_layer.add_child(top_row)

	_home_best_btn = _make_pill_button("0", 17, Color(0.06, 0.10, 0.18, 0.80), "trophy")
	_home_best_btn.custom_minimum_size = Vector2(98, 42)
	_home_best_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_refresh_stats_text()
		_open_modal(_stats_overlay, "home")
	)
	top_row.add_child(_home_best_btn)

	_home_apples_btn = _make_pill_button("0", 17, Color(0.06, 0.10, 0.18, 0.80), "apple")
	_home_apples_btn.custom_minimum_size = Vector2(88, 42)
	_home_apples_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_refresh_stats_text()
		_open_modal(_stats_overlay, "home")
	)
	top_row.add_child(_home_apples_btn)

	var top_sp := Control.new()
	top_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(top_sp)

	_home_sound_btn = _make_pill_button("", 16, Color(0.06, 0.10, 0.18, 0.80), "sound_on")
	_home_sound_btn.custom_minimum_size = Vector2(46, 42)
	_home_sound_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		game.toggle_mute()
		_refresh_selector_states()
	)
	top_row.add_child(_home_sound_btn)

	var top_gear_btn := _make_pill_button("", 16, Color(0.06, 0.10, 0.18, 0.80), "gear")
	top_gear_btn.custom_minimum_size = Vector2(46, 42)
	top_gear_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_open_modal(_settings_overlay, "home")
	)
	top_row.add_child(top_gear_btn)

	# 2. Bold Embossed Arcade Logo Floating in Upper Sky (zero dark box behind it!)
	var logo_box := VBoxContainer.new()
	logo_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	logo_box.offset_top = 56.0
	logo_box.offset_bottom = 196.0
	logo_box.add_theme_constant_override("separation", 5)
	logo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home_layer.add_child(logo_box)

	var title_lbl := Label.new()
	title_lbl.text = "PLANET SNAKE 3D"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 42)
	title_lbl.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	title_lbl.add_theme_color_override("font_outline_color", Color(0.03, 0.08, 0.14, 0.96))
	title_lbl.add_theme_constant_override("outline_size", 11)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.82))
	title_lbl.add_theme_constant_override("shadow_offset_x", 0)
	title_lbl.add_theme_constant_override("shadow_offset_y", 5)
	logo_box.add_child(title_lbl)

	var badge_pill := PanelContainer.new()
	badge_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color = Color(0.95, 0.68, 0.14, 0.95)
	badge_sb.border_color = Color(1.0, 0.92, 0.56, 0.95)
	badge_sb.set_border_width_all(2)
	badge_sb.set_corner_radius_all(12)
	badge_sb.set_content_margin_all(4)
	badge_sb.content_margin_left = 14
	badge_sb.content_margin_right = 14
	badge_pill.add_theme_stylebox_override("panel", badge_sb)
	badge_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_box.add_child(badge_pill)

	var badge_lbl := Label.new()
	badge_lbl.text = "ORBITAL CLASSIC"
	badge_lbl.add_theme_font_size_override("font_size", 14)
	badge_lbl.add_theme_color_override("font_color", Color(0.06, 0.08, 0.12))
	badge_pill.add_child(badge_lbl)

	_home_mode_chip = _make_label("Classic  •  Mossy Terra  •  10x10", 15, Color(0.88, 0.94, 1.0, 0.94))
	_home_mode_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_box.add_child(_home_mode_chip)

	# 3. Bottom Open Floating Action Area: Pulsing TAP TO PLAY + Slim Floating Icon Row
	var bottom_stack := VBoxContainer.new()
	bottom_stack.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_stack.offset_top = -148.0
	bottom_stack.offset_bottom = -4.0
	bottom_stack.add_theme_constant_override("separation", 14)
	bottom_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home_layer.add_child(bottom_stack)

	_tap_play_btn = _make_pill_button("TAP TO PLAY", 22, Color(0.14, 0.68, 0.38, 0.95), "play")
	_tap_play_btn.custom_minimum_size = Vector2(270, 58)
	_tap_play_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(_tap_play_btn, Color(0.14, 0.68, 0.38, 0.96), Color(0.60, 1.0, 0.74, 0.92), 28, 2)
	_tap_play_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		game.start_new_game()
	)
	bottom_stack.add_child(_tap_play_btn)

	# Slim Floating Icon Pills Row (no heavy panel box behind them)
	var icon_bar := HBoxContainer.new()
	icon_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_bar.add_theme_constant_override("separation", 8)
	icon_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_stack.add_child(icon_bar)

	icon_bar.add_child(_make_dock_icon_btn("WORLDS", "globe", func() -> void: _open_modal(_customize_overlay, "home")))
	icon_bar.add_child(_make_dock_icon_btn("RECORDS", "trophy", func() -> void:
		_refresh_stats_text()
		_open_modal(_stats_overlay, "home")
	))
	icon_bar.add_child(_make_dock_icon_btn("GUIDE", "guide", func() -> void: _open_modal(_guide_overlay, "home")))
	icon_bar.add_child(_make_dock_icon_btn("SETTINGS", "gear", func() -> void: _open_modal(_settings_overlay, "home")))


func _make_dock_icon_btn(txt: String, icon_name: String, on_click: Callable) -> Button:
	var b := _make_pill_button(txt, 13, Color(0.06, 0.11, 0.19, 0.82), icon_name)
	b.custom_minimum_size = Vector2(102, 46)
	_style_button(b, Color(0.06, 0.11, 0.19, 0.84), Color(0.46, 0.68, 0.92, 0.45), 16, 1)
	b.pressed.connect(func() -> void:
		game.play_ui_click()
		on_click.call()
	)
	return b


func _build_customize_modal(parent: Control) -> void:
	_customize_overlay = CenterContainer.new()
	_customize_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_customize_overlay.visible = false
	parent.add_child(_customize_overlay)

	var panel := _make_glass_panel(Color(0.05, 0.08, 0.14, 0.94), 20)
	panel.custom_minimum_size = Vector2(420, 0)
	_customize_overlay.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := _make_label("WORLDS & GAME SETUP", 22, Color(0.42, 0.96, 0.64))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_make_selector_row("Mode", ["Classic", "Arcade", "Open"], _mode_btns, func(idx: int) -> void:
		game.play_ui_click()
		game.apply_settings(idx, game.selected_biome, game.selected_size_idx, game.selected_speed_idx, game.camera_mode, game.touch_mode, game.audio_muted, game.high_quality)
		_refresh_selector_states()
	))

	box.add_child(_make_selector_row("Planet", ["Terra", "Volcanic", "Desert"], _biome_btns, func(idx: int) -> void:
		game.play_ui_click()
		game.apply_settings(game.selected_mode, idx, game.selected_size_idx, game.selected_speed_idx, game.camera_mode, game.touch_mode, game.audio_muted, game.high_quality)
		_refresh_selector_states()
	))

	box.add_child(_make_selector_row("Skin", ["Emerald", "Magma", "Frost", "Gold"], _skin_btns, func(idx: int) -> void:
		game.play_ui_click()
		game.apply_settings(game.selected_mode, game.selected_biome, game.selected_size_idx, game.selected_speed_idx, game.camera_mode, game.touch_mode, game.audio_muted, game.high_quality, idx)
		_refresh_selector_states()
	))

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	box.add_child(size_row)

	var size_lbl := _make_label("Globe", 15, Color(0.76, 0.84, 0.95))
	size_lbl.custom_minimum_size = Vector2(74, 34)
	size_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	size_row.add_child(size_lbl)

	_btn_size_dec = _make_pill_button("-", 18, Color(0.14, 0.20, 0.30, 0.90))
	_btn_size_dec.custom_minimum_size = Vector2(52, 36)
	_btn_size_dec.pressed.connect(func() -> void:
		game.play_ui_click()
		game.set_grid_size(game.selected_grid_n - 1)
		_refresh_selector_states()
	)
	size_row.add_child(_btn_size_dec)

	_lbl_size_val = _make_label("10x10 (600 cells)", 14, Color(0.42, 0.96, 0.64))
	_lbl_size_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_size_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_size_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	size_row.add_child(_lbl_size_val)

	_btn_size_inc = _make_pill_button("+", 18, Color(0.14, 0.20, 0.30, 0.90))
	_btn_size_inc.custom_minimum_size = Vector2(52, 36)
	_btn_size_inc.pressed.connect(func() -> void:
		game.play_ui_click()
		game.set_grid_size(game.selected_grid_n + 1)
		_refresh_selector_states()
	)
	size_row.add_child(_btn_size_inc)

	box.add_child(_make_selector_row("Speed", ["Chill", "Classic", "Hyper"], _speed_btns, func(idx: int) -> void:
		game.play_ui_click()
		game.apply_settings(game.selected_mode, game.selected_biome, game.selected_size_idx, idx, game.camera_mode, game.touch_mode, game.audio_muted, game.high_quality)
		_refresh_selector_states()
	))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)

	var play_btn := _make_pill_button("PLAY NOW", 17, Color(0.14, 0.62, 0.36, 0.96), "play")
	play_btn.custom_minimum_size = Vector2(180, 46)
	play_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_close_modals()
		game.start_new_game()
	)
	row.add_child(play_btn)

	var back_btn := _make_pill_button("BACK", 16, Color(0.18, 0.25, 0.38, 0.94))
	back_btn.custom_minimum_size = Vector2(130, 46)
	back_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_close_modals_and_return()
	)
	row.add_child(back_btn)


func _build_stats_modal(parent: Control) -> void:
	_stats_overlay = CenterContainer.new()
	_stats_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_overlay.visible = false
	parent.add_child(_stats_overlay)

	var panel := _make_glass_panel(Color(0.05, 0.08, 0.14, 0.94), 20)
	panel.custom_minimum_size = Vector2(410, 0)
	_stats_overlay.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := _make_label("RECORDS & LIFETIME STATS", 22, Color(1.0, 0.84, 0.30))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_stats_body_lbl = _make_label("", 16, Color(0.92, 0.95, 1.0))
	_stats_body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_stats_body_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)

	var reset_btn := _make_pill_button("RESET STATS", 15, Color(0.45, 0.18, 0.20, 0.92))
	reset_btn.custom_minimum_size = Vector2(140, 44)
	reset_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		game.reset_stats()
		_refresh_stats_text()
		_refresh_selector_states()
	)
	row.add_child(reset_btn)

	var back_btn := _make_pill_button("BACK", 16, Color(0.18, 0.44, 0.72, 0.95))
	back_btn.custom_minimum_size = Vector2(140, 44)
	back_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_close_modals_and_return()
	)
	row.add_child(back_btn)


func _build_guide_modal(parent: Control) -> void:
	_guide_overlay = CenterContainer.new()
	_guide_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_guide_overlay.visible = false
	parent.add_child(_guide_overlay)

	var panel := _make_glass_panel(Color(0.05, 0.08, 0.14, 0.94), 20)
	panel.custom_minimum_size = Vector2(420, 0)
	_guide_overlay.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := _make_label("HOW TO PLAY", 24, Color(0.42, 0.96, 0.64))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sections := [
		["Classic Sphere Rules", "Slither seamlessly across all 6 curved faces of the 3D globe. Eat crimson apples to grow longer without crashing into your tail, walls, or boulders."],
		["Controls (Desktop)", "WASD or Arrow Keys turn along screen directions (or Left/Right in 3D Chase). Hold Space/Shift to Boost, Scroll Wheel to Zoom, P/Esc to Pause."],
		["Controls (Mobile)", "Swipe anywhere in the direction you want to turn, or use the Virtual D-Pad & Boost button. Pinch with two fingers to adjust Zoom."],
		["Combos & Golden Fruit", "Eat apples rapidly to build up to a x5 Combo multiplier. Every 5th apple spawns a timed Golden Fruit worth bonus points and +2 growth!"],
		["Power-Ups & Skins", "Grab Shield (shatters 1 wall), Magnet 2x (pulls nearby apples for double points), and Frost (slows speed). Customize Snake Skins in Worlds!"],
	]
	for sec in sections:
		var h := _make_label(sec[0], 15, Color(1.0, 0.85, 0.34))
		box.add_child(h)
		var body := _make_label(sec[1], 13, Color(0.84, 0.90, 0.98))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(body)

	var back_btn := _make_pill_button("GOT IT", 17, Color(0.14, 0.62, 0.36, 0.96))
	back_btn.custom_minimum_size = Vector2(180, 44)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_close_modals_and_return()
	)
	box.add_child(back_btn)


func _build_settings_modal(parent: Control) -> void:
	_settings_overlay = CenterContainer.new()
	_settings_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.visible = false
	parent.add_child(_settings_overlay)

	var panel := _make_glass_panel(Color(0.05, 0.08, 0.14, 0.94), 20)
	panel.custom_minimum_size = Vector2(420, 0)
	_settings_overlay.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := _make_label("SETTINGS", 24, Color(0.95, 0.97, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_make_selector_row("Camera", ["Globe 4-Way", "3D Chase"], _cam_btns, func(idx: int) -> void:
		game.play_ui_click()
		game.apply_settings(game.selected_mode, game.selected_biome, game.selected_size_idx, game.selected_speed_idx, idx, game.touch_mode, game.audio_muted, game.high_quality)
		_refresh_selector_states()
	))

	box.add_child(_make_selector_row("Touch", ["Auto", "Swipe", "D-Pad"], _touch_btns, func(idx: int) -> void:
		game.play_ui_click()
		game.apply_settings(game.selected_mode, game.selected_biome, game.selected_size_idx, game.selected_speed_idx, game.camera_mode, idx, game.audio_muted, game.high_quality)
		_refresh_selector_states()
	))

	box.add_child(_make_selector_row("Quality", ["Balanced", "High"], _gfx_btns, func(idx: int) -> void:
		game.play_ui_click()
		game.apply_settings(game.selected_mode, game.selected_biome, game.selected_size_idx, game.selected_speed_idx, game.camera_mode, game.touch_mode, game.audio_muted, idx == 1)
		_refresh_selector_states()
	))

	box.add_child(_make_selector_row("Audio", ["On", "Muted"], _audio_btns, func(idx: int) -> void:
		game.apply_settings(game.selected_mode, game.selected_biome, game.selected_size_idx, game.selected_speed_idx, game.camera_mode, game.touch_mode, idx == 1, game.high_quality)
		game.play_ui_click()
		_refresh_selector_states()
	))

	var back_btn := _make_pill_button("BACK", 17, Color(0.18, 0.44, 0.72, 0.95))
	back_btn.custom_minimum_size = Vector2(180, 44)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_close_modals_and_return()
	)
	box.add_child(back_btn)


func _build_pause_modal(parent: Control) -> void:
	_pause_overlay = CenterContainer.new()
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	parent.add_child(_pause_overlay)

	var panel := _make_glass_panel(Color(0.05, 0.08, 0.14, 0.92), 20)
	panel.custom_minimum_size = Vector2(340, 0)
	_pause_overlay.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := _make_label("PAUSED", 28, Color(0.96, 0.98, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var resume_btn := _make_pill_button("RESUME", 18, Color(0.14, 0.62, 0.36, 0.96), "play")
	resume_btn.custom_minimum_size = Vector2(240, 46)
	resume_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		game.toggle_pause()
	)
	box.add_child(resume_btn)

	var restart_btn := _make_pill_button("RESTART", 16, Color(0.18, 0.34, 0.56, 0.94))
	restart_btn.custom_minimum_size = Vector2(240, 42)
	restart_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		game.start_new_game()
	)
	box.add_child(restart_btn)

	var guide_btn := _make_pill_button("HOW TO PLAY", 16, Color(0.15, 0.22, 0.34, 0.94), "guide")
	guide_btn.custom_minimum_size = Vector2(240, 42)
	guide_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_open_modal(_guide_overlay, "pause")
	)
	box.add_child(guide_btn)

	var set_btn := _make_pill_button("SETTINGS", 16, Color(0.15, 0.22, 0.34, 0.94), "gear")
	set_btn.custom_minimum_size = Vector2(240, 42)
	set_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_open_modal(_settings_overlay, "pause")
	)
	box.add_child(set_btn)

	var menu_btn := _make_pill_button("HOME", 16, Color(0.30, 0.18, 0.22, 0.94))
	menu_btn.custom_minimum_size = Vector2(240, 42)
	menu_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		game.rebuild_world(true)
		game.set_play_state(GameController.PlayState.MENU)
	)
	box.add_child(menu_btn)


func _build_gameover_modal(parent: Control) -> void:
	_gameover_overlay = CenterContainer.new()
	_gameover_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameover_overlay.visible = false
	parent.add_child(_gameover_overlay)

	var panel := _make_glass_panel(Color(0.05, 0.08, 0.14, 0.94), 22)
	panel.custom_minimum_size = Vector2(390, 0)
	_gameover_overlay.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_go_title = _make_label("GAME OVER", 30, Color(1.0, 0.42, 0.38))
	_go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_go_title)

	_go_reason = _make_label("", 15, Color(0.76, 0.84, 0.94))
	_go_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_go_reason)

	_go_new_best = _make_label("NEW HIGH SCORE!", 17, Color(1.0, 0.86, 0.26))
	_go_new_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_go_new_best.visible = false
	box.add_child(_go_new_best)

	_go_stats = _make_label("", 16, Color(0.94, 0.96, 1.0))
	_go_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_go_stats)

	var retry_btn := _make_pill_button("PLAY AGAIN", 18, Color(0.14, 0.62, 0.36, 0.96), "play")
	retry_btn.custom_minimum_size = Vector2(240, 48)
	retry_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		game.start_new_game()
	)
	box.add_child(retry_btn)

	var cust_btn := _make_pill_button("WORLDS & SETUP", 15, Color(0.16, 0.28, 0.44, 0.94), "globe")
	cust_btn.custom_minimum_size = Vector2(240, 42)
	cust_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cust_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		_open_modal(_customize_overlay, "gameover")
	)
	box.add_child(cust_btn)

	var menu_btn := _make_pill_button("HOME", 15, Color(0.18, 0.23, 0.34, 0.94))
	menu_btn.custom_minimum_size = Vector2(200, 40)
	menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu_btn.pressed.connect(func() -> void:
		game.play_ui_click()
		game.rebuild_world(true)
		game.set_play_state(GameController.PlayState.MENU)
	)
	box.add_child(menu_btn)


func _open_modal(target: CenterContainer, return_to: String) -> void:
	_modal_return_target = return_to
	_home_layer.visible = false
	_pause_overlay.visible = false
	_gameover_overlay.visible = false
	_customize_overlay.visible = false
	_stats_overlay.visible = false
	_guide_overlay.visible = false
	_settings_overlay.visible = false
	_modal_backdrop.visible = true
	target.visible = true


func _close_modals() -> void:
	_modal_backdrop.visible = false
	_customize_overlay.visible = false
	_stats_overlay.visible = false
	_guide_overlay.visible = false
	_settings_overlay.visible = false


func _close_modals_and_return() -> void:
	_close_modals()
	if _modal_return_target == "pause":
		_pause_overlay.visible = true
		_modal_backdrop.visible = true
	elif _modal_return_target == "gameover":
		_gameover_overlay.visible = true
		_modal_backdrop.visible = true
	else:
		_home_layer.visible = (game.play_state == GameController.PlayState.MENU)


func _refresh_stats_text() -> void:
	var tot_secs := int(float(game.stats["total_time"]))
	var t_mins := tot_secs / 60
	var t_rem := tot_secs % 60
	_stats_body_lbl.text = (
		"Best Classic Score: %d\n"
		+ "Best Arcade Score: %d\n\n"
		+ "Games Played: %d\n"
		+ "Total Apples Eaten: %d\n"
		+ "Longest Snake: %d\n"
		+ "Highest Combo: x%d\n"
		+ "Total Time Played: %02d:%02d"
	) % [
		int(game.best_scores["classic"]),
		int(game.best_scores["arcade"]),
		int(game.stats["games_played"]),
		int(game.stats["total_apples"]),
		int(game.stats["max_length"]),
		int(game.stats["best_combo"]),
		t_mins,
		t_rem,
	]


func _on_game_state_changed(state: int) -> void:
	_close_modals()
	_home_layer.visible = (state == GameController.PlayState.MENU)
	_pause_overlay.visible = (state == GameController.PlayState.PAUSED)
	_gameover_overlay.visible = (state == GameController.PlayState.GAME_OVER or state == GameController.PlayState.VICTORY)
	_modal_backdrop.visible = (state == GameController.PlayState.PAUSED or state == GameController.PlayState.GAME_OVER or state == GameController.PlayState.VICTORY)
	_hud_layer.visible = (state == GameController.PlayState.PLAYING or state == GameController.PlayState.PAUSED)
	_touch_controls.visible = (state == GameController.PlayState.PLAYING) and game.should_show_dpad()
	_refresh_selector_states()

	if state == GameController.PlayState.GAME_OVER or state == GameController.PlayState.VICTORY:
		var won := state == GameController.PlayState.VICTORY
		_go_title.text = "PLANET CONQUERED!" if won else "GAME OVER"
		_go_title.add_theme_color_override("font_color", Color(0.40, 0.98, 0.62) if won else Color(1.0, 0.42, 0.38))
		if won:
			_go_reason.text = "Every cell on the globe explored!"
		elif game.logic.death_reason == "wall":
			_go_reason.text = "Crashed into a stone wall"
		elif game.logic.death_reason == "obstacle":
			_go_reason.text = "Crashed into a rocky bump"
		else:
			_go_reason.text = "Collided with your own tail"

		var key := "arcade" if game.selected_mode == SnakeLogic.GameMode.ARCADE else "classic"
		var best_val := int(game.best_scores[key])
		_go_new_best.visible = (game.logic.score > 0 and game.logic.score >= best_val)
		var mins := int(game.logic.elapsed_time) / 60
		var secs := int(game.logic.elapsed_time) % 60
		_go_stats.text = "Score: %d  •  Best: %d\nApples: %d  •  Length: %d  •  Peak Combo: x%d\nSurvival Time: %02d:%02d" % [
			game.logic.score,
			best_val,
			game.logic.apples_eaten,
			game.logic.snake_cells.size(),
			game._run_peak_combo,
			mins,
			secs,
		]


func _on_hud_updated(data: Dictionary) -> void:
	_lbl_score.text = "SCORE %d" % int(data["score"])
	_lbl_best.text = "BEST %d" % int(data["best_score"])
	_lbl_length.text = "LEN %d" % int(data["length"])
	var c := int(data["combo"])
	_lbl_combo.text = "x%d COMBO" % c if c > 1 else ""

	var bonus_ratio := float(data["bonus_ratio"])
	_bonus_bar_box.visible = bonus_ratio > 0.0
	if bonus_ratio > 0.0:
		_bonus_bar.value = bonus_ratio

	if _badge_shield != null:
		_badge_shield.visible = bool(data.get("shield_active", false))
	if _badge_magnet != null:
		var m_ratio := float(data.get("magnet_ratio", 0.0))
		_badge_magnet.visible = m_ratio > 0.0
		if _badge_magnet.visible:
			_magnet_lbl.text = "2X %.1fs" % float(data.get("magnet_secs", 0.0))
			_magnet_bar.value = m_ratio
	if _badge_frost != null:
		var f_ratio := float(data.get("frost_ratio", 0.0))
		_badge_frost.visible = f_ratio > 0.0
		if _badge_frost.visible:
			_frost_lbl.text = "FROST %.1fs" % float(data.get("frost_secs", 0.0))
			_frost_bar.value = f_ratio

	var is_muted := bool(data["muted"])
	if _btn_mute != null:
		_btn_mute.icon = _icons["sound_off" if is_muted else "sound_on"]
	if _home_sound_btn != null:
		_home_sound_btn.icon = _icons["sound_off" if is_muted else "sound_on"]
	_touch_controls.visible = (game.play_state == GameController.PlayState.PLAYING) and bool(data["show_dpad"])

	if game.is_mobile_platform() or bool(data["show_dpad"]):
		_lbl_cam_hint.text = "Swipe or Use D-Pad  •  Pinch: Zoom"
	elif int(data["camera_mode"]) == GameController.CameraMode.CHASE_3D:
		_lbl_cam_hint.text = "3D Chase: A/D or Arrows to Steer  •  Space: Boost"
	else:
		_lbl_cam_hint.text = "WASD / Arrows: Turn  •  Space: Boost  •  Scroll: Zoom"


func _on_floating_popup(screen_pos: Vector2, text: String, color: Color) -> void:
	var lbl := _make_label(text, 22, color)
	lbl.position = screen_pos - Vector2(40, 20)
	_popup_layer.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 54.0, 0.78).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.78).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)


func _on_milestone_banner(title_txt: String, col: Color) -> void:
	if _milestone_panel == null:
		return
	if _milestone_tween != null and _milestone_tween.is_valid():
		_milestone_tween.kill()
	_milestone_lbl.text = title_txt
	_milestone_lbl.add_theme_color_override("font_color", col)
	_milestone_panel.visible = true
	_milestone_panel.modulate.a = 0.0
	_milestone_tween = create_tween()
	_milestone_tween.tween_property(_milestone_panel, "modulate:a", 1.0, 0.20)
	_milestone_tween.tween_interval(1.55)
	_milestone_tween.tween_property(_milestone_panel, "modulate:a", 0.0, 0.35)
	_milestone_tween.tween_callback(func() -> void: _milestone_panel.visible = false)


func _refresh_selector_states() -> void:
	if game == null:
		return
	var mode_names := ["Classic", "Arcade", "Open"]
	var biome_names := ["Mossy Terra", "Volcanic", "Desert"]
	var skin_names := ["Emerald", "Magma", "Frost", "Gold"]
	var n := clampi(game.selected_grid_n, GameController.MIN_GRID_N, GameController.MAX_GRID_N)
	var top_best := maxi(int(game.best_scores["classic"]), int(game.best_scores["arcade"]))
	_home_best_btn.text = "%d" % top_best
	_home_apples_btn.text = "%d" % int(game.stats["total_apples"])
	_home_sound_btn.icon = _icons["sound_off" if game.audio_muted else "sound_on"]
	_home_mode_chip.text = "%s  •  %s  •  %dx%d  •  %s" % [
		mode_names[clampi(game.selected_mode, 0, 2)],
		biome_names[clampi(game.selected_biome, 0, 2)],
		n,
		n,
		skin_names[clampi(game.selected_skin, 0, 3)],
	]

	_highlight_btn_group(_mode_btns, game.selected_mode)
	_highlight_btn_group(_biome_btns, game.selected_biome)
	_highlight_btn_group(_skin_btns, game.selected_skin)
	if _lbl_size_val != null:
		_lbl_size_val.text = "%dx%dx6  (%d cells)" % [n, n, 6 * n * n]
	if _btn_size_dec != null:
		_btn_size_dec.disabled = (n <= GameController.MIN_GRID_N)
	if _btn_size_inc != null:
		_btn_size_inc.disabled = (n >= GameController.MAX_GRID_N)
	_highlight_btn_group(_speed_btns, game.selected_speed_idx)
	_highlight_btn_group(_cam_btns, game.camera_mode)
	_highlight_btn_group(_touch_btns, game.touch_mode)
	_highlight_btn_group(_gfx_btns, 1 if game.high_quality else 0)
	_highlight_btn_group(_audio_btns, 1 if game.audio_muted else 0)


func _highlight_btn_group(btns: Array[Button], active_idx: int) -> void:
	for i in range(btns.size()):
		var active := (i == active_idx)
		var bg := Color(0.16, 0.56, 0.38, 0.96) if active else Color(0.12, 0.16, 0.25, 0.85)
		var border := Color(0.42, 0.98, 0.66, 0.90) if active else Color(0.32, 0.42, 0.56, 0.35)
		_style_button(btns[i], bg, border)


func _make_selector_row(label_text: String, options: Array[String], store: Array[Button], on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := _make_label(label_text, 15, Color(0.76, 0.84, 0.95))
	lbl.custom_minimum_size = Vector2(74, 34)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	for i in range(options.size()):
		var btn := _make_pill_button(options[i], 14, Color(0.12, 0.16, 0.25, 0.85))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)
		var idx := i
		btn.pressed.connect(func() -> void: on_pick.call(idx))
		row.add_child(btn)
		store.append(btn)

	return row


func _make_powerup_badge(icon_name: String, init_text: String, accent: Color, with_bar: bool) -> Dictionary:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.14, 0.86)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(hbox)

	if _icons.has(icon_name) and _icons[icon_name] != null:
		var tex := TextureRect.new()
		tex.texture = _icons[icon_name]
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(18, 18)
		hbox.add_child(tex)

	var lbl := _make_label(init_text, 13, accent)
	hbox.add_child(lbl)

	var bar: ProgressBar = null
	if with_bar:
		bar = ProgressBar.new()
		bar.max_value = 1.0
		bar.value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(90, 6)
		vbox.add_child(bar)

	return {"panel": panel, "label": lbl, "bar": bar}


func _make_glass_panel(bg: Color, pad: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.45, 0.62, 0.84, 0.34)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_pill_button(txt: String, font_size: int, bg: Color, icon_name: String = "") -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	if icon_name != "" and _icons.has(icon_name):
		b.icon = _icons[icon_name]
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 22)
		b.add_theme_constant_override("h_separation", 8)
	_style_button(b, bg, Color(0.48, 0.66, 0.88, 0.42))
	return b


func _style_button(b: Button, bg: Color, border: Color, corner_r: int = 14, border_w: int = 1) -> void:
	for state_name in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		var factor := 1.15 if state_name == "hover" else (0.86 if state_name == "pressed" else 1.0)
		sb.bg_color = Color(clampf(bg.r * factor, 0, 1), clampf(bg.g * factor, 0, 1), clampf(bg.b * factor, 0, 1), bg.a)
		sb.border_color = border
		sb.set_border_width_all(border_w)
		sb.set_corner_radius_all(corner_r)
		sb.set_content_margin_all(8)
		b.add_theme_stylebox_override(state_name, sb)


func _make_label(txt: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l
