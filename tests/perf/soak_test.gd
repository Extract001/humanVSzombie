extends Node
## Phase 11 memory soak: repeats a whole session many times and checks that nothing piles up.
## One cycle = main menu → new game → Walkers chase, pistol shots, blood, a death, respawn,
## an autosave, a load → back to the menu. Records object, node, orphan-node and memory counts
## after every cycle. Leak = counts that keep rising cycle after cycle.
## Run headless: godot --headless --fixed-fps 60 res://tests/perf/soak_test.tscn  (diagnostics only)

const CYCLES: int = 12

func _ready() -> void:
	SaveSystem.path = "user://tool_save.json"
	GameState.street_spawns_disabled = true  # fun pass: measure the placed/horde zombies only
	GameState.records_disabled = true
	GameState.intro_disabled = true
	var rows: Array = []
	for c in CYCLES:
		await _cycle()
		for i in 10:
			await get_tree().process_frame
		var row := [Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]
		rows.append(row)
		print("SOAK cycle %2d  objects %6d  nodes %5d  orphans %3d  resources %5d  memory %.1f MB" % [c + 1, row[0], row[1], row[2], row[3], row[4]])
	# Compare the end with cycle 3 (after first-time loading/caching has settled).
	var a: Array = rows[2]
	var b: Array = rows[CYCLES - 1]
	var grow_objects: float = (b[0] - a[0]) / float(CYCLES - 3)
	var grow_nodes: float = (b[1] - a[1]) / float(CYCLES - 3)
	var grow_mem: float = (b[4] - a[4]) / float(CYCLES - 3)
	print("SOAK growth per cycle (cycles 3-%d): objects %+.1f  nodes %+.1f  orphans %d  memory %+.2f MB" % [CYCLES, grow_objects, grow_nodes, b[2], grow_mem])
	var long_ok: bool = await _long_session()
	var ok: bool = absf(grow_nodes) < 1.0 and grow_objects < 20.0 and b[2] == 0 and grow_mem < 0.5 and long_ok
	print("SOAK TEST PASSED" if ok else "SOAK TEST FAILED")
	for f in [SaveSystem.path, SaveSystem.path + ".bak", SaveSystem.path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	get_tree().quit(0 if ok else 1)


func _cycle() -> void:
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(20)
	menu.queue_free()
	await _frames(2)
	SaveSystem.fresh_start = true
	GameState.new_game(randi())
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await _frames(30)
	var p: Player = game.get_node("World/Actors/Player")
	p.use_mouse_aim = false
	NoiseSystem.emit_noise(p.global_position, 5000.0, null)
	p.try_switch(1)
	await _frames(40)
	for i in 4:
		p.aim_direction = Vector2.RIGHT.rotated(i * 1.5)
		p.try_attack()
		await _frames(25)
	Fx.burst(game.get_node("World/Actors"), p.global_position, Fx.BLOOD, 8, 55.0, Vector2.RIGHT)
	p.set_flashlight(true)
	await _frames(60)
	p.health.take_damage(10000.0)  # death: backpack drop + death save
	await _frames(150)
	if not p.is_dead() or GameState.piles.is_empty():
		push_error("soak: the death did not happen as planned")
	game.respawn_player()
	await _frames(30)
	game.save_now("soak")
	game.queue_free()
	await _frames(2)
	# Continue from the save.
	SaveSystem.load_game()
	var game2: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game2)
	await _frames(60)
	get_tree().paused = false
	game2.queue_free()
	await _frames(5)


## One long session: 5 simulated minutes of shooting, shoving, running and flashlight use with
## Walkers around. Node count must come back down (tracers, sparks, noise rings are freed).
func _long_session() -> bool:
	SaveSystem.fresh_start = true
	GameState.new_game(7)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await _frames(30)
	var p: Player = game.get_node("World/Actors/Player")
	p.use_mouse_aim = false
	p.health.setup(1.0e9)
	p.inventory.add_item(&"ammo_pistol", 500)
	game.day_cycle.set_physics_process(false)   # stay in daylight: this checks effects, not the horde
	p.try_switch(1)
	var samples: Array = []
	for minute_part in 10:  # 10 x 30 s
		for k in 30:
			p.aim_direction = Vector2.RIGHT.rotated(randf() * TAU)
			if not p.try_attack():
				p.try_reload()
			if k % 7 == 0:
				p.try_shove()
			if k % 10 == 0:
				p.toggle_flashlight()
			await _frames(60)
		samples.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		print("SOAK long session %3d s  nodes %d  objects %d  zombies alive %d" % [(minute_part + 1) * 30,
			samples[-1], Performance.get_monitor(Performance.OBJECT_COUNT), get_tree().get_nodes_in_group(&"zombies").size()])
	game.queue_free()
	await _frames(5)
	# After the first 30 s the node count should stay level (±40 for effects alive at the sample moment).
	var lo: float = samples.slice(1).min()
	var hi: float = samples.slice(1).max()
	print("SOAK long session node range after 30 s: %d..%d" % [lo, hi])
	return hi - lo <= 40


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
