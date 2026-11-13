extends Node
## Slice 1 balance measurements: how hard is a night? (report only, no pass/fail)
## For several nights / Heat / board levels it runs a whole night and records:
## - PASSIVE: the player just stands in the middle of the safehouse (can't die). Time until the
##   first window breaks, windows broken by dawn, horde Walkers that got inside, bite damage.
## - DEFEND: a simple defender bot (can't die) with a bat and 6 scrap: hits Walkers in reach,
##   re-boards damaged windows when nobody is right there.
## Town Walkers are removed so only the horde counts.
## Run: godot --headless --fixed-fps 60 res://tests/scenarios/siege_scenarios.tscn

const SIEGE: SiegeData = preload("res://data/siege/siege_data.tres")
const ROOM_CENTER := Vector2(78.5, 71.5) * 16.0
const ROOM := Rect2(71 * 16, 65 * 16, 15 * 16, 13 * 16)

var rows: PackedStringArray = []


func _ready() -> void:
	SaveSystem.path = "user://tool_save.json"
	GameState.street_spawns_disabled = true  # fun pass: measure the placed/horde zombies only
	GameState.records_disabled = true
	GameState.intro_disabled = true
	print("SIEGE SCENARIOS (night length %d s, %d Walker damage per hit on boards every %.1f s, %d HP per plank)" % [
		SIEGE.night_length, SIEGE.zombie_barricade_damage, SIEGE.zombie_barricade_interval, SIEGE.plank_health])
	print("mode     night heat boards | horde | 1st breach | windows broken | got inside | bites  dmg | kills | scrap used")
	for cfg in [[1, 0, 2], [1, 4, 2], [3, 0, 1], [3, 0, 3], [5, 0, 3], [5, 6, 3], [10, 0, 3], [10, 8, 3]]:
		for mode in ["PASSIVE", "DEFEND"]:
			await _night(mode, cfg[0], cfg[1], cfg[2])
	print("SIEGE SCENARIOS COMPLETED")
	for f in [SaveSystem.path, SaveSystem.path + ".bak", SaveSystem.path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	get_tree().quit()


func _night(mode: String, night: int, heat: float, boards: int) -> void:
	SaveSystem.fresh_start = false
	GameState.new_game(night * 100 + int(heat))
	seed(night * 7919 + int(heat) * 31 + boards)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await _frames(5)
	for z in get_tree().get_nodes_in_group(&"zombies"):
		z.queue_free()
	await _frames(300)   # navigation ready
	var p: Player = game.get_node("World/Actors/Player")
	p.use_mouse_aim = false
	p.health.setup(1.0e9)
	p.global_position = ROOM_CENTER
	var bites := [0, 0.0]
	p.health.damaged.connect(func(a: float, _s: Node) -> void:
		bites[0] += 1
		bites[1] += a)
	var scrap_start := 6
	if mode == "DEFEND":
		p.inventory.add_item(&"scrap", scrap_start)
	for b in get_tree().get_nodes_in_group(&"barricades"):
		(b as Barricade).set_planks(boards)
	GameState.nights_survived = night - 1
	GameState.heat = heat
	var dawned := [false]
	game.day_cycle.dawn.connect(func(_s: Dictionary) -> void: dawned[0] = true)
	game.day_cycle.start_night()
	var horde: int = game.day_cycle.horde_alive()
	var first_breach := -1.0
	var inside_ids := {}
	var frames := 0
	while not dawned[0] and frames < int((SIEGE.night_length + 5.0) * 60.0):
		if mode == "DEFEND":
			_defend(p)
		for b in get_tree().get_nodes_in_group(&"barricades"):
			if (b as Barricade).is_broken() and first_breach < 0.0:
				first_breach = GameState.phase_time
		for z in get_tree().get_nodes_in_group(&"horde"):
			if (z as Zombie).state != Zombie.State.DEAD and ROOM.has_point((z as Zombie).global_position):
				inside_ids[z.get_instance_id()] = true
		await _frames(1)
		frames += 1
	var broken := 0
	for b in get_tree().get_nodes_in_group(&"barricades"):
		if (b as Barricade).is_broken():
			broken += 1
	if game.dawn_panel.visible:
		game.dawn_panel.pick_first_and_close()
	get_tree().paused = false
	var kills: int = int(GameState.stats.get("kills", 0))
	print("%-8s %5d %4d %6d | %5d | %10s | %14d | %10d | %5d %4d | %5d | %d" % [mode, night, int(heat), boards, horde,
		("%.0f s" % first_breach) if first_breach >= 0.0 else "never", broken, inside_ids.size(), bites[0], int(bites[1]),
		kills, (scrap_start - p.inventory.count(&"scrap")) if mode == "DEFEND" else 0])
	game.queue_free()
	await _frames(3)


## Defender bot: fight what's in reach; otherwise fix the most damaged window nobody stands at;
## otherwise wait in the middle.
func _defend(p: Player) -> void:
	p.move_override = Vector2.ZERO
	if p.is_working():
		return
	var best: Zombie = null
	var best_d := 34.0
	for z in get_tree().get_nodes_in_group(&"zombies"):
		var zz := z as Zombie
		if zz.state == Zombie.State.DEAD:
			continue
		var d: float = zz.global_position.distance_to(p.global_position)
		if d < best_d:
			best = zz
			best_d = d
	if best != null:
		p.aim_direction = p.global_position.direction_to(best.global_position)
		if best.state != Zombie.State.STUNNED and p.shove_ready() and best_d < 26.0:
			p.try_shove()
		else:
			p.try_attack()
		return
	# Nearest threat to a window: go stand inside it.
	var target_w: Barricade = null
	var worst := 1.0e9
	for b in get_tree().get_nodes_in_group(&"barricades"):
		var w := b as Barricade
		var threat := false
		for z in get_tree().get_nodes_in_group(&"zombies"):
			if (z as Zombie).state != Zombie.State.DEAD and (z as Zombie).global_position.distance_to(w.center()) < 70.0:
				threat = true
		var score: float = w.health() - (100.0 if threat else 0.0)
		if (threat or w.planks() < SIEGE.max_planks) and score < worst:
			worst = score
			target_w = w
	if target_w == null:
		var to_c: Vector2 = ROOM_CENTER - p.global_position
		p.move_override = to_c.normalized() if to_c.length() > 6.0 else Vector2.ZERO
		return
	var inward: Vector2 = target_w.center().direction_to(ROOM_CENTER)
	var spot: Vector2 = target_w.center() + inward * 15.0
	if p.global_position.distance_to(spot) > 4.0:
		p.move_override = p.global_position.direction_to(spot)
		p.aim_direction = p.move_override
		return
	p.aim_direction = -inward
	if target_w.planks() < SIEGE.max_planks and p.inventory.count(&"scrap") > 0 and p.current_interactable == target_w.get_node("Interact"):
		p.try_interact()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
