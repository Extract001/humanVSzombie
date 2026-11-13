extends "res://tests/test_case.gd"
## Batch 2 — characters, daily challenge, survivors with jobs, playtest log, banner queue.

var _saved_settings: Dictionary = {}


func _game(seed_value: int = 1) -> Node:
	GameState.new_game(seed_value)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	return game


func _player(game: Node) -> Player:
	return game.get_node("World/Actors/Player")


func _keep_settings() -> void:
	_saved_settings = {"best_score": Settings.best_score, "best_nights": Settings.best_nights,
		"kills": Settings.lifetime_kills, "rescued": Settings.lifetime_rescued}


func _restore_settings() -> void:
	Settings.best_score = _saved_settings.best_score
	Settings.best_nights = _saved_settings.best_nights
	Settings.lifetime_kills = _saved_settings.kills
	Settings.lifetime_rescued = _saved_settings.rescued


func test_characters_unlock_from_lifetime_records() -> void:
	_keep_settings()
	Settings.best_score = 0
	Settings.best_nights = 0
	Settings.lifetime_kills = 0
	Settings.lifetime_rescued = 0
	check_eq(Characters.unlocked_ids(), [&"rook"] as Array[StringName], "only Rook at first")
	Settings.best_nights = 3
	check(Characters.is_unlocked(&"mara"), "3 nights unlock Mara")
	Settings.lifetime_kills = 150
	check(Characters.is_unlocked(&"dex"), "150 kills unlock Dex")
	Settings.best_score = 2500
	check(Characters.is_unlocked(&"kit"), "2500 points unlock Kit")
	check(not Characters.is_unlocked(&"sol"), "Sol still locked")
	Settings.lifetime_rescued = 3
	check(Characters.is_unlocked(&"sol"), "3 rescues unlock Sol")
	check(Characters.progress_text(&"sol").contains("3 so far"), "progress shown")
	_restore_settings()


func test_characters_change_the_numbers() -> void:
	var base: PlayerStats = load("res://data/player/player_stats.tres")
	var dex: PlayerStats = Characters.apply(&"dex", base)
	check_eq(dex.max_health, base.max_health + 30.0, "Dex +30 health")
	check(dex.run_speed < base.run_speed, "Dex a bit slower")
	var kit: PlayerStats = Characters.apply(&"kit", base)
	check_eq(kit.max_health, base.max_health - 20.0, "Kit 80 health")
	check(kit.run_speed > base.run_speed and kit.run_noise_radius < base.run_noise_radius, "Kit faster and quieter")
	check_eq(Characters.apply(&"mara", base).respawn_health, base.max_health, "Mara wakes up at full health")
	check_eq(Characters.plank_health_mult(&"sol"), 1.3, "Sol's planks")
	# Through the player: the character is applied under the perks.
	GameState.new_game(1)
	GameState.character = &"dex"
	var s: PlayerStats = Perks.apply_to_stats(base)
	check_eq(s.max_health, base.max_health + 30.0, "player stats include the character")
	GameState.new_game(1)
	check_eq(GameState.character, &"rook", "tests always get the default character")


func test_starting_gear_and_save_round_trip() -> void:
	var game := _game()
	await physics_frames(3)
	GameState.character = &"mara"
	game._give_start_gear()
	var p := _player(game)
	check_eq(p.inventory.count(&"medkit"), 1, "Mara starts with a medkit")
	GameState.survivors[&"tomas"] = "home"
	GameState.mode = &"daily"
	GameState.daily_date = "2026-11-13"
	GameState.modifier = &"swarm"
	var d: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.new_game(5)
	GameState.from_dict(d)
	check_eq(GameState.character, &"mara", "character saved")
	check_eq(GameState.survivors.get(&"tomas", ""), "home", "survivors saved")
	check_eq(GameState.mode, &"daily", "mode saved")
	check_eq(GameState.modifier, &"swarm", "daily twist saved")
	game.queue_free()
	GameState.new_game(1)


func test_daily_challenge_is_the_same_for_everyone_today() -> void:
	var old_path: String = SaveSystem.path
	check_eq(DailyChallenge.seed_for("2026-11-13"), DailyChallenge.seed_for("2026-11-13"), "same seed for the same date")
	check(DailyChallenge.seed_for("2026-11-13") != DailyChallenge.seed_for("2026-11-14"), "a new town tomorrow")
	var seen: Dictionary = {}
	for day in 28:
		seen[DailyChallenge.modifier_for("2026-11-%02d" % (day + 1))] = true
	check(seen.size() >= 4, "the twist changes from day to day (%d different in 4 weeks)" % seen.size())
	DailyChallenge.begin("2026-11-13")
	check_eq(GameState.mode, &"daily", "daily mode")
	check_eq(GameState.world_seed, DailyChallenge.seed_for("2026-11-13"), "today's town")
	check_eq(SaveSystem.path, DailyChallenge.SAVE_PATH, "its own save file (the main game is never touched)")
	SaveSystem.path = old_path
	SaveSystem.fresh_start = false
	# Twists
	GameState.modifier = &"glass"
	var base: PlayerStats = load("res://data/player/player_stats.tres")
	check_eq(Perks.apply_to_stats(base).max_health, 60.0, "Glass Bones: 60 health")
	var before: int = GameState.score
	GameState.add_score(100)
	check_eq(GameState.score - before, 150, "Glass Bones: points x1.5")
	GameState.modifier = &"swarm"
	check_eq(DailyChallenge.horde_mult(), 1.5, "Swarm: bigger hordes")
	GameState.modifier = &"short_days"
	check_near(DailyChallenge.day_length_mult(), 0.6, 0.001, "Short Days")
	GameState.new_game(1)
	check_eq(DailyChallenge.active(), DailyChallenge.NONE, "no twist in a normal game")


func test_daily_death_ends_the_run() -> void:
	var old_path: String = SaveSystem.path
	var game := _game()
	await physics_frames(3)
	GameState.mode = &"daily"
	GameState.daily_date = "2026-11-13"
	GameState.modifier = &"swarm"
	SaveSystem.path = old_path
	var p := _player(game)
	p.health.take_damage(9999.0, null)
	await get_tree().create_timer(1.3).timeout
	var go: CanvasLayer = game.get_node("GameOver")
	check(go.visible, "game over shown")
	check(not go.respawn_button.visible, "one life: no respawn")
	check_eq(go.retry_button.text, "Try again", "try again instead")
	check(go._title.text == "DAILY RUN OVER", "says so")
	game.queue_free()
	SaveSystem.path = old_path
	GameState.new_game(1)


func test_survivor_is_announced_followed_and_rescued() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var sv: Survivors = game.survivors
	check(sv.npcs.is_empty(), "nobody on the radio on day 1")
	GameState.day = 2
	var lines: PackedStringArray = sv.on_dawn({"breaches": 0})
	check(sv.npcs.has(&"tomas"), "Tomas is on the radio on day 2")
	check("\n".join(lines).contains("Tomas"), "the dawn summary says so")
	var npc: SurvivorNPC = sv.npcs[&"tomas"]
	await physics_frames(2)
	check_eq(sv.target().get("label", ""), "SURVIVOR", "green arrow points at him")
	check(npc.global_position.distance_to(Vector2(118.5, 70.5) * 16.0) < 64.0, "waiting at his house (%s)" % str(npc.global_position / 16.0))
	npc.interactable.interact(p)
	check_eq(npc.mode, SurvivorNPC.Mode.FOLLOWING, "E: he follows")
	check(String(sv.target().get("label", "")).contains("HOME"), "arrow now points home")
	var score_before: int = GameState.score
	p.global_position = Vector2(78.5, 70.5) * 16.0
	npc.global_position = Vector2(77.5, 70.5) * 16.0
	await physics_frames(3)
	check_eq(GameState.survivors.get(&"tomas", ""), "home", "rescued once you're both inside")
	check_eq(GameState.score - score_before, Survivors.RESCUE_POINTS, "+150 points")
	check_eq(npc.mode, SurvivorNPC.Mode.HOME, "goes to his spot")
	check_eq(Survivors.plank_health_mult(), 1.25, "Mechanic: tougher planks")
	game.queue_free()
	GameState.new_game(1)


func test_survivor_jobs() -> void:
	var game := _game()
	await physics_frames(3)
	var p := _player(game)
	var sv: Survivors = game.survivors
	# Mechanic: one free plank per window at dusk.
	GameState.survivors[&"tomas"] = "home"
	var w: Barricade = game.get_node("World/Map/Barricades/Window_safehouse_west")
	w.set_planks(1)
	sv._on_phase_changed(GameState.Phase.DUSK)
	check_eq(w.planks(), 2, "Tomas nails a plank at dusk")
	# Doctor and scavenger at dawn.
	GameState.survivors[&"amara"] = "home"
	GameState.survivors[&"pip"] = "home"
	p.health.take_damage(50.0, null)
	var bandages: int = GameState.stash_count(&"bandage")
	var stash_total := 0
	for id in GameState.stash:
		stash_total += GameState.stash[id]
	var lines: PackedStringArray = sv.on_dawn({"breaches": 0})
	check_eq(p.health.current_health, p.health.max_health, "Amara heals you")
	check(GameState.stash_count(&"bandage") >= bandages + 1, "and leaves a bandage")
	var total_after := 0
	for id in GameState.stash:
		total_after += GameState.stash[id]
	check(total_after >= stash_total + 4, "Pip brings 3 finds (plus the bandage)")
	check("\n".join(lines).contains("Pip brought back"), "listed at dawn")
	# Guard: shoots a zombie near the safehouse.
	GameState.survivors[&"hale"] = "home"
	for zz in get_tree().get_nodes_in_group(&"zombies"):
		zz.queue_free()
	await physics_frames(2)
	var z := spawn_walker(game.get_node("World/Actors"), Vector2(68.5, 71.5) * 16.0, Vector2.RIGHT)
	await physics_frames(2)
	var hp: float = z.health.current_health
	check(sv.guard_shoot() == z, "Hale fires at the nearest zombie")
	check(z.health.current_health < hp, "and hits it")
	var far := spawn_walker(game.get_node("World/Actors"), Vector2(20.5, 20.5) * 16.0, Vector2.RIGHT)
	z.health.take_damage(9999.0, null)
	await physics_frames(2)
	check(sv.guard_shoot() == null, "but not at zombies far away (%s)" % far.name)
	game.queue_free()
	GameState.new_game(1)


func test_survivors_can_die_when_the_horde_breaks_in() -> void:
	var game := _game()
	await physics_frames(3)
	var sv: Survivors = game.survivors
	var died := 0
	for night in 30:
		GameState.survivors = {&"tomas": "home", &"amara": "home", &"pip": "home"}
		GameState.nights_survived = night
		var before: int = Survivors.home_count()
		sv.on_dawn({"breaches": 0})
		check_eq(Survivors.home_count(), before, "no break-in, nobody dies")
		sv.on_dawn({"breaches": 2})
		var lost: int = before - Survivors.home_count()
		check(lost <= 1, "at most one a night")
		died += lost
	check(died >= 10 and died <= 26, "two broken windows: about 60%% of nights cost someone (%d of 30)" % died)
	game.queue_free()
	GameState.new_game(1)


func test_breaches_are_counted_at_night() -> void:
	var game := _game()
	await physics_frames(3)
	var dc: DayCycle = game.day_cycle
	var w: Barricade = game.get_node("World/Map/Barricades/Window_safehouse_west")
	w.set_planks(1)
	dc.start_night()
	w.take_hit(9999.0)
	check_eq(dc._breaches, 1, "a broken window at night counts")
	game.queue_free()
	GameState.new_game(1)


func test_playtest_log_writes_rows_and_summary() -> void:
	var game := _game()
	await physics_frames(3)
	var sl := SessionLog.new()
	sl.csv_path = "user://test_playtest_log.csv"
	sl.summary_path = "user://test_playtest_summary.txt"
	for f in [sl.csv_path, sl.summary_path]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	game.add_child(sl)
	sl.game = game
	sl.player = _player(game)
	sl.enabled = true
	sl.session_id = "test"
	sl.log_event("death", "walker")
	sl.rate(4)
	sl.write_summary("test")
	var csv: String = FileAccess.get_file_as_string(sl.csv_path)
	check(csv.begins_with(SessionLog.HEADER), "CSV has a header row")
	check(csv.contains(",death,") and csv.contains(",rating,"), "events are rows")
	var txt: String = FileAccess.get_file_as_string(sl.summary_path)
	check(txt.contains("Fun rating: 4/5"), "readable summary with the rating")
	for f in [sl.csv_path, sl.summary_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	game.queue_free()
	GameState.new_game(1)


func test_banners_wait_their_turn() -> void:
	var game := _game()
	await physics_frames(3)
	var hud: CanvasLayer = game.hud
	hud.show_banner("SUPPLY DROP", "a")
	hud.show_banner("SURVIVOR ON THE RADIO", "b")
	check_eq(hud._banner_title.text, "SUPPLY DROP", "first banner shows")
	check_eq(hud._banner_queue.size(), 1, "second one waits")
	hud._banner_tween.kill()
	hud._next_banner()
	check_eq(hud._banner_title.text, "SURVIVOR ON THE RADIO", "then the next")
	game.queue_free()
	GameState.new_game(1)
