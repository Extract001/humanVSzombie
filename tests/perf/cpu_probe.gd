extends Node2D
## Phase 11: CPU cost of game logic in the real map (headless, no drawing).
## 40 Walkers chasing the player in Ashford Lane; prints average physics and process time.
## Diagnostics only (not exported).

func _ready() -> void:
	SaveSystem.path = "user://tool_save.json"
	GameState.street_spawns_disabled = true  # fun pass: measure the placed/horde zombies only
	GameState.records_disabled = true
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	var p: Player = game.get_node("World/Actors/Player")
	p.use_mouse_aim = false
	p.health.setup(1.0e9)
	p.global_position = Vector2(78.5, 58.5) * 16.0
	var actors: Node = game.get_node("World/Actors")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var map: Node = game.get_node("World/Map")
	var walls: TileMapLayer = map.get_node("Walls")
	var props: TileMapLayer = map.get_node("Props")
	var target_count: int = int(OS.get_environment("WALKERS")) if OS.get_environment("WALKERS") != "" else 40
	if target_count == 0:
		for z in get_tree().get_nodes_in_group(&"zombies"): z.queue_free()
	var need: int = target_count - get_tree().get_nodes_in_group(&"zombies").size()
	var tries := 0
	while need > 0 and tries < 5000:
		tries += 1
		var pos: Vector2 = p.global_position + Vector2(rng.randf_range(-300, 300), rng.randf_range(-220, 220))
		var c: Vector2i = walls.local_to_map(pos)
		if walls.get_cell_source_id(c) != -1 or props.get_cell_source_id(c) != -1 or pos.distance_to(p.global_position) < 80:
			continue
		var z: Zombie = load("res://scenes/zombies/walker.tscn").instantiate()
		z.position = pos
		actors.add_child(z)
		need -= 1
	for i in 60:
		await get_tree().physics_frame
	NoiseSystem.emit_noise(p.global_position, 5000.0, null)
	for i in 60:
		await get_tree().physics_frame
	var phys := 0.0
	var proc := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	for i in 1200:
		await get_tree().physics_frame
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		n += 1
	var states := {}
	for z in get_tree().get_nodes_in_group(&"zombies"):
		states[z.state] = states.get(z.state, 0) + 1
	print("CPU walkers=%d  physics+AI %.3f ms/step  process %.3f ms/frame  wall %.3f ms/frame  states %s" % [
		get_tree().get_nodes_in_group(&"zombies").size(), phys / n, proc / n, (Time.get_ticks_usec() - t0) / 1000.0 / n, str(states)])
	get_tree().quit()
