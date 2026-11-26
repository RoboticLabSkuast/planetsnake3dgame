extends SceneTree
## Automated headless verification suite for SphereGrid, SnakeLogic,
## ProceduralMeshes, and main scene instantiation.

const SphereGridScript = preload("res://scripts/sphere_grid.gd")
const SnakeLogicScript = preload("res://scripts/snake_logic.gd")
const ProceduralMeshesScript = preload("res://scripts/procedural_meshes.gd")

var _failures := 0
var _scene_inst: Node = null
var _smoke_frames := 0


func _initialize() -> void:
	print("=== Running Planet Snake 3D Automated Verification ===")
	_test_sphere_grid_topology(2)
	_test_sphere_grid_topology(3)
	_test_sphere_grid_topology(5)
	_test_sphere_grid_topology(8)
	_test_sphere_grid_topology(10)
	_test_sphere_grid_topology(14)
	_test_equiangular_mesh(10)
	_test_snake_movement_and_growth()
	_test_turn_buffering_and_reverse_block()
	_test_tail_vacate_rule()
	_test_obstacles_and_collision()
	_test_win_condition_on_small_grid()
	_test_procedural_meshes()
	_test_powerups_shield_magnet_frost()

	var packed: PackedScene = load("res://scenes/main.tscn")
	_assert(packed != null, "main.tscn loads")
	_scene_inst = packed.instantiate()
	_assert(_scene_inst != null, "main.tscn instantiates")
	root.add_child(_scene_inst)


func _process(delta: float) -> bool:
	_smoke_frames += 1
	if _smoke_frames == 2 and _scene_inst != null:
		_scene_inst.save_disabled = true
		_assert(_scene_inst.clouds_mesh_inst != null, "cloud shell created")
		_assert(_scene_inst.lamps_root != null and _scene_inst._lamp_dirs.size() > 0, "dark-side street lamps generated")
		_assert(_scene_inst.boost_particles != null and _scene_inst.slither_dust_particles != null, "trail & dust particles created")
		_assert(_scene_inst.crash_particles != null and _scene_inst.powerup_burst_particles != null, "burst particles created")
		_scene_inst.apply_settings(0, 0, 1, 1, 0, 0, true, true, 2)
		_assert(_scene_inst.selected_skin == 2, "apply_settings updates skin index")
		_scene_inst.set_grid_size(2)
		_assert(_scene_inst.selected_grid_n == 2 and _scene_inst.grid.total_cells == 24, "set_grid_size(2) rebuilds 2x2x6 globe")
		_scene_inst.set_grid_size(14)
		_assert(_scene_inst.selected_grid_n == 14 and _scene_inst.grid.total_cells == 1176, "set_grid_size(14) rebuilds 14x14x6 globe")
		_scene_inst.start_new_game()
		_assert(_scene_inst.play_state == 1, "game transitions to PLAYING")
		_scene_inst.set_boosting(true)
		_scene_inst.apply_directional_input(Vector2(1.0, 0.0))
	elif _smoke_frames == 6 and _scene_inst != null:
		_assert(_scene_inst.logic.alive, "snake remains alive during live ticks")
		_scene_inst.free()
		_scene_inst = null
	elif _smoke_frames >= 8:
		if _failures > 0:
			printerr("FAILED: %d assertion(s) failed." % _failures)
			quit(1)
		else:
			print("ALL TESTS PASSED!")
			quit(0)
		return true
	return false


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("ASSERTION FAILED: %s" % msg)


func _test_sphere_grid_topology(n: int) -> void:
	var grid = SphereGridScript.new(n)
	_assert(grid.total_cells == 6 * n * n, "total_cells mismatch for N=%d" % n)

	for cid in range(grid.total_cells):
		var c_norm: Vector3 = grid.cell_normals[cid]
		_assert(absf(c_norm.length() - 1.0) < 1e-4, "cell_normal not unit at %d" % cid)

		var seen_neighbors := {}
		for d in range(4):
			var st: Dictionary = grid.step(cid, d)
			var nb: int = st["cell"]
			var fwd_d: int = st["dir"]
			_assert(nb >= 0 and nb < grid.total_cells, "neighbor out of bounds")
			_assert(nb != cid, "self-neighbor at %d" % cid)
			seen_neighbors[nb] = true

			# Involution check: stepping forward then reversing twice returns to cid
			var rev_d := SphereGridScript.opposite_dir(fwd_d)
			var back: Dictionary = grid.step(nb, rev_d)
			_assert(back["cell"] == cid, "edge involution cell mismatch N=%d cid=%d d=%d" % [n, cid, d])
			_assert(SphereGridScript.opposite_dir(back["dir"]) == d, "edge involution dir mismatch N=%d cid=%d d=%d" % [n, cid, d])

			# Right-handed basis consistency across every cell & corner
			var t_d: Vector3 = grid.get_edge_tangent(cid, d)
			var t_right: Vector3 = grid.get_edge_tangent(cid, SphereGridScript.turn_right(d))
			_assert(absf(t_d.dot(c_norm)) < 1e-4, "edge tangent not orthogonal to normal")
			# Right-handed check: t_d.cross(c_norm) points along +right
			_assert(t_d.cross(c_norm).dot(t_right) > 0.7, "handedness broken at N=%d cid=%d d=%d" % [n, cid, d])

		_assert(seen_neighbors.size() == 4, "cell %d does not have 4 distinct neighbors" % cid)


func _test_equiangular_mesh(n: int) -> void:
	var grid = SphereGridScript.new(n)
	var mesh: ArrayMesh = grid.build_planet_mesh(4.0, 4)
	_assert(mesh.get_surface_count() == 1, "planet mesh surface count")
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	_assert(verts.size() == norms.size() and verts.size() > 0, "planet mesh vertex count")
	for i in range(verts.size()):
		_assert(absf(verts[i].length() - 4.0) < 0.12, "planet mesh vertex radius within terrain bump bounds")
		_assert(absf(norms[i].length() - 1.0) < 1e-3, "planet mesh normal length")


func _test_snake_movement_and_growth() -> void:
	var grid = SphereGridScript.new(10)
	var logic = SnakeLogicScript.new(grid, 12345)
	logic.reset(SnakeLogicScript.GameMode.CLASSIC, SnakeLogicScript.SpeedTier.CLASSIC)

	_assert(logic.snake_cells.size() == 4, "initial snake length == 4")
	_assert(logic.food_cells.size() == logic.get_target_food_count(), "spawns multiple foods simultaneously")
	# Ensure all spawned foods are unique and unoccupied
	var unique_food := {}
	for fc in logic.food_cells:
		_assert(not logic.occupied.has(fc), "food does not overlap snake")
		unique_food[fc] = true
	_assert(unique_food.size() == logic.food_cells.size(), "all simultaneous foods are on distinct cells")

	var start_head: int = logic.snake_cells[0]
	var expected_next: int = grid.step(start_head, logic.head_dir)["cell"]
	logic.food_cells.erase(expected_next)

	var ev: Dictionary = logic.step_tick()
	_assert(ev["moved"] and not ev["died"], "first step moves cleanly")
	_assert(logic.snake_cells[0] == expected_next, "head stepped onto expected neighbor")

	# Place food directly ahead and verify eating + growth + score + multi-food refill
	var ahead: int = grid.step(logic.snake_cells[0], logic.head_dir)["cell"]
	if not logic.food_cells.has(ahead):
		logic.food_cells[0] = ahead
	var eat_ev: Dictionary = logic.step_tick()
	_assert(eat_ev["ate_food"] and eat_ev["points_gained"] >= 10, "ate food event")
	_assert(logic.score >= 10 and logic.apples_eaten == 1, "score & apple count incremented")
	_assert(logic.snake_cells.size() == 5, "snake grew to length 5 immediately on eat")
	_assert(logic.food_cells.size() == logic.get_target_food_count(), "multi-food pool refilled after eating")


func _test_turn_buffering_and_reverse_block() -> void:
	var grid = SphereGridScript.new(10)
	var logic = SnakeLogicScript.new(grid, 777)
	logic.reset(SnakeLogicScript.GameMode.CLASSIC, SnakeLogicScript.SpeedTier.CLASSIC)

	# Pressing directly backwards relative to current heading must be rejected
	var back_world: Vector3 = -grid.get_edge_tangent(logic.snake_cells[0], logic.head_dir)
	var accepted_back: bool = logic.queue_screen_direction(back_world)
	_assert(not accepted_back, "180-degree reversal must be blocked")

	# Rapid 2-step hairpin turn (Left then Left) buffers cleanly without dying
	var ok1: bool = logic.queue_relative_turn(-1)
	var ok2: bool = logic.queue_relative_turn(-1)
	var ok3: bool = logic.queue_relative_turn(-1)
	_assert(ok1 and ok2 and not ok3, "turn queue caps at 2 inputs")
	logic.food_cells.clear()
	var e1: Dictionary = logic.step_tick()
	var e2: Dictionary = logic.step_tick()
	_assert(e1["turned"] and e2["turned"] and logic.alive, "hairpin double turn executes safely")


func _test_tail_vacate_rule() -> void:
	var grid = SphereGridScript.new(4)
	var logic = SnakeLogicScript.new(grid, 99)
	logic.reset(SnakeLogicScript.GameMode.CLASSIC, SnakeLogicScript.SpeedTier.CLASSIC)
	# Construct a 4-cell 2x2 square loop on face 4 so head steps onto tail_cell
	var c0: int = grid.cell_id(4, 1, 2)
	var c1: int = grid.cell_id(4, 1, 1)
	var c2: int = grid.cell_id(4, 2, 1)
	var c3: int = grid.cell_id(4, 2, 2)
	logic.snake_cells.assign([c0, c1, c2, c3])
	logic.prev_cells = logic.snake_cells.duplicate()
	logic.occupied = {c0: true, c1: true, c2: true, c3: true}
	logic.head_dir = 1 # +right from (1,2) -> (2,2) == c3 (tail!)
	logic.pending_growth = 0
	logic.food_cells.assign([grid.cell_id(4, 0, 0)])

	var ev: Dictionary = logic.step_tick()
	_assert(ev["moved"] and not ev["died"] and logic.snake_cells[0] == c3, "moving into vacating tail tip must succeed")

	# Now test when growing: moving into tail tip MUST collide
	logic.pending_growth = 1
	logic.head_dir = 2 # -up from (2,2) -> (2,1) == c2 (current tail!)
	var ev_grow: Dictionary = logic.step_tick()
	_assert(ev_grow["died"] and logic.death_reason == "self", "moving into non-vacating growing tail must collide")


func _test_obstacles_and_collision() -> void:
	var grid = SphereGridScript.new(10)
	var logic = SnakeLogicScript.new(grid, 555)
	logic.reset(SnakeLogicScript.GameMode.CLASSIC, SnakeLogicScript.SpeedTier.CLASSIC)
	_assert(logic.wall_cells.size() >= 2 and logic.bump_cells.size() >= 4, "classic mode spawns stone walls and bumps")
	_assert(logic.get_tick_interval() >= 0.32, "starts slow and comfortable")
	logic.update_timers(90.0)
	_assert(logic.get_tick_interval() < 0.28, "speed increases gradually over time")

	logic.reset(SnakeLogicScript.GameMode.ARCADE, SnakeLogicScript.SpeedTier.CLASSIC)
	_assert(logic.obstacles.size() >= 10, "arcade mode spawns dense walls and bumps")
	var ahead: int = grid.step(logic.snake_cells[0], logic.head_dir)["cell"]
	logic.obstacles[ahead] = true
	logic.wall_cells[ahead] = true
	var ev: Dictionary = logic.step_tick()
	_assert(ev["died"] and logic.death_reason == "wall", "wall collision triggers wall death")

	logic.reset(SnakeLogicScript.GameMode.OPEN, SnakeLogicScript.SpeedTier.CLASSIC)
	_assert(logic.obstacles.is_empty(), "open mode has no obstacle walls or bumps")


func _test_win_condition_on_small_grid() -> void:
	var grid = SphereGridScript.new(4)
	var logic = SnakeLogicScript.new(grid, 333)
	logic.reset(SnakeLogicScript.GameMode.OPEN, SnakeLogicScript.SpeedTier.CLASSIC)
	# Simulate filling 95 of 96 cells, leaving 1 free cell ahead containing food
	logic.snake_cells.clear()
	logic.occupied.clear()
	var head: int = grid.cell_id(4, 0, 0)
	var next_c: int = grid.step(head, 0)["cell"]
	for cid in range(grid.total_cells):
		if cid != next_c:
			logic.snake_cells.append(cid)
			logic.occupied[cid] = true
	# Put head at index 0
	var idx: int = logic.snake_cells.find(head)
	logic.snake_cells[idx] = logic.snake_cells[0]
	logic.snake_cells[0] = head
	logic.prev_cells = logic.snake_cells.duplicate()
	logic.head_dir = 0
	logic.food_cells.assign([next_c])

	var ev: Dictionary = logic.step_tick()
	_assert(ev["won"] and logic.won, "filling all sphere cells triggers win")


func _test_procedural_meshes() -> void:
	var grid = SphereGridScript.new(10)
	var spine := PackedVector3Array([
		grid.cell_normals[grid.cell_id(4, 5, 5)],
		grid.cell_normals[grid.cell_id(4, 5, 4)],
		grid.cell_normals[grid.cell_id(4, 5, 3)],
		grid.cell_normals[grid.cell_id(4, 4, 3)],
	])
	var snake_mesh := ArrayMesh.new()
	ProceduralMeshesScript.update_snake_body_mesh(snake_mesh, spine, 4.0, 0.21, 0.628, 1.2)
	_assert(snake_mesh.get_surface_count() == 1, "snake body mesh surface generated")

	var mat := StandardMaterial3D.new()
	var head_dict := ProceduralMeshesScript.build_snake_head_node(0.21, mat, mat, mat, mat)
	_assert(head_dict.has("root") and head_dict.has("jaw_pivot") and head_dict.has("tongue_pivot"), "snake head hierarchy built")
	(head_dict["root"] as Node).free()

	var apple := ProceduralMeshesScript.build_apple_node(0.22, mat, mat, mat)
	_assert(apple.get_child_count() == 3, "apple node has body, stem, leaf")
	apple.free()

	var boulder := ProceduralMeshesScript.build_boulder_mesh(0.25, 42)
	_assert(boulder.get_surface_count() == 1, "boulder mesh generated")

	for ptype in range(3):
		var pm := ProceduralMeshesScript.build_powerup_mesh(0.25, ptype)
		_assert(pm.get_surface_count() == 1, "powerup mesh %d generated" % ptype)
	var ring := ProceduralMeshesScript.build_shockwave_ring_mesh(0.18, 0.34)
	_assert(ring.get_surface_count() == 1, "shockwave ring mesh generated")
	var lamp := ProceduralMeshesScript.build_street_lamp_node(0.62, mat, mat)
	_assert(lamp.get_child_count() == 4, "street lamp node has base, post, hood, bulb")
	lamp.free()


func _test_powerups_shield_magnet_frost() -> void:
	var grid = SphereGridScript.new(10)
	var logic = SnakeLogicScript.new(grid, 909)
	logic.reset(SnakeLogicScript.GameMode.OPEN, SnakeLogicScript.SpeedTier.CLASSIC)

	# 0. Verify powerup spawn & tiny 2x2 / 3x3 globe compatibility
	for tiny_n in [2, 3]:
		var tg = SphereGridScript.new(tiny_n)
		for m in [SnakeLogicScript.GameMode.CLASSIC, SnakeLogicScript.GameMode.ARCADE, SnakeLogicScript.GameMode.OPEN]:
			var tl = SnakeLogicScript.new(tg, 42)
			tl.reset(m, SnakeLogicScript.SpeedTier.CLASSIC)
			_assert(tl.snake_cells.size() == 4 and tl.food_cells.size() >= 3, "tiny %dx%d spawns cleanly in mode %d" % [tiny_n, tiny_n, m])
			_assert(tl._is_free_space_connected(), "tiny %dx%d stays connected in mode %d" % [tiny_n, tiny_n, m])

	for mode in [SnakeLogicScript.GameMode.OPEN, SnakeLogicScript.GameMode.CLASSIC]:
		logic.reset(mode, SnakeLogicScript.SpeedTier.CLASSIC)
		var cur_c: int = logic.snake_cells[0]
		var cur_d: int = logic.head_dir
		for step_i in range(4):
			var st: Dictionary = grid.step(cur_c, cur_d)
			cur_c = int(st["cell"])
			cur_d = int(st["dir"])
			logic.obstacles.erase(cur_c)
			logic.wall_cells.erase(cur_c)
			logic.bump_cells.erase(cur_c)
			if not logic.food_cells.has(cur_c):
				logic.food_cells.append(cur_c)
			var ev_sp: Dictionary = logic.step_tick()
			_assert(ev_sp["ate_food"], "ate apple during spawn test")
		_assert(logic.powerup_cell >= 0 and logic.powerup_type != SnakeLogicScript.PowerUpType.NONE, "powerup spawns cleanly in mode %d" % mode)
		if mode == SnakeLogicScript.GameMode.OPEN:
			_assert(logic.powerup_type != SnakeLogicScript.PowerUpType.SHIELD, "open mode does not spawn wall-only shield")

	# 1. Shield wall-shatter check & subsequent unprotected collision
	logic.reset(SnakeLogicScript.GameMode.OPEN, SnakeLogicScript.SpeedTier.CLASSIC)
	var st1: Dictionary = grid.step(logic.snake_cells[0], logic.head_dir)
	var wall_ahead: int = st1["cell"]
	var st2: Dictionary = grid.step(wall_ahead, st1["dir"])
	var wall_second: int = st2["cell"]
	logic.food_cells.assign([])
	logic.obstacles[wall_ahead] = true
	logic.wall_cells[wall_ahead] = true
	logic.obstacles[wall_second] = true
	logic.wall_cells[wall_second] = true
	logic.shield_active = true

	var ev_smash: Dictionary = logic.step_tick()
	_assert(ev_smash["shield_smashed"] and not ev_smash["died"] and logic.alive, "shield smashes obstacle without dying")
	_assert(not logic.shield_active and not logic.obstacles.has(wall_ahead), "shield consumed and obstacle removed")
	_assert(logic.snake_cells[0] == wall_ahead, "snake advances onto smashed cell")

	var ev_crash: Dictionary = logic.step_tick()
	_assert(ev_crash["died"] and not logic.alive and logic.death_reason == "wall", "unshielded wall hit still ends run")

	# 2. Magnet 2-step pull + 2x points check & Frost speed slowdown
	logic.reset(SnakeLogicScript.GameMode.OPEN, SnakeLogicScript.SpeedTier.CLASSIC)
	var next_st: Dictionary = grid.step(logic.snake_cells[0], logic.head_dir)
	var next_c: int = next_st["cell"]
	var pull_a: int = grid.get_neighbor(next_c, SphereGridScript.turn_left(next_st["dir"]))
	var pull_b: int = grid.step(next_c, next_st["dir"])["cell"]
	var far_c: int = grid.cell_id(0, 0, 0)
	logic.food_cells.assign([pull_a, pull_b, far_c])
	logic.magnet_time_left = 6.0
	var pre_score: int = logic.score
	var ev_mag: Dictionary = logic.step_tick()
	_assert(ev_mag["ate_food"] and ev_mag["magnet_pulled_cells"].size() == 2, "magnet pulls nearby apples within 2 steps")
	_assert(logic.score - pre_score == 50, "magnet grants 2x score multiplier (20 + 30)")
	_assert(logic.food_cells.has(far_c), "magnet does not pull distant apples")

	var base_iv: float = logic.get_tick_interval(false)
	logic.frost_time_left = 6.0
	var frost_iv: float = logic.get_tick_interval(false)
	_assert(frost_iv > base_iv * 1.4, "frost slows snake tick interval")
	logic.update_timers(7.0)
	_assert(logic.magnet_time_left == 0.0 and logic.frost_time_left == 0.0, "powerup timers expire cleanly")
