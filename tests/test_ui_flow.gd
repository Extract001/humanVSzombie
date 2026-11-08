extends "res://tests/test_case.gd"
## Phase 8: main menu, pause (really stops the game), settings + key rebinding saved to disk, theme/font.

const TEST_CFG := "user://test_settings.cfg"


func _game() -> Node:
	GameState.new_game(1)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _clear_saves() -> void:
	for ext in ["", ".tmp", ".bak", ".broken", ".bak.broken"]:
		if FileAccess.file_exists(SaveSystem.path + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.path + ext))


func test_main_menu_buttons() -> void:
	_clear_saves()
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await physics_frames(2)
	check_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/ui/main_menu.tscn", "the game starts at the main menu")
	check(ResourceLoader.exists(menu.GAME_SCENE), "New game leads to an existing scene")
	check(menu.new_button.has_focus(), "New game has keyboard focus (Enter starts)")
	check(menu.continue_button.disabled and menu.continue_button.tooltip_text.contains("No saved game"), "Continue disabled without a save")
	check_eq(menu.exit_button.visible, not OS.has_feature("web"), "Exit shown on desktop, hidden in the browser")
	menu.settings_button.pressed.emit()
	check(menu.settings_menu.visible, "Settings opens the settings screen")
	menu.settings_menu.close()
	menu.credits_button.pressed.emit()
	var credits: Control = menu.get_node("Credits")
	check(credits.visible, "Credits opens")
	var text: String = credits.get_node("Box/Text").text
	check(text.contains("Godot Engine") and text.contains("Permission is hereby granted"), "credits carry the Godot licence notice")
	menu.queue_free()


func test_pause_stops_zombies_timers_and_battery() -> void:
	var game := _game()
	await physics_frames(3)
	var p: Player = game.get_node("World/Actors/Player")
	p.health.setup(100.0, 40.0)
	p.inventory.add_item(&"bandage", 1)
	p.use_item(&"bandage")  # heals over time
	p.set_flashlight(true)
	var z := spawn_walker(game.get_node("World/Actors"), p.global_position + Vector2(60, 0), Vector2.LEFT)
	await physics_frames(20)
	check(z.state == Zombie.State.CHASE, "zombie chasing before the pause")
	game.pause_menu.pause()
	check(get_tree().paused and game.pause_menu.visible, "paused, menu shown")
	var zpos: Vector2 = z.global_position
	var hp: float = p.health.current_health
	var charge: float = p.flashlight_charge()
	var elapsed: float = game.elapsed
	await physics_frames(90)
	check(z.global_position.distance_to(zpos) < 0.01, "zombie doesn't move while paused")
	check_eq(p.health.current_health, hp, "no bites and no healing while paused")
	check_eq(p.flashlight_charge(), charge, "flashlight battery doesn't drain while paused")
	check_eq(game.elapsed, elapsed, "survival timer stopped")
	game.pause_menu.resume()
	check(not get_tree().paused and not game.pause_menu.visible, "resumed")
	await physics_frames(10)
	check(z.global_position.distance_to(zpos) > 1.0, "zombie moves again after resuming")
	game.queue_free()


func test_escape_pauses_only_in_normal_play() -> void:
	var game := _game()
	await physics_frames(3)
	var p: Player = game.get_node("World/Actors/Player")
	var esc := InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	game.pause_menu._unhandled_input(esc)
	check(game.pause_menu.visible and get_tree().paused, "Esc pauses")
	game.pause_menu._unhandled_input(esc)
	check(not game.pause_menu.visible and not get_tree().paused, "Esc again resumes")
	game.inventory_panel.open()
	check(not game.can_pause(), "no pause on top of an open panel (Esc closes the panel instead)")
	game.inventory_panel.close()
	p.health.take_damage(1000.0)
	await physics_frames(2)
	check(not game.can_pause(), "no pause on the death screen")
	game.queue_free()


func test_rebinding_is_saved_and_survives_a_restart() -> void:
	var old_path: String = Settings.config_path
	Settings.config_path = TEST_CFG
	var t := InputEventKey.new()
	t.physical_keycode = KEY_T
	Settings.rebind(&"reload", t)
	check_eq(Settings.event_text(Settings.primary_event(&"reload")), "T", "Reload is now T")
	# Rebinding to a key another action uses swaps them, so nothing is left without a key.
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	Settings.rebind(&"reload", e)
	check_eq(Settings.event_text(Settings.primary_event(&"reload")), "E", "Reload is now E")
	check_eq(Settings.event_text(Settings.primary_event(&"interact")), "T", "Use/interact got Reload's old key (T)")
	Settings.master_volume = 0.4
	Settings.save_settings()
	# "Restart": back to the project defaults in memory, then load the saved file.
	Settings.reset_bindings(false)
	Settings.master_volume = 1.0
	check_eq(Settings.event_text(Settings.primary_event(&"reload")), "R", "defaults in memory")
	Settings.load_settings()
	check_eq(Settings.event_text(Settings.primary_event(&"reload")), "E", "after restart: Reload is E")
	check_eq(Settings.event_text(Settings.primary_event(&"interact")), "T", "after restart: Use/interact is T")
	check_near(Settings.master_volume, 0.4, 0.001, "after restart: volume kept")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_T
	ev.pressed = true
	check(InputMap.event_is_action(ev, &"interact"), "pressing T now triggers Use/interact")
	check(InputMap.action_get_events(&"inventory").size() == 2, "secondary keys kept (Tab and I for the inventory)")
	# Clean up: defaults back, test file removed, real settings path restored.
	Settings.reset_bindings(false)
	Settings.master_volume = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Settings.config_path = old_path
	check_eq(Settings.event_text(Settings.primary_event(&"reload")), "R", "defaults restored")


func test_settings_screen_captures_keys_and_mouse() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_G
	k.pressed = true
	k.shift_pressed = true
	var got: InputEvent = preload("res://scripts/ui/settings_menu.gd").capture_event(k)
	check(got is InputEventKey and (got as InputEventKey).physical_keycode == KEY_G, "key captured")
	check(not (got as InputEventKey).shift_pressed and got.device == -1, "no modifiers, any device")
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_MIDDLE
	m.pressed = true
	got = preload("res://scripts/ui/settings_menu.gd").capture_event(m)
	check(got is InputEventMouseButton and Settings.event_text(got) == "Middle mouse", "mouse button captured")
	var release := InputEventKey.new()
	release.physical_keycode = KEY_G
	check(preload("res://scripts/ui/settings_menu.gd").capture_event(release) == null, "key releases ignored")


func test_theme_and_pixel_font_cover_the_ui_text() -> void:
	var theme: Theme = load(ProjectSettings.get_setting("gui/theme/custom"))
	check(theme != null, "project theme set")
	var font: Font = theme.default_font
	check(font != null and font.resource_path.ends_with("last_signal_pixel.png"), "theme uses the original pixel font")
	check_eq(theme.default_font_size, 10, "pixel font at 1:1 size")
	var needed := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:;!?'\"()[]/-+%#&*_<>=@·×•—…▶✓"
	var missing := ""
	for ch in needed:
		if not font.has_char(ch.unicode_at(0)):
			missing += ch
	check_eq(missing, "", "every character the UI uses has a glyph")
	check(theme.has_stylebox(&"normal", &"Button") and theme.has_stylebox(&"panel", &"PanelContainer"), "buttons and panels are styled")
	check(theme.has_icon(&"checked", &"CheckBox"), "custom check boxes (no default Godot icons)")


func test_death_screen_stats_and_fps_setting() -> void:
	var game := _game()
	await physics_frames(3)
	var p: Player = game.get_node("World/Actors/Player")
	p.inventory.add_item(&"food_can", 3)
	p.health.take_damage(1000.0)
	await physics_frames(75)
	var go: CanvasLayer = game.get_node("GameOver")
	check(go.visible, "death screen shown")
	check(go.get_node("%BackpackLabel").text.contains("3 kinds of item (21 in total)"), "items left in the backpack shown")
	check(go.get_node("%MainMenuButton") is Button, "Main menu button present")
	Settings.show_fps = false
	await physics_frames(2)
	check(not game.get_node("HUD").fps_label.visible, "FPS counter follows the setting")
	Settings.show_fps = true
	game.queue_free()


## Phase 11: "Flashlight shadows" graphics setting: applied to the player at once, saved, and visual only.
func test_flashlight_shadows_setting() -> void:
	var old_path: String = Settings.config_path
	Settings.config_path = TEST_CFG
	var game := _game()
	await physics_frames(3)
	var p: Player = game.get_node("World/Actors/Player")
	check(p.flashlight.shadow_enabled, "shadows on by default")
	Settings.flashlight_shadows = false
	Settings.apply()
	check(not p.flashlight.shadow_enabled, "switching the setting off removes the beam's shadows at once")
	Settings.save_settings()
	Settings.flashlight_shadows = true
	Settings.load_settings()
	check(not Settings.flashlight_shadows, "setting is saved and loaded")
	Settings.flashlight_shadows = true
	Settings.apply()
	check(p.flashlight.shadow_enabled, "back on")
	game.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Settings.config_path = old_path


## Responsive screen: the picture fills common laptop/monitor sizes with whole-number zoom.
func test_screen_fit_fills_common_sizes() -> void:
	check_eq(Settings.view_for(Vector2i(1920, 1080)), Vector2i(640, 360), "1920×1080: 3× zoom, exact")
	check_eq(Settings.view_for(Vector2i(1366, 768)), Vector2i(683, 384), "1366×768: 2× zoom, a bit more world, no bars")
	check_eq(Settings.view_for(Vector2i(1536, 864)), Vector2i(768, 432), "1536×864 (1080p at 125%): 2×")
	check_eq(Settings.view_for(Vector2i(2560, 1440)), Vector2i(640, 360), "1440p: 4×")
	check_eq(Settings.view_for(Vector2i(1920, 1200)), Vector2i(640, 400), "16:10: 3×, taller view")
	check_eq(Settings.view_for(Vector2i(2560, 1080)), Vector2i(854, 360), "ultrawide: 3×, wider view")
	check_eq(Settings.view_for(Vector2i(1024, 768)), Settings.BASE_SIZE, "odd sizes fall back to smooth scaling")
	var v: Vector2i = Settings.view_for(Vector2i(1366, 768))
	check(v.x * 2 >= 1366 and v.y * 2 >= 768, "the picture covers the whole window")
	check_eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand", "no black bars for other shapes")
	check(Settings.fullscreen or OS.has_feature("web"), "desktop starts in fullscreen")
