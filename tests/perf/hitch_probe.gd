extends Node2D
## Phase 11: finds first-use stutters ("hitches"): the first time a light, effect or
## panel appears, the graphics driver may compile a shader and the frame takes long.
## Each action runs twice; a big first/second difference = one-time stutter.
## Diagnostics only (not exported).

var game: Node
var p: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveSystem.path = "user://tool_save.json"
	GameState.street_spawns_disabled = true  # fun pass: measure the placed/horde zombies only
	GameState.records_disabled = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	p = game.get_node("World/Actors/Player")
	p.use_mouse_aim = false
	p.health.setup(1.0e9)
	p.global_position = Vector2(21.5, 8.5) * 16.0  # warehouse (dark)
	p.camera.make_current()
	p.camera.reset_smoothing()
	await _frames(90)
	for round_i in 2:
		for action in ["flashlight on", "flashlight off", "pistol shot", "blood burst", "inventory panel", "close panel", "pause menu", "resume"]:
			await _probe(action)
		print("HITCH ---- round %d done" % (round_i + 1))
	print("HITCH PROBE COMPLETED")
	get_tree().quit()


func _probe(action: String) -> void:
	if action == "pistol shot":
		p.try_switch(1)
		await _frames(40)
		p.aim_direction = Vector2.RIGHT
	await _frames(20)
	var t0: int = Time.get_ticks_usec()
	match action:
		"flashlight on": p.set_flashlight(true)
		"flashlight off": p.set_flashlight(false)
		"pistol shot": p.try_attack()
		"blood burst": Fx.burst(game.get_node("World/Actors"), p.global_position + Vector2(20, 0), Fx.BLOOD, 8, 55.0, Vector2.RIGHT)
		"inventory panel": game.get_node("InventoryPanel").open()
		"close panel": game.get_node("InventoryPanel").close()
		"pause menu": game.get_node("PauseMenu").pause()
		"resume": game.get_node("PauseMenu").resume()
	var last: int = Time.get_ticks_usec()
	var call_ms: float = (last - t0) / 1000.0
	var worst := 0.0
	var total := 0.0
	for i in 12:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		total += (now - last) / 1000.0
		last = now
	print("HITCH %-16s call %6.2f ms | worst frame %7.2f ms | average %6.2f ms" % [action, call_ms, worst, total / 12.0])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
