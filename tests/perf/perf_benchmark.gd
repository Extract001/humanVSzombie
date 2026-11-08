extends Node2D
## Performance benchmark (diagnostics only, excluded from exported builds).
##
## Measures, on the machine it runs on:
##   - FPS and frame times with 1, 10, 20 and 40 chasing Walkers
##   - in the open test yard and inside the dark room
##   - with V-Sync ON (what players get) and OFF (the real capacity)
##   - CPU time split: physics + AI (_physics_process), render CPU, and render GPU time
##     where the driver reports it
##   - draw calls and drawn objects
##   - lighting cost: dark room with 40 Walkers, lights on vs. off
## Results go to logs/perf_benchmark.txt (and the console).
##
## Run outside the editor (closest to a real build): tools\validate.bat perf
## Run inside the editor: open this scene and press F6 (the editor's own overhead is then included).

const COUNTS: Array[int] = [1, 10, 20, 40]
const WARMUP_S: float = 1.5
const MEASURE_S: float = 4.0
const YARD_SPOT := Vector2(30 * 16, 20 * 16)     # middle of the road, open area
const DARK_SPOT := Vector2(47 * 16, 32 * 16)     # inside the dark room

var _lines: PackedStringArray = []
## "-- --quick" (Phase 11): only the V-Sync OFF rows, for comparing graphics drivers quickly.
var _quick: bool = false
var _vp: RID


func _ready() -> void:
	SaveSystem.path = "user://tool_save.json"  # never touch the player's real save
	_quick = OS.get_cmdline_user_args().has("--quick")
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_out("LAST SIGNAL performance benchmark  %s" % Time.get_datetime_string_from_system())
	_out("Run mode: %s" % _run_mode())
	_out("Godot %s | renderer %s | driver %s" % [Engine.get_version_info().string,
		ProjectSettings.get_setting("rendering/renderer/rendering_method"), RenderingServer.get_current_rendering_driver_name()])
	_out("GPU: %s (%s) | OS: %s | CPU: %s, %d threads" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), OS.get_name(), OS.get_processor_name(), OS.get_processor_count()])
	_out("Screen refresh rate: %.0f Hz | window %s | viewport 640x360 scaled" % [
		DisplayServer.screen_get_refresh_rate(), str(DisplayServer.window_get_size())])
	_out("Engine.max_fps = %d (0 = unlimited) | physics ticks %d/s | V-Sync setting %d (1 = enabled)" % [
		Engine.max_fps, Engine.physics_ticks_per_second, ProjectSettings.get_setting("display/window/vsync/vsync_mode")])
	_out("")
	_out("%-10s %-5s %-6s | %6s %7s %7s | %7s %7s %7s | %5s %5s" % ["place", "vsync", "walkrs",
		"FPS", "avg ms", "worst", "phys+AI", "rendCPU", "rendGPU", "draws", "objs"])
	_out("-".repeat(100))
	if _quick:
		_out("QUICK run: V-Sync OFF rows only")
	for vsync in ([false] if _quick else [false, true]):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		for place in ["yard", "dark room"]:
			for n in COUNTS:
				await _measure(place, n, vsync, true)
	_out("")
	_out("Lighting cost (dark room, 40 Walkers, V-Sync OFF):")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _measure("dark room", 40, false, true)
	await _measure("dark room", 40, false, false)
	_out("")
	_out("Real game scene (Ashford Lane, all its Walkers awake and chasing), V-Sync OFF / ON:")
	for vs in ([false] if _quick else [false, true]):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vs else DisplayServer.VSYNC_DISABLED)
		for spot in [["street", Vector2(78.5, 58.5)], ["pharmacy", Vector2(18.5, 50.5)], ["grocery", Vector2(62.5, 44.5)]]:
			await _measure_game(spot[0], spot[1] * 16.0, vs)
	_out("")
	_out("Flashlight cost (Phase 6: cone light with wall/shelf shadows), V-Sync OFF:")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_out("(+L = flashlight on, -L = off)")
	for spot in [["warehouse", Vector2(21.5, 8.5)], ["street", Vector2(78.5, 58.5)]]:
		for fl in [false, true]:
			await _measure_game(spot[0].substr(0, 7) + (" +L" if fl else " -L"), spot[1] * 16.0, false, fl)
	# Phase 11: the "Flashlight shadows" setting switched off (beam without wall shadows).
	var keep: bool = Settings.flashlight_shadows
	Settings.flashlight_shadows = false
	for spot in [["warehouse", Vector2(21.5, 8.5)], ["street", Vector2(78.5, 58.5)]]:
		await _measure_game(spot[0].substr(0, 5) + "+L-sh", spot[1] * 16.0, false, true)
	Settings.flashlight_shadows = keep
	# Slice 1: night siege with the horde at the 40-Walker cap, flashlight on.
	for spot in [["safehouse", Vector2(78.5, 72.5)], ["street", Vector2(78.5, 58.5)]]:
		await _measure_game(spot[0].substr(0, 5) + " night", spot[1] * 16.0, false, true, true)
	_out("(night = Slice 1 siege: dark tint, safehouse lamp, horde at the 40-Walker cap, flashlight on)")
	_out("(+L-sh = flashlight on, \"Flashlight shadows\" setting OFF)")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	_out("")
	_out("Columns: FPS = frames per second; avg/worst = real time per frame (ms);")
	_out("phys+AI = physics + zombie/player logic per physics step; rendCPU / rendGPU = time to draw the frame on CPU / GPU")
	_out("(0.00 GPU = not reported by this driver). Budget for 60 FPS = 16.7 ms per frame.")
	_save()
	AudioManager.stop_all()
	await get_tree().process_frame
	print("PERF BENCHMARK COMPLETED")
	get_tree().quit()


func _measure(place: String, walkers: int, vsync: bool, lights: bool) -> void:
	var yard: Node2D = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	var actors := Node2D.new()
	actors.y_sort_enabled = true
	yard.add_child(actors)
	var spot: Vector2 = DARK_SPOT if place == "dark room" else YARD_SPOT
	var p: Player = load("res://scenes/player/player.tscn").instantiate()
	p.use_mouse_aim = false
	p.position = spot
	actors.add_child(p)
	p.health.setup(1.0e9)  # survives the whole measurement
	p.camera.make_current()
	p.camera.reset_smoothing()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + walkers
	var walls: TileMapLayer = yard.get_node("Walls")
	var props: TileMapLayer = yard.get_node("Props")
	var placed := 0
	var tries := 0
	while placed < walkers and tries < 5000:
		tries += 1
		var pos: Vector2 = spot + Vector2(rng.randf_range(-260, 260), rng.randf_range(-200, 200))
		var cell: Vector2i = walls.local_to_map(pos)
		if walls.get_cell_source_id(cell) != -1 or props.get_cell_source_id(cell) != -1:
			continue
		if pos.distance_to(spot) < 60.0 or not Rect2(24, 24, 912, 592).has_point(pos):
			continue
		var z: Zombie = load("res://scenes/zombies/walker.tscn").instantiate()
		z.position = pos
		z.wanders = false
		actors.add_child(z)
		placed += 1
	if not lights:
		for l in yard.find_children("*", "PointLight2D", true, false):
			(l as PointLight2D).enabled = false
		p.adaptation_light.visible = false
	await _wait(0.3)
	NoiseSystem.emit_noise(spot, 5000.0, null)  # everyone comes for the player: worst case
	await _wait(WARMUP_S)

	var frames := 0
	var worst := 0.0
	var phys_ms := 0.0
	var rcpu := 0.0
	var rgpu := 0.0
	var draws := 0.0
	var objs := 0.0
	var start: int = Time.get_ticks_usec()
	var last: int = start
	while Time.get_ticks_usec() - start < int(MEASURE_S * 1000000.0):
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		rgpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var elapsed: float = (Time.get_ticks_usec() - start) / 1000000.0
	var f: float = maxf(1.0, frames)
	_out("%-10s %-5s %6d | %6.1f %7.2f %7.2f | %7.2f %7.2f %7.2f | %5.0f %5.0f%s" % [place,
		"on" if vsync else "off", walkers, frames / elapsed, elapsed * 1000.0 / f, worst,
		phys_ms / f, rcpu / f, rgpu / f, draws / f, objs / f, "" if lights else "  (lights OFF)"])
	yard.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _measure_game(label: String, pos: Vector2, vsync: bool, flashlight: bool = false, night: bool = false) -> void:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	var p: Player = game.get_node("World/Actors/Player")
	if night:
		# Slice 1: a full-size night (horde up to the 40-Walker cap, all spawned, heading for the safehouse).
		GameState.heat = 40.0
		game.day_cycle.start_night()
		GameState.phase_time = SiegeData.new().night_length * 0.7
	p.use_mouse_aim = false
	p.global_position = pos
	p.health.setup(1.0e9)
	p.camera.make_current()
	p.camera.reset_smoothing()
	p.aim_direction = Vector2.DOWN
	if flashlight:
		p.set_flashlight(true)
	await _wait(0.5)
	NoiseSystem.emit_noise(pos, 5000.0, null)
	await _wait(WARMUP_S)
	var frames := 0
	var worst := 0.0
	var phys := 0.0
	var rcpu := 0.0
	var rgpu := 0.0
	var draws := 0.0
	var start: int = Time.get_ticks_usec()
	var last: int = start
	while Time.get_ticks_usec() - start < int(MEASURE_S * 1000000.0):
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		rgpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var elapsed: float = (Time.get_ticks_usec() - start) / 1000000.0
	var f: float = maxf(1.0, frames)
	_out("%-10s %-5s %6d | %6.1f %7.2f %7.2f | %7.2f %7.2f %7.2f | %5.0f" % [label, "on" if vsync else "off",
		get_tree().get_nodes_in_group(&"zombies").size(), frames / elapsed, elapsed * 1000.0 / f, worst,
		phys / f, rcpu / f, rgpu / f, draws / f])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	var t: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - t < int(seconds * 1000000.0):
		await get_tree().process_frame


func _run_mode() -> String:
	var embedded := false
	if Engine.has_method(&"is_embedded_in_editor"):
		embedded = Engine.call(&"is_embedded_in_editor")
	if OS.has_feature("template"):
		return "EXPORTED build"
	if embedded:
		return "run from the EDITOR, embedded in the editor's Game tab"
	if EngineDebugger.is_active():
		return "run from the EDITOR (separate window, debugger connected)"
	return "standalone (Godot executable with --path, no editor, no debugger)"


func _out(line: String) -> void:
	print(line)
	_lines.append(line)


func _save() -> void:
	var dir: String = ProjectSettings.globalize_path("res://logs")
	if OS.has_feature("template"):
		dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var fname: String = "perf_benchmark_%s%s.txt" % [RenderingServer.get_current_rendering_driver_name(), "_quick" if _quick else ""]
	var f := FileAccess.open(dir.path_join(fname), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		print("Saved: ", dir.path_join(fname))
