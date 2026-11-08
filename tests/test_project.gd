extends "res://tests/test_case.gd"
## Project settings, input map, scene integrity, game flow, dark zone setup.

const SCENE_DIRS: Array[String] = ["res://scenes"]


func test_renderer_and_resolution() -> void:
	check_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility",
		"Compatibility renderer")
	check_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 640, "viewport width")
	check_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 360, "viewport height")
	check_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "viewport", "pixel-perfect stretch")


func test_input_actions_exist_with_default_keys() -> void:
	var expected := {
		&"move_up": KEY_W, &"move_down": KEY_S, &"move_left": KEY_A, &"move_right": KEY_D,
		&"run": KEY_SHIFT, &"reload": KEY_R, &"interact": KEY_E, &"shove": KEY_SPACE,
		&"flashlight": KEY_F, &"pause": KEY_ESCAPE,
	}
	for action in expected:
		check(InputMap.has_action(action), "action %s exists" % action)
		var found := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and ev.physical_keycode == expected[action]:
				found = true
		check(found, "action %s bound to %s" % [action, OS.get_keycode_string(expected[action])])
	for action in [&"attack", &"aim", &"inventory", &"weapon_1", &"weapon_next"]:
		check(InputMap.has_action(action), "action %s exists" % action)


func _collect_scenes(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect_scenes(dir.path_join(d), out)


func _collect_scripts(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect_scripts(dir.path_join(d), out)


func test_every_script_compiles() -> void:
	var scripts: Array[String] = []
	_collect_scripts("res://scripts", scripts)
	_collect_scripts("res://tests", scripts)
	check(scripts.size() >= 10, "found scripts (%d)" % scripts.size())
	for path in scripts:
		var s: GDScript = load(path)
		check(s != null and s.can_instantiate(), "compiles: " + path)


func test_every_scene_loads_and_instantiates() -> void:
	var scenes: Array[String] = []
	for d in SCENE_DIRS:
		_collect_scenes(d, scenes)
	check(scenes.size() >= 7, "found game scenes (%d)" % scenes.size())
	for path in scenes:
		var ps: PackedScene = load(path)
		check(ps != null, "loads: " + path)
		if ps == null:
			continue
		var inst: Node = ps.instantiate()
		check(inst != null, "instantiates: " + path)
		if inst != null:
			inst.free()


func test_game_scene_starts_and_player_spawns_in_safehouse() -> void:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(5)
	var p: Player = game.get_node("World/Actors/Player")
	var spawn: Marker2D = game.get_node("World/Map/PlayerSpawn")
	check(p.global_position.distance_to(spawn.global_position) < 2.0, "player at spawn")
	check(p.health.current_health == 100.0 and p.stamina == 100.0, "full health and stamina")
	var hud: CanvasLayer = game.get_node("HUD")
	check_eq(hud.get_node("%HealthBar").value, 100.0, "HUD health bar bound")
	check(not game.get_node("GameOver").visible, "game-over hidden at start")
	game.queue_free()


func test_death_shows_game_over_screen() -> void:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(5)
	var p: Player = game.get_node("World/Actors/Player")
	p.health.take_damage(1000.0)
	check(p.is_dead(), "player dead")
	await physics_frames(75)  # screen appears after 1 s
	var go: CanvasLayer = game.get_node("GameOver")
	check(go.visible, "game-over screen visible")
	check(go.get_node("%RetryButton") is Button, "retry button present")
	game.queue_free()


func test_test_yard_dark_room_setup() -> void:
	var yard: Node = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	await physics_frames(2)
	var dz: DarkZone = yard.get_node("DarkRoom")
	var light: PointLight2D = dz.get_node("Light")
	check_eq(light.blend_mode, Light2D.BLEND_MODE_SUB, "darkness uses a Subtract light")
	check_eq(light.range_item_cull_mask, 2, "darkness only affects layer 2")
	check(not light.shadow_enabled, "darkness light casts no shadows")
	check(light.texture != null, "darkness mask generated")
	check((yard.get_node("Ground").light_mask & 2) != 0, "ground is darkened inside rooms")
	check((yard.get_node("Walls").light_mask & 2) == 0, "walls are NOT darkened")
	check(not (yard as Node2D).get_children().any(func(c: Node) -> bool: return c is CanvasModulate),
		"no CanvasModulate in the map")
	yard.queue_free()


func test_player_detects_entering_and_leaving_dark_room() -> void:
	var yard: Node = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	var p := spawn_player(yard, Vector2(300, 300))
	await physics_frames(5)
	check(not p.in_darkness, "outside: not in darkness")
	check(not p.adaptation_light.enabled, "no player glow outdoors")
	var dz: DarkZone = yard.get_node("DarkRoom")
	p.global_position = dz.global_position + dz.size * 0.5
	await physics_frames(5)
	check(p.in_darkness, "inside: in darkness")
	check(p.adaptation_light.enabled, "faint glow on inside")
	p.global_position = Vector2(300, 300)
	await physics_frames(5)
	check(not p.in_darkness, "left the room: not in darkness")
	yard.queue_free()
