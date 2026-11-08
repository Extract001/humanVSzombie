extends Node2D
## Gameplay root for the Phase 1 prototype: places the player at the map's spawn point,
## connects the HUD and shows the game-over screen when the player dies.
## Phase 5: loot/inventory panels, item piles and death backpacks (from GameState), respawn.
## Phase 7: objective chain, safehouse stations (stash, bed, radio desk, objective board).
## Phase 8: pause menu (Esc), settings, back to the main menu.
## Phase 10: saving (death, bed, entering the safehouse, quitting from the safehouse) and loading.
## Slice 1 (night siege): DayCycle (day → dusk → night → dawn), the dawn summary, bed = sleep until dusk.

const DEATH_SCREEN_DELAY: float = 1.0
const PILE_SCENE: PackedScene = preload("res://scenes/world/loot_container.tscn")
## You can't sleep with a zombie this close (px).
const SLEEP_SAFE_DISTANCE: float = 200.0
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## Safehouse interior (tiles x 71-85, y 65-77): calmer ambience and music in here.
const SAFEHOUSE_RECT := Rect2(71 * 16, 65 * 16, 15 * 16, 13 * 16)

@onready var world: Node2D = $World
@onready var player: Player = $World/Actors/Player
@onready var hud: CanvasLayer = $HUD
@onready var game_over: CanvasLayer = $GameOver
@onready var crosshair: CanvasLayer = $Crosshair
@onready var loot_panel: CanvasLayer = $LootPanel
@onready var inventory_panel: CanvasLayer = $InventoryPanel
@onready var stash_panel: CanvasLayer = $StashPanel
@onready var objectives_panel: CanvasLayer = $ObjectivesPanel
@onready var ending_panel: CanvasLayer = $EndingPanel
@onready var objectives: ObjectiveTracker = $Objectives
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var settings_menu: CanvasLayer = $SettingsMenu

var piles_root: Node2D
var day_cycle: DayCycle
var dawn_panel: CanvasLayer
## Fun pass
var score_keeper: ScoreKeeper
var population: Population
var _last_backpack: StringName = &""

var elapsed: float = 0.0
var kills: int = 0
var _was_in_safehouse: bool = true
var _last_auto_save_ms: int = -100000
var _perf_log: bool = false
var _perf_timer: float = 0.0


func _ready() -> void:
	var map: Node = world.get_node("Map")
	var spawn: Marker2D = map.get_node_or_null("PlayerSpawn")
	if spawn != null:
		player.global_position = spawn.global_position
	var bounds: Rect2 = map.get_meta(&"bounds", Rect2(0, 0, 960, 640))
	player.camera.limit_left = int(bounds.position.x)
	player.camera.limit_top = int(bounds.position.y)
	player.camera.limit_right = int(bounds.end.x)
	player.camera.limit_bottom = int(bounds.end.y)
	player.camera.reset_smoothing()

	if not GameState.started:
		GameState.new_game()
	var rings := Node2D.new()
	rings.name = "NoiseRings"
	rings.set_script(load("res://scripts/world/noise_rings.gd"))
	world.add_child(rings)
	piles_root = Node2D.new()
	piles_root.name = "Piles"
	world.add_child(piles_root)
	world.move_child(piles_root, world.get_node("Actors").get_index())  # drawn under the actors
	GameState.piles_changed.connect(_sync_piles)
	_sync_piles()

	day_cycle = DayCycle.new()
	day_cycle.name = "DayCycle"
	add_child(day_cycle)
	day_cycle.setup(self, player, world.get_node("Actors"), world)
	day_cycle.dawn.connect(_on_dawn)
	dawn_panel = CanvasLayer.new()
	dawn_panel.name = "DawnPanel"
	dawn_panel.set_script(load("res://scripts/ui/dawn_panel.gd"))
	add_child(dawn_panel)
	dawn_panel.bind(player)

	var splats := Node2D.new()
	splats.name = "BloodSplats"
	world.add_child(splats)
	world.move_child(splats, piles_root.get_index())  # under piles and actors
	score_keeper = ScoreKeeper.new()
	score_keeper.name = "ScoreKeeper"
	add_child(score_keeper)
	score_keeper.setup(world, splats, player)
	population = Population.new()
	population.name = "Population"
	add_child(population)
	population.setup(self, player, world.get_node("Actors"))

	Soundscape.player = player
	hud.bind(player)
	hud.bind_cycle(day_cycle)
	hud.bind_game(self)
	score_keeper.streak_changed.connect(hud.show_streak)
	loot_panel.bind(player)
	inventory_panel.bind(player)
	stash_panel.bind(player)
	objectives_panel.bind(player, objectives)
	ending_panel.bind(player)
	objectives.objective_completed.connect(func(o: ObjectiveData) -> void:
		score_keeper.on_objective_completed()
		get_tree().call_group(&"hud", &"show_toast", "Objective complete: " + o.title))
	objectives.chain_completed.connect(func() -> void: ending_panel.open())
	objectives.progress_changed.connect(func(o: ObjectiveData) -> void:
		hud.set_objective(o.title if o != null else "", objectives.progress_text(o)))
	objectives.bind(player)
	objectives.validate_quest_items()
	for station in get_tree().get_nodes_in_group(&"safehouse_stations"):
		(station as SafehouseStation).used.connect(_on_station_used)
	pause_menu.bind(self)
	game_over.main_menu_requested.connect(go_to_main_menu)
	for panel in [loot_panel, inventory_panel, stash_panel, objectives_panel, ending_panel, pause_menu, dawn_panel]:
		panel.opened.connect(_update_ui_mode)
		panel.closed.connect(_update_ui_mode)
	_restore_from_save()
	_was_in_safehouse = is_in_safehouse()
	game_over.respawn_requested.connect(respawn_player)
	player.backpack_dropped.connect(func(id: StringName) -> void: _last_backpack = id)
	player.died.connect(_on_player_died)
	add_to_group(&"score_listeners")   # every zombie death (placed, street, horde) counts
	# The crosshair replaces the system cursor during play (not in tests/headless runs).
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	# Marker line used by the automated browser load test.
	print("LAST_SIGNAL_READY")
	_perf_log = _wants_perf_log()
	if _perf_log:
		player.state_changed.connect(func(st: Player.State) -> void: print("DIAG state ", Player.State.keys()[st]))
		player.weapons.reload_started.connect(func(_d: float) -> void: print("DIAG reload started"))
		player.weapons.reload_cancelled.connect(func() -> void: print("DIAG reload cancelled"))
		player.weapons.reload_finished.connect(func() -> void: print("DIAG reload finished"))
		player.health.damaged.connect(func(a: float, _s: Node) -> void: print("DIAG bitten %.0f" % a))
		inventory_panel.opened.connect(func() -> void: print("DIAG inventory opened slots=%d" % player.inventory.used_slots()))
		inventory_panel.closed.connect(func() -> void: print("DIAG inventory closed"))
		loot_panel.opened.connect(func() -> void: print("DIAG loot opened"))
		stash_panel.opened.connect(func() -> void: print("DIAG stash opened"))
		pause_menu.opened.connect(func() -> void: print("DIAG paused"))
		SaveSystem.saved.connect(func(reason: String) -> void: print("DIAG saved " + reason))
		pause_menu.closed.connect(func() -> void: print("DIAG resumed"))
		objectives_panel.opened.connect(func() -> void: print("DIAG objectives opened"))
		objectives.progress_changed.connect(func(o: ObjectiveData) -> void:
			print("DIAG objective %s | %s" % [o.id if o != null else &"done", objectives.progress_text(o)]))
		player.search_started.connect(func(c: LootContainer, d: float) -> void: print("DIAG search %s %.1fs" % [c.container_id, d]))
		player.search_cancelled.connect(func() -> void: print("DIAG search cancelled"))
		var last_light := [false]
		player.flashlight_changed.connect(func(on: bool, charge: float) -> void:
			if on != last_light[0]:
				last_light[0] = on
				print("DIAG flashlight %s battery=%d%%" % ["on" if on else "off", int(charge * 100.0)]))
		NoiseSystem.noise_emitted.connect(func(_p: Vector2, r: float, src: Node) -> void:
			if src == player and r >= 100.0:
				print("DIAG player noise %d px" % int(r)))
		GameState.piles_changed.connect(func() -> void: print("DIAG piles=%d bandages=%d" % [GameState.piles.size(), player.inventory.count(&"bandage")]))


func _process(delta: float) -> void:
	if not player.is_dead():
		elapsed += delta
	var inside: bool = is_in_safehouse()
	Soundscape.set_mood("safehouse" if inside else "outside")
	if inside and not _was_in_safehouse and not player.is_dead() and not day_cycle.is_night() \
			and Time.get_ticks_msec() - _last_auto_save_ms > 5000:
		_last_auto_save_ms = Time.get_ticks_msec()
		if save_now("safehouse"):   # back home safe: autosave
			get_tree().call_group(&"hud", &"show_toast", "Game saved")
	_was_in_safehouse = inside
	if _perf_log:
		_perf_timer += delta
		if _perf_timer >= 2.0:
			_perf_timer = 0.0
			print("PERF fps=%d pos=%s dark=%s kills=%d ammo=%d/%d" % [Engine.get_frames_per_second(),
				str(player.global_position.round()), str(player.in_darkness), kills,
				player.weapons.loaded_rounds(), player.weapons.reserve_for(player.weapons.current_weapon())])


## Diagnostics only: FPS logging when the web page URL contains "?perf",
## or the desktop game is started with "-- --perf-log".
func _wants_perf_log() -> bool:
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("window.location.search", true)
		return str(query).contains("perf")
	return OS.get_cmdline_user_args().has("--perf-log")


func on_zombie_killed(_z: Zombie) -> void:
	_on_zombie_died()


func _on_zombie_died() -> void:
	kills += 1
	GameState.stats.kills = int(GameState.stats.get("kills", 0)) + 1
	hud.set_kills(kills)


func _on_player_died() -> void:
	save_now("death")   # immediately, so quitting can't undo the death (GDD §3)
	score_keeper.record()
	await get_tree().create_timer(DEATH_SCREEN_DELAY, false).timeout
	if not player.is_dead():
		return
	crosshair.visible = false
	var lost := 0
	var contents: Array = GameState.get_contents(_last_backpack)
	for e in contents:
		lost += int(e.qty)
	game_over.show_screen(elapsed, kills, _last_backpack != &"", lost, contents.size())


## Respawn at the safehouse bed (RespawnPoint), 75 HP, full stamina. Backpacks stay in the world.
func respawn_player() -> void:
	player.respawn(respawn_point(), player.stats.respawn_health)
	game_over.visible = false
	_update_ui_mode()
	get_tree().call_group(&"hud", &"show_toast", "You wake up in the safehouse")


## One node per GameState pile; removes nodes for piles that were emptied.
func _sync_piles() -> void:
	var existing: Dictionary = {}
	for node in piles_root.get_children():
		var c := node as LootContainer
		if c == null or c.is_queued_for_deletion():
			continue
		if GameState.piles.has(c.container_id):
			existing[c.container_id] = true
		else:
			c.queue_free()
	for id in GameState.piles:
		if existing.has(id):
			continue
		var data: Dictionary = GameState.piles[id]
		var pile: LootContainer = PILE_SCENE.instantiate()
		pile.name = String(id)
		pile.container_id = id
		pile.container_type = &"backpack"
		pile.is_pile = true
		pile.look = LootContainer.Look.BACKPACK if data.backpack else LootContainer.Look.PILE
		pile.display_name = "Your backpack" if data.backpack else "Dropped items"
		pile.position = data.position
		piles_root.add_child(pile)


func _on_station_used(station: SafehouseStation, _by: Node) -> void:
	match station.kind:
		SafehouseStation.Kind.STASH:
			stash_panel.open()
		SafehouseStation.Kind.BOARD:
			objectives_panel.open()
		SafehouseStation.Kind.BED:
			try_sleep()
		SafehouseStation.Kind.RADIO:
			use_radio()


## Bed: full heal, sleep until dusk (Slice 1; the day now ends at dawn after the night) and save.
## Refused at dusk/night and with a zombie nearby. Returns true if you slept.
func try_sleep() -> bool:
	if GameState.phase != GameState.Phase.DAY:
		get_tree().call_group(&"hud", &"show_toast", "No time to sleep. They're coming.")
		return false
	for z in get_tree().get_nodes_in_group(&"zombies"):
		if (z as Zombie).state != Zombie.State.DEAD and (z as Zombie).global_position.distance_to(player.global_position) < SLEEP_SAFE_DISTANCE:
			get_tree().call_group(&"hud", &"show_toast", "You can't sleep with them this close.")
			return false
	player.health.heal(player.health.max_health)
	day_cycle.skip_to_dusk()
	save_now("bed")
	get_tree().call_group(&"hud", &"show_toast", "You sleep until dusk. Game saved. Board up the windows!")
	hud.flash_black()
	return true


## Slice 1: a night was survived. Save first (the summary pauses the game), then show it.
func _on_dawn(summary: Dictionary) -> void:
	summary["night_points"] = score_keeper.on_night_survived(int(summary.night))
	summary["score"] = GameState.score
	summary["new_best"] = score_keeper.record()
	summary["best"] = Settings.best_score
	save_now("dawn")
	dawn_panel.show_summary(summary)


func use_radio() -> void:
	var msg: String = objectives.try_repair_radio()
	if msg != "":
		get_tree().call_group(&"hud", &"show_toast", msg)
	elif objectives.is_chain_complete() and not ending_panel.visible:
		ending_panel.open()  # listen to the broadcast again


## Esc pauses only during normal play (not on the death screen or while a panel is open;
## those panels close with Esc themselves).
func can_pause() -> bool:
	return not player.is_dead() and not game_over.visible and not player.ui_open and not settings_menu.visible


func go_to_main_menu() -> void:
	if is_in_safehouse() and not player.is_dead():
		save_now("menu")
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Mouse and crosshair follow whether a panel is open; the player ignores clicks meanwhile.
func _update_ui_mode() -> void:
	var panel_open: bool = loot_panel.visible or inventory_panel.visible or stash_panel.visible \
		or objectives_panel.visible or ending_panel.visible or pause_menu.visible \
		or (dawn_panel != null and dawn_panel.visible)
	player.ui_open = panel_open
	crosshair.visible = not panel_open and not game_over.visible
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (panel_open or game_over.visible) else Input.MOUSE_MODE_HIDDEN


func _exit_tree() -> void:
	if Soundscape.player == player:
		Soundscape.player = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------- saving (Phase 10) ----------------

func is_in_safehouse() -> bool:
	return SAFEHOUSE_RECT.has_point(player.global_position)


func respawn_point() -> Vector2:
	var map: Node = world.get_node("Map")
	var point: Node2D = map.get_node_or_null("RespawnPoint")
	if point == null:
		point = map.get_node_or_null("PlayerSpawn")
	return point.global_position if point != null else player.global_position


func make_save_data() -> Dictionary:
	var dead: Array = []
	for z in world.get_node("Actors").get_children():
		if z is Zombie and (z as Zombie).state == Zombie.State.DEAD:
			dead.append(String(z.name))
	var open_doors: Array = []
	for d in get_tree().get_nodes_in_group(&"doors"):
		if (d as Door).is_open:
			open_doors.append(String(world.get_node("Map").get_path_to(d)))
	GameState.stats["time"] = elapsed
	return {
		"player": player.to_save_dict(),
		"world": GameState.to_dict(),
		"game": {"elapsed": elapsed, "dead_zombies": dead, "doors_open": open_doors},
	}


## Writes the save now. Returns true on success (a failure keeps the previous save and shows a message).
func save_now(reason: String) -> bool:
	var err: Error = SaveSystem.save_game(make_save_data(), reason)
	if err != OK:
		get_tree().call_group(&"hud", &"show_toast", "Couldn't save the game (%s)." % error_string(err))
	return err == OK


## After Continue: put the player, the dead zombies and the doors back as they were saved.
## (GameState - containers, backpacks, stash, objectives, unlocks - was already restored by SaveSystem.)
func _restore_from_save() -> void:
	if SaveSystem.pending_player.is_empty():
		if SaveSystem.fresh_start:   # a brand-new game replaces the old save straight away
			SaveSystem.fresh_start = false
			save_now.call_deferred("new_game")
			get_tree().call_group.call_deferred(&"hud", &"show_toast",
				"Scavenge by day. At night they come for your safehouse: board up the windows (E, 1 scrap).")
		return
	var d: Dictionary = SaveSystem.pending_player
	SaveSystem.pending_player = {}
	var g: Dictionary = d.get("game", {})
	elapsed = float(g.get("elapsed", 0.0))
	kills = int(GameState.stats.get("kills", 0))
	hud.set_kills(kills)
	var actors: Node = world.get_node("Actors")
	for name in g.get("dead_zombies", []):
		var z: Node = actors.get_node_or_null(NodePath(name))
		if z is Zombie:
			z.queue_free()   # killed zombies stay dead (a new day doesn't refill them yet)
	var map: Node = world.get_node("Map")
	for p in g.get("doors_open", []):
		var door := map.get_node_or_null(NodePath(p)) as Door
		if door != null and not door.locked:
			door.is_open = true
	player.apply_save_dict(d, respawn_point())
	objectives.validate_quest_items()
	get_tree().call_group(&"hud", &"show_toast", ("Day %d" % GameState.day) if GameState.phase == GameState.Phase.DAY
		else "Day %d. Dusk is falling: board up!" % GameState.day)

