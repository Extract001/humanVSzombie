extends Node2D
## Phase 11 profiling helper: what costs render time in the real game scene?
## Loads Ashford Lane, puts the player at a spot, then measures render CPU/GPU
## with one part of the scene switched off at a time. Diagnostics only (not exported).

const MEASURE_S: float = 3.0
var _vp: RID

func _ready() -> void:
	SaveSystem.path = "user://tool_save.json"
	GameState.street_spawns_disabled = true  # fun pass: measure the placed/horde zombies only
	GameState.records_disabled = true
	GameState.intro_disabled = true
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for spot in [["warehouse", Vector2(21.5, 8.5)], ["street", Vector2(78.5, 58.5)]]:
		for variant in ["all", "no zombies", "no HUD+UI", "no roofs", "no dark zones", "no occluders", "no ground", "no walls+props", "no fx", "flashlight on"]:
			await _measure(spot[0], spot[1] * 16.0, variant)
	print("BREAKDOWN COMPLETED")
	get_tree().quit()

func _measure(label: String, pos: Vector2, variant: String) -> void:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	var p: Player = game.get_node("World/Actors/Player")
	p.use_mouse_aim = false
	p.global_position = pos
	p.health.setup(1.0e9)
	p.camera.make_current()
	p.camera.reset_smoothing()
	await _wait(0.6)
	var map: Node = game.get_node("World/Map")
	match variant:
		"no zombies":
			for z in get_tree().get_nodes_in_group(&"zombies"): z.visible = false
		"no HUD+UI":
			for c in game.get_children():
				if c is CanvasLayer: c.visible = false
		"no roofs":
			for r in map.get_children():
				if r.name.ends_with("Roof"): r.visible = false
		"no dark zones":
			for d in map.get_children():
				if d is DarkZone: d.visible = false
		"no occluders":
			for t in map.get_children():
				if t is TileMapLayer: t.occlusion_enabled = false
		"no ground":
			map.get_node("Ground").visible = false
		"no walls+props":
			map.get_node("Walls").visible = false
			map.get_node("Props").visible = false
		"no fx":
			for n in game.find_children("*", "CPUParticles2D", true, false): n.visible = false
		"flashlight on":
			p.set_flashlight(true)
	await _wait(0.6)
	var frames := 0
	var rcpu := 0.0
	var rgpu := 0.0
	var draws := 0.0
	var start: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < int(MEASURE_S * 1000000.0):
		await get_tree().process_frame
		frames += 1
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		rgpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var f: float = maxf(1.0, frames)
	var el: float = (Time.get_ticks_usec() - start) / 1000000.0
	print("BREAK %-10s %-16s fps %6.1f  rendCPU %6.2f  rendGPU %6.2f  draws %5.0f" % [label, variant, frames / el, rcpu / f, rgpu / f, draws / f])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _wait(s: float) -> void:
	var t: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - t < int(s * 1000000.0):
		await get_tree().process_frame
