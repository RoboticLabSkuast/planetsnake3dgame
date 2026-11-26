class_name SnakeLogic
extends RefCounted
## Pure classic Snake state machine operating on a SphereGrid.
## Supports input buffering (turn queue), food/bonus spawns, obstacles,
## tail-vacate edge cases, combo scoring, and win/loss tracking.

enum GameMode { CLASSIC = 0, ARCADE = 1, OPEN = 2 }
enum SpeedTier { CHILL = 0, CLASSIC = 1, HYPER = 2 }
enum PowerUpType { NONE = -1, SHIELD = 0, MAGNET = 1, FROST = 2 }

# Start gently slow and accelerate smoothly over elapsed survival time + apples eaten
const BASE_INTERVALS := [0.42, 0.34, 0.23]
const MIN_INTERVALS := [0.21, 0.14, 0.105]
const POWERUP_DURATION := 8.0

var grid: SphereGrid
var game_mode: int = GameMode.CLASSIC
var speed_tier: int = SpeedTier.CLASSIC

var snake_cells: Array[int] = []
var prev_cells: Array[int] = []
var head_dir: int = 0
var prev_head_dir: int = 0

var food_cells: Array[int] = []
var bonus_food_cell: int = -1
var bonus_time_left: float = 0.0
var bonus_max_time: float = 10.0

var powerup_cell: int = -1
var powerup_type: int = PowerUpType.NONE
var powerup_time_left: float = 0.0
var powerup_max_time: float = 12.0

var shield_active: bool = false
var magnet_time_left: float = 0.0
var frost_time_left: float = 0.0
var powerups_collected: int = 0
var _next_powerup_at_apple: int = 4
var _next_bonus_at_apple: int = 5

var obstacles: Dictionary = {}
var wall_cells: Dictionary = {}
var bump_cells: Dictionary = {}
var occupied: Dictionary = {}
var pending_growth: int = 0

var score: int = 0
var apples_eaten: int = 0
var combo: int = 0
var combo_time_left: float = 0.0
var elapsed_time: float = 0.0

var alive: bool = true
var won: bool = false
var death_reason: String = ""

# Buffered turns: stores relative turns (-1 = left, +1 = right, 0 = straight)
# or absolute next local dir resolved against the predicted next step.
var _turn_queue: Array[int] = []
var _queued_world_dirs: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()


func _init(p_grid: SphereGrid = null, seed_val: int = 0) -> void:
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()
	grid = p_grid if p_grid != null else SphereGrid.new(10)
	reset(game_mode, speed_tier)


func reset(mode: int = GameMode.CLASSIC, speed: int = SpeedTier.CLASSIC) -> void:
	game_mode = mode
	speed_tier = speed
	snake_cells.clear()
	prev_cells.clear()
	obstacles.clear()
	wall_cells.clear()
	bump_cells.clear()
	occupied.clear()
	food_cells.clear()
	_turn_queue.clear()
	_queued_world_dirs.clear()

	pending_growth = 0
	score = 0
	apples_eaten = 0
	combo = 0
	combo_time_left = 0.0
	elapsed_time = 0.0
	bonus_food_cell = -1
	bonus_time_left = 0.0
	powerup_cell = -1
	powerup_type = PowerUpType.NONE
	powerup_time_left = 0.0
	shield_active = false
	magnet_time_left = 0.0
	frost_time_left = 0.0
	powerups_collected = 0
	_next_powerup_at_apple = 4
	_next_bonus_at_apple = 5
	alive = true
	won = false
	death_reason = ""

	# Start on the center of face 4 (+Z) heading +Y (dir 0) with length 4
	var mid := grid.grid_n / 2
	var tail_start := grid.cell_id(4, mid, clampi(mid - 2, 0, grid.grid_n - 1))
	var cur := tail_start
	var cur_dir := 0
	var init_chain: Array[int] = [cur]
	for _i in range(3):
		var st := grid.step(cur, cur_dir)
		cur = st["cell"]
		cur_dir = st["dir"]
		init_chain.append(cur)

	# Reverse so index 0 is head
	for i in range(init_chain.size() - 1, -1, -1):
		snake_cells.append(init_chain[i])
		occupied[init_chain[i]] = true
	prev_cells = snake_cells.duplicate()
	head_dir = cur_dir
	prev_head_dir = cur_dir

	if game_mode == GameMode.CLASSIC:
		if grid.grid_n <= 2:
			_spawn_walls_and_bumps(0, 2)
		elif grid.grid_n == 3:
			_spawn_walls_and_bumps(1, 2)
		elif grid.grid_n <= 5:
			_spawn_walls_and_bumps(1, 3)
		else:
			_spawn_walls_and_bumps(maxi(2, grid.grid_n / 3), maxi(4, grid.grid_n / 2))
	elif game_mode == GameMode.ARCADE:
		if grid.grid_n <= 2:
			_spawn_walls_and_bumps(1, 2)
		elif grid.grid_n == 3:
			_spawn_walls_and_bumps(2, 3)
		else:
			_spawn_walls_and_bumps(maxi(4, grid.grid_n / 2 + 1), maxi(8, grid.total_cells / 45))

	_refill_foods()


func get_target_food_count() -> int:
	if grid.grid_n <= 2:
		return 3
	elif grid.grid_n == 3:
		return 4
	elif grid.grid_n <= 5:
		return 5
	elif grid.grid_n <= 8:
		return 6
	elif grid.grid_n <= 10:
		return 8
	return 11


func get_tick_interval(is_boosting: bool = false) -> float:
	var base: float = BASE_INTERVALS[clampi(speed_tier, 0, BASE_INTERVALS.size() - 1)]
	var min_iv: float = MIN_INTERVALS[clampi(speed_tier, 0, MIN_INTERVALS.size() - 1)]
	var time_ramp := elapsed_time * 0.0012
	var food_ramp := float(apples_eaten) * 0.0024
	var total_ramp := minf(time_ramp + food_ramp, base - min_iv)
	var interval := maxf(base - total_ramp, min_iv)
	if frost_time_left > 0.0:
		interval *= 1.45
	if is_boosting:
		interval *= 0.50
	return interval


func queue_relative_turn(rel_turn: int) -> bool:
	## rel_turn: -1 (left) or +1 (right). Buffers up to 2 turns.
	if not alive or won or _turn_queue.size() >= 2:
		return false
	if rel_turn != -1 and rel_turn != 1:
		return false
	_turn_queue.append(rel_turn)
	_queued_world_dirs.clear()
	return true


func queue_screen_direction(desired_world_dir: Vector3) -> bool:
	## Buffers screen-relative directional input against current or predicted next cell.
	if not alive or won or _turn_queue.size() >= 2:
		return false

	# Predict the cell & heading after already-queued turns execute
	var sim_cell := snake_cells[0]
	var sim_dir := head_dir
	for rel in _turn_queue:
		var turned := _apply_rel_turn(sim_dir, rel)
		var st := grid.step(sim_cell, turned)
		sim_cell = st["cell"]
		sim_dir = st["dir"]

	var target_dir := grid.screen_tangent_to_dir(sim_cell, sim_dir, desired_world_dir, false)
	if target_dir == -1:
		return false

	if target_dir == sim_dir:
		# Pressing straight while a 1-turn buffer exists shouldn't discard valid forward flow
		if _turn_queue.size() == 0:
			return false
		_turn_queue.append(0)
		return true
	elif target_dir == SphereGrid.turn_left(sim_dir):
		_turn_queue.append(-1)
		return true
	elif target_dir == SphereGrid.turn_right(sim_dir):
		_turn_queue.append(1)
		return true
	return false


func update_timers(delta: float) -> void:
	if not alive or won:
		return
	elapsed_time += delta
	if combo_time_left > 0.0:
		combo_time_left -= delta
		if combo_time_left <= 0.0:
			combo = 0
	if bonus_food_cell != -1:
		bonus_time_left -= delta
		if bonus_time_left <= 0.0:
			bonus_food_cell = -1
			bonus_time_left = 0.0
	if powerup_cell != -1:
		powerup_time_left -= delta
		if powerup_time_left <= 0.0:
			powerup_cell = -1
			powerup_type = PowerUpType.NONE
			powerup_time_left = 0.0
	magnet_time_left = maxf(0.0, magnet_time_left - delta)
	frost_time_left = maxf(0.0, frost_time_left - delta)


func step_tick() -> Dictionary:
	## Advances the classic Snake simulation by 1 discrete grid step.
	## Returns event flags for audio, particles, and haptics.
	var events := {
		"moved": false,
		"ate_food": false,
		"ate_bonus": false,
		"collected_powerup": PowerUpType.NONE,
		"powerup_cell": -1,
		"shield_smashed": false,
		"smash_cell": -1,
		"magnet_pulled_cells": [],
		"turned": false,
		"died": false,
		"won": false,
		"points_gained": 0,
		"eat_cell": -1,
	}
	if not alive or won:
		return events

	prev_cells = snake_cells.duplicate()
	prev_head_dir = head_dir

	if _turn_queue.size() > 0:
		var rel: int = _turn_queue.pop_front()
		if rel != 0:
			head_dir = _apply_rel_turn(head_dir, rel)
			events["turned"] = true

	var st := grid.step(snake_cells[0], head_dir)
	var next_cell: int = st["cell"]
	var next_dir: int = st["dir"]

	# Classic Snake rule: tail cell vacates unless growing on this tick
	var tail_cell := snake_cells[snake_cells.size() - 1]
	var hits_obstacle := obstacles.has(next_cell)
	var hits_self := occupied.has(next_cell) and not (pending_growth == 0 and next_cell == tail_cell)

	if hits_obstacle:
		if shield_active:
			shield_active = false
			obstacles.erase(next_cell)
			wall_cells.erase(next_cell)
			bump_cells.erase(next_cell)
			events["shield_smashed"] = true
			events["smash_cell"] = next_cell
		else:
			alive = false
			death_reason = "wall" if wall_cells.has(next_cell) else "obstacle"
			events["died"] = true
			return events

	if hits_self:
		alive = false
		death_reason = "self"
		events["died"] = true
		return events

	# Move snake head forward
	head_dir = next_dir
	snake_cells.insert(0, next_cell)
	occupied[next_cell] = true
	events["moved"] = true

	# Check power-up pickup on head cell
	if next_cell == powerup_cell and powerup_type != PowerUpType.NONE:
		var ptype := powerup_type
		powerup_cell = -1
		powerup_type = PowerUpType.NONE
		powerup_time_left = 0.0
		powerups_collected += 1
		if ptype == PowerUpType.SHIELD:
			shield_active = true
		elif ptype == PowerUpType.MAGNET:
			magnet_time_left = POWERUP_DURATION
		elif ptype == PowerUpType.FROST:
			frost_time_left = POWERUP_DURATION
		score += 25
		events["collected_powerup"] = ptype
		events["powerup_cell"] = next_cell
		events["points_gained"] = int(events["points_gained"]) + 25

	# Check direct food consumption before tail pop so eating grows immediately
	var food_idx := food_cells.find(next_cell)
	if food_idx >= 0:
		_consume_food_at(food_idx, next_cell, events)
	elif next_cell == bonus_food_cell:
		_consume_bonus_food(next_cell, events)

	# Magnet 2-step attraction radius pulls nearby fruits directly to the snake
	if magnet_time_left > 0.0:
		var reach := _collect_cells_within_two_steps(next_cell)
		var pulled: Array[int] = []
		for i in range(food_cells.size() - 1, -1, -1):
			var fc := food_cells[i]
			if reach.has(fc):
				pulled.append(fc)
				_consume_food_at(i, fc, events)
		if bonus_food_cell != -1 and reach.has(bonus_food_cell):
			pulled.append(bonus_food_cell)
			_consume_bonus_food(bonus_food_cell, events)
		events["magnet_pulled_cells"] = pulled

	if pending_growth > 0:
		pending_growth -= 1
	else:
		var removed: int = snake_cells.pop_back()
		if removed != next_cell:
			occupied.erase(removed)

	if events["ate_food"] or events["ate_bonus"]:
		if snake_cells.size() + obstacles.size() >= grid.total_cells:
			won = true
			food_cells.clear()
			events["won"] = true
			return events
		if events["ate_food"]:
			_refill_foods()
			if apples_eaten >= _next_bonus_at_apple and bonus_food_cell == -1:
				_spawn_bonus_food()
				_next_bonus_at_apple = apples_eaten + 5
			if apples_eaten >= _next_powerup_at_apple and powerup_cell == -1:
				_spawn_powerup()
				_next_powerup_at_apple = apples_eaten + _rng.randi_range(4, 6)

	return events


static func _apply_rel_turn(dir: int, rel: int) -> int:
	if rel < 0:
		return SphereGrid.turn_left(dir)
	elif rel > 0:
		return SphereGrid.turn_right(dir)
	return dir


func _spawn_walls_and_bumps(wall_count: int, bump_count: int) -> void:
	# Keep a generous safe corridor ahead and around the starting snake
	var safe_cells := {}
	for c in snake_cells:
		safe_cells[c] = true
		for d in range(4):
			safe_cells[grid.get_neighbor(c, d)] = true
	var ahead := snake_cells[0]
	var adir := head_dir
	var safe_steps := mini(9, maxi(2, grid.grid_n))
	for _i in range(safe_steps):
		var st := grid.step(ahead, adir)
		ahead = st["cell"]
		adir = st["dir"]
		safe_cells[ahead] = true
		safe_cells[grid.get_neighbor(ahead, SphereGrid.turn_left(adir))] = true
		safe_cells[grid.get_neighbor(ahead, SphereGrid.turn_right(adir))] = true

	var candidates: Array[int] = []
	for cid in range(grid.total_cells):
		if not safe_cells.has(cid):
			candidates.append(cid)

	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	# 1. Place short continuous 2-3 cell stone walls with full connectivity verification
	var walls_placed := 0
	for cid in candidates:
		if walls_placed >= wall_count:
			break
		if obstacles.has(cid) or _touches_obstacle(cid):
			continue
		var dir := _rng.randi_range(0, 3)
		var seg_len := _rng.randi_range(2, 3)
		var chain: Array[int] = [cid]
		var cur := cid
		var cur_d := dir
		var valid := true
		for _step in range(seg_len - 1):
			var st := grid.step(cur, cur_d)
			cur = st["cell"]
			cur_d = st["dir"]
			if safe_cells.has(cur) or obstacles.has(cur) or _touches_obstacle(cur, chain):
				valid = false
				break
			chain.append(cur)
		if not valid or chain.size() < 2:
			continue
		for w in chain:
			obstacles[w] = true
			wall_cells[w] = true
		if _is_free_space_connected():
			walls_placed += 1
		else:
			for w in chain:
				obstacles.erase(w)
				wall_cells.erase(w)

	# 2. Place single rocky mound bumps safely spaced from walls & each other
	var bumps_placed := 0
	for cid in candidates:
		if bumps_placed >= bump_count:
			break
		if obstacles.has(cid) or _touches_obstacle(cid):
			continue
		obstacles[cid] = true
		bump_cells[cid] = true
		if _is_free_space_connected():
			bumps_placed += 1
		else:
			obstacles.erase(cid)
			bump_cells.erase(cid)


func _touches_obstacle(cid: int, ignore_list: Array[int] = []) -> bool:
	for d in range(4):
		var nb := grid.get_neighbor(cid, d)
		if obstacles.has(nb) and not ignore_list.has(nb):
			return true
		var st1 := grid.step(cid, d)
		var diag1 := grid.get_neighbor(st1["cell"], SphereGrid.turn_right(st1["dir"]))
		if obstacles.has(diag1) and not ignore_list.has(diag1):
			return true
	return false


func _is_free_space_connected() -> bool:
	var start: int = snake_cells[0]
	var visited := {start: true}
	var queue: Array[int] = [start]
	var head_idx := 0
	while head_idx < queue.size():
		var cur := queue[head_idx]
		head_idx += 1
		for d in range(4):
			var nb := grid.get_neighbor(cur, d)
			if not obstacles.has(nb) and not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return visited.size() + obstacles.size() == grid.total_cells


func _refill_foods() -> void:
	var target := get_target_food_count()
	if food_cells.size() >= target:
		return
	var free := _collect_free_cells()
	# Shuffle free cells so multiple spawned fruits spread naturally around the globe
	for i in range(free.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := free[i]
		free[i] = free[j]
		free[j] = tmp
	var needed := mini(target - food_cells.size(), free.size())
	for k in range(needed):
		food_cells.append(free[k])


func _consume_food_at(food_idx: int, cell_id: int, events: Dictionary) -> void:
	apples_eaten += 1
	pending_growth += 1
	combo = mini(combo + 1, 5)
	combo_time_left = 4.5
	var mult := 2 if magnet_time_left > 0.0 else 1
	var pts := (10 + (combo - 1) * 5) * mult
	score += pts
	events["ate_food"] = true
	events["points_gained"] = int(events["points_gained"]) + pts
	if int(events["eat_cell"]) == -1:
		events["eat_cell"] = cell_id
	food_cells.remove_at(food_idx)


func _consume_bonus_food(cell_id: int, events: Dictionary) -> void:
	pending_growth += 2
	combo = mini(combo + 1, 5)
	combo_time_left = 5.0
	var mult := 2 if magnet_time_left > 0.0 else 1
	var bonus_pts := (50 + int(ceil(bonus_time_left)) * 5) * mult
	score += bonus_pts
	events["ate_bonus"] = true
	events["points_gained"] = int(events["points_gained"]) + bonus_pts
	if int(events["eat_cell"]) == -1:
		events["eat_cell"] = cell_id
	bonus_food_cell = -1
	bonus_time_left = 0.0


func _collect_cells_within_two_steps(origin: int) -> Dictionary:
	var reach := {}
	var ring1: Array[int] = []
	for d in range(4):
		var nb := grid.get_neighbor(origin, d)
		if nb >= 0 and nb != origin:
			reach[nb] = true
			ring1.append(nb)
	for r1 in ring1:
		for d in range(4):
			var nb2 := grid.get_neighbor(r1, d)
			if nb2 >= 0 and nb2 != origin:
				reach[nb2] = true
	return reach


func _spawn_powerup() -> void:
	var free := _collect_free_cells()
	if free.is_empty():
		powerup_cell = -1
		powerup_type = PowerUpType.NONE
		return
	var pool: Array[int] = [PowerUpType.MAGNET, PowerUpType.FROST]
	if game_mode != GameMode.OPEN:
		pool.append(PowerUpType.SHIELD)
	powerup_type = pool[_rng.randi_range(0, pool.size() - 1)]
	powerup_cell = free[_rng.randi_range(0, free.size() - 1)]
	powerup_time_left = powerup_max_time


func _spawn_bonus_food() -> void:
	var free := _collect_free_cells()
	if free.is_empty():
		bonus_food_cell = -1
		return
	bonus_food_cell = free[_rng.randi_range(0, free.size() - 1)]
	bonus_time_left = bonus_max_time


func _collect_free_cells() -> Array[int]:
	var food_set := {}
	for fc in food_cells:
		food_set[fc] = true
	var free: Array[int] = []
	for cid in range(grid.total_cells):
		if not occupied.has(cid) and not obstacles.has(cid) and not food_set.has(cid) and cid != bonus_food_cell and cid != powerup_cell:
			free.append(cid)
	return free
