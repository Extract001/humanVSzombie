extends Node
## Walker difficulty scenarios S1–S6 + a 40-zombie performance run (DEVELOPMENT_ROADMAP).
## These MEASURE difficulty; they don't decide it. Values only change when these numbers
## and the owner's play-test agree.
##
## Run: godot --headless --path . --fixed-fps 60 res://tests/scenarios/difficulty_scenarios.tscn
## Prints a metrics table and "SCENARIOS COMPLETED".

const SEEDS: Array[int] = [11, 22, 33]
const DT: float = 1.0 / 60.0

var _p: Player
var _arena: Dictionary
var _shoves: int = 0
var _swings: int = 0
var _bites: int = 0
var _kills: int = 0
var _baseline_ms: float = 0.0


func _ready() -> void:
	SaveSystem.path = "user://tool_save.json"
	GameState.street_spawns_disabled = true  # fun pass: measure the placed/horde zombies only
	GameState.records_disabled = true
	GameState.intro_disabled = true  # never touch the player's real save
	await get_tree().process_frame
	print("")
	print("WALKER DIFFICULTY SCENARIOS  (Walker: chase 45 px/s, bite 12, wind-up 0.4 s; player walk 80 px/s)")
	print("%-62s | %-9s | %6s | %5s | %5s | %5s | %s" % ["scenario (3 seeds each)", "outcome", "dmg", "bites", "kills", "time", "notes"])
	print("-".repeat(130))
	for i in 6:
		for s in SEEDS:
			seed(s)
			var r: Dictionary = await _run(i)
			print("%-62s | %-9s | %6.0f | %5d | %5d | %4.1fs | %s" % [
				ArenaBuilder.NAMES[i] + "  seed %d" % s, r.outcome, r.damage, r.bites, r.kills, r.time, r.get("notes", "")])
	await _performance_run()
	AudioManager.stop_all()
	await get_tree().process_frame
	print("SCENARIOS COMPLETED")
	get_tree().quit(0)


func _setup(index: int) -> void:
	_arena = ArenaBuilder.build(index)
	add_child(_arena.root)
	_p = load("res://scenes/player/player.tscn").instantiate()
	_p.use_mouse_aim = false
	_p.position = _arena.player_spawn
	_arena.root.get_node("Actors").add_child(_p)
	_shoves = 0
	_swings = 0
	_bites = 0
	_kills = 0
	_p.health.damaged.connect(func(_a: float, _s: Node) -> void: _bites += 1)
	_p.weapons.attacked.connect(func(_o: Vector2, _w: WeaponData) -> void: _swings += 1)
	for z in _arena.walkers:
		(z as Zombie).died.connect(func() -> void: _kills += 1)
	# let the navigation map sync
	for f in 20:
		await get_tree().physics_frame


func _teardown() -> void:
	_arena.root.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _run(index: int) -> Dictionary:
	await _setup(index)
	var result: Dictionary
	match index:
		0:
			result = await _bot_walk(Vector2.RIGHT, 5.0)
		1:
			result = await _bot_flee(8.0)
		2, 4:
			result = await _bot_fight_to_exit(25.0)
		3:
			result = await _bot_search_then_escape(1.2, 20.0)
		5:
			result = await _bot_gunshot(12.0)
	result["damage"] = 100.0 - _p.health.current_health
	result["bites"] = _bites
	result["kills"] = _kills
	await _teardown()
	return result


# ---------------- bots ----------------

func _living() -> Array[Zombie]:
	var out: Array[Zombie] = []
	for z in _arena.walkers:
		if is_instance_valid(z) and not (z as Zombie).health.is_dead:
			out.append(z)
	return out


func _nearest() -> Zombie:
	var best: Zombie = null
	for z in _living():
		if best == null or z.global_position.distance_to(_p.global_position) < best.global_position.distance_to(_p.global_position):
			best = z
	return best


## Fights back when something is in reach. Returns true while busy fighting.
func _fight() -> bool:
	var z: Zombie = _nearest()
	if z == null:
		return false
	var d: float = z.global_position.distance_to(_p.global_position)
	if d > 26.0:
		return false
	_p.aim_direction = _p.global_position.direction_to(z.global_position)
	if d < 20.0 and _p.shove_ready() and _p.stamina >= _p.stats.shove_stamina_cost and not z.is_staggered():
		if _p.try_shove():
			_shoves += 1
	else:
		_p.try_attack()
	return true


func _path_direction(goal: Vector2) -> Vector2:
	var map: RID = _p.get_world_2d().navigation_map
	var path: PackedVector2Array = NavigationServer2D.map_get_path(map, _p.global_position, goal, true)
	for point in path:
		if point.distance_to(_p.global_position) > 4.0:
			return _p.global_position.direction_to(point)
	return _p.global_position.direction_to(goal)


func _done(outcome: String, t: float, notes: String = "") -> Dictionary:
	_p.move_override = Vector2.ZERO
	return {"outcome": outcome, "time": t, "notes": notes}


func _bot_walk(direction: Vector2, seconds: float) -> Dictionary:
	var t := 0.0
	while t < seconds:
		if _p.is_dead():
			return _done("DIED", t)
		_p.move_override = direction
		_p.aim_direction = direction
		await get_tree().physics_frame
		t += DT
	var z: Zombie = _nearest()
	var gap: float = z.global_position.distance_to(_p.global_position) if z else 0.0
	return _done("ESCAPED" if _bites == 0 else "HURT", t, "gap at end %.0f px" % gap)


func _bot_flee(seconds: float) -> Dictionary:
	var t := 0.0
	var b: Rect2 = (_arena.bounds as Rect2).grow(-28.0)
	while t < seconds:
		if _p.is_dead():
			return _done("DIED", t)
		if _fight():
			_p.move_override = Vector2.ZERO
		else:
			var away := Vector2.ZERO
			for z in _living():
				var d: Vector2 = _p.global_position - z.global_position
				if d.length() < 220.0:
					away += d.normalized() / maxf(d.length(), 1.0)
			var dir: Vector2 = away.normalized() if away != Vector2.ZERO else Vector2.ZERO
			# keep away from the arena edges
			if not b.has_point(_p.global_position + dir * 20.0):
				dir = (b.get_center() - _p.global_position).normalized().rotated(PI * 0.5)
			_p.move_override = dir
			if dir != Vector2.ZERO:
				_p.aim_direction = dir
		await get_tree().physics_frame
		t += DT
	return _done("SURVIVED", t, "shoves %d, swings %d" % [_shoves, _swings])


func _bot_fight_to_exit(limit: float) -> Dictionary:
	var t := 0.0
	var goal: Vector2 = (_arena.exit as Rect2).get_center()
	while t < limit:
		if _p.is_dead():
			return _done("DIED", t, "shoves %d, swings %d" % [_shoves, _swings])
		if (_arena.exit as Rect2).has_point(_p.global_position):
			return _done("ESCAPED", t, "shoves %d, swings %d" % [_shoves, _swings])
		if _fight():
			_p.move_override = Vector2.ZERO
		else:
			var dir: Vector2 = _path_direction(goal)
			_p.move_override = dir
			_p.aim_direction = dir
		await get_tree().physics_frame
		t += DT
	return _done("STUCK", t, "shoves %d, swings %d" % [_shoves, _swings])


func _bot_search_then_escape(search_time: float, limit: float) -> Dictionary:
	# "Searching a cabinet": stand still for search_time (searching makes a 60 px noise).
	NoiseSystem.emit_noise(_p.global_position, 60.0, _p)
	var t := 0.0
	var bites_while_searching := 0
	while t < search_time:
		_p.move_override = Vector2.ZERO
		_p.aim_direction = Vector2.UP
		await get_tree().physics_frame
		t += DT
	bites_while_searching = _bites
	var r: Dictionary = await _bot_fight_to_exit(limit)
	r["time"] += t
	r["notes"] = "bites while searching %d; %s" % [bites_while_searching, r.get("notes", "")]
	return r


func _bot_gunshot(seconds: float) -> Dictionary:
	_p.try_switch(1)
	for f in 15:
		await get_tree().physics_frame
	_p.aim_direction = Vector2(-1, -1).normalized()  # into empty space
	_p.try_attack()
	await get_tree().physics_frame
	var investigating := 0
	for z in _living():
		if z.state == Zombie.State.INVESTIGATE or z.state == Zombie.State.CHASE:
			investigating += 1
	var t := 0.0
	var first_arrival := -1.0
	var arrived := {}
	_p.try_switch(0)
	while t < seconds:
		if _p.is_dead():
			return _done("DIED", t)
		_fight()
		_p.move_override = Vector2.ZERO
		for z in _living():
			if z.global_position.distance_to(_p.global_position) < 40.0:
				arrived[z] = true
				if first_arrival < 0.0:
					first_arrival = t
		await get_tree().physics_frame
		t += DT
	return _done("SURVIVED", t, "heard the shot: %d of 6; first arrived %.1fs; arrived within %.0fs: %d" % [
		investigating, first_arrival, seconds, arrived.size()])


# ---------------- performance ----------------

func _performance_run() -> void:
	print("")
	print("PERFORMANCE  40 Walkers chasing the player in the test yard (headless Linux CPU, NOT your laptop)")
	var yard: Node2D = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	var actors := Node2D.new()
	actors.y_sort_enabled = true
	yard.add_child(actors)
	_p = load("res://scenes/player/player.tscn").instantiate()
	_p.use_mouse_aim = false
	_p.position = Vector2(30 * 16, 20 * 16)
	actors.add_child(_p)
	_p.health.setup(100000.0)  # survive the whole measurement
	for f in 20:
		await get_tree().physics_frame
	var t0: int = Time.get_ticks_usec()
	for f in 300:
		await get_tree().physics_frame
	_baseline_ms = (Time.get_ticks_usec() - t0) / 1000.0 / 300.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var count := 0
	while count < 40:
		var pos := Vector2(rng.randf_range(40, 920), rng.randf_range(40, 600))
		var cell: Vector2i = (yard.get_node("Walls") as TileMapLayer).local_to_map(pos)
		var free: bool = (yard.get_node("Walls") as TileMapLayer).get_cell_source_id(cell) == -1 \
			and (yard.get_node("Props") as TileMapLayer).get_cell_source_id(cell) == -1
		var map_ok: bool = free and pos.distance_to(_p.position) > 120.0
		if map_ok:
			var z: Zombie = load("res://scenes/zombies/walker.tscn").instantiate()
			z.position = pos
			z.wanders = false
			actors.add_child(z)
			count += 1
	for f in 20:
		await get_tree().physics_frame
	NoiseSystem.emit_noise(_p.global_position, 5000.0, null)  # everyone comes
	# Wall-clock time per frame (the game runs as fast as it can with --fixed-fps,
	# so this is the real CPU cost of one frame: physics + all zombie AI + player).
	var samples: Array[float] = []
	var last: int = Time.get_ticks_usec()
	for f in 600:
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec()
		samples.append((now - last) / 1000.0)
		last = now
	samples.sort()
	var avg := 0.0
	for v in samples:
		avg += v
	avg /= samples.size()
	print("frame time with 40 Walkers over 10 s of game time: average %.2f ms, 95th percentile %.2f ms, worst %.2f ms" % [
		avg, samples[int(samples.size() * 0.95)], samples[-1]])
	print("(budget at 60 FPS is 16.7 ms per frame; baseline without zombies: %.2f ms)" % _baseline_ms)
	var chasing := 0
	for z in get_tree().get_nodes_in_group(&"zombies"):
		if (z as Zombie).state in [Zombie.State.CHASE, Zombie.State.ATTACK, Zombie.State.INVESTIGATE, Zombie.State.SEARCH]:
			chasing += 1
	print("zombies active (chasing/investigating/searching): %d of 40" % chasing)
	yard.queue_free()
	await get_tree().physics_frame
