extends Node
## Phase 11 end-to-end check: a "bot" plays LAST SIGNAL from a new game to the ending.
## It WALKS the real Ashford Lane map (movement input along navigation paths, physics and
## collisions on), opens doors with E, searches containers, carries quest items home, cuts
## the warehouse gate and repairs the radio. Several world seeds, so random loot is covered.
##
## Mode A (pass/fail): no Walkers, so it only tests the map and the quest flow (reachability,
## stuck spots, doors, panels, objectives).  Mode B (report only): normal Walkers, player can't die,
## records bites and time. Diagnostics only (not exported).
##
## Run: godot --headless --fixed-fps 60 res://tests/scenarios/playthrough_bot.tscn

const SEEDS: Array[int] = [1, 42, 777, 2026, 31337]
const LEG_TIMEOUT_S: float = 90.0

var game: Node
var p: Player
var failures: PackedStringArray = []
var _bites: int = 0


func _ready() -> void:
	SaveSystem.path = "user://tool_save.json"
	print("PLAYTHROUGH BOT")
	for s in SEEDS:
		await _run(s, false)
	await _run(SEEDS[0], true)
	for f in [SaveSystem.path, SaveSystem.path + ".bak", SaveSystem.path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	if failures.is_empty():
		print("PLAYTHROUGH PASSED (%d seeds walked to the ending)" % SEEDS.size())
	else:
		for f in failures:
			print("PLAYTHROUGH FAIL: ", f)
		print("PLAYTHROUGH FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)


func _run(seed_value: int, with_zombies: bool) -> void:
	var label: String = "seed %d%s" % [seed_value, " + Walkers" if with_zombies else ""]
	SaveSystem.fresh_start = true
	GameState.new_game(seed_value)
	game = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await _frames(5)
	p = game.get_node("World/Actors/Player")
	p.use_mouse_aim = false
	_bites = 0
	if with_zombies:
		p.health.setup(1.0e9)
		p.health.damaged.connect(func(_a: float, _s: Node) -> void: _bites += 1)
	else:
		for z in get_tree().get_nodes_in_group(&"zombies"):
			z.queue_free()
	await _frames(300)  # navigation map ready
	var start_ticks: int = Engine.get_physics_frames()
	var t: ObjectiveTracker = game.get_node("Objectives")
	var c := "World/Map/Containers/C_"
	var plan: Array = [
		["search", c + "grocery_shelf_01"], ["search", c + "grocery_shelf_02"], ["search", c + "grocery_shelf_03"],
		["search", c + "grocery_shelf_04"], ["search", c + "house_a_kitchen"], ["search", c + "house_b_kitchen"],
		["stash", "World/Map/Stash"], ["check", &"stock_up"],
		["search", c + "pharmacy_counter_01"], ["search", c + "pharmacy_cabinet_01"], ["search", c + "pharmacy_cabinet_02"],
		["check", &"first_aid"],
		["search", c + "vehicle_trunk_pickup_01"], ["use", "World/Map/WarehouseGate"], ["check", &"cut_the_lock"],
		["search", c + "warehouse_office_locker"], ["check", &"signal_parts"],
		["use", "World/Map/RadioDesk"], ["check", &"last_signal"],
	]
	var ok := true
	for step in plan:
		match step[0]:
			"check":
				if not t.is_completed(step[1]):
					_fail(label, "objective %s not complete when expected" % step[1])
					ok = false
			"search", "stash", "use":
				var node: Node = game.get_node_or_null(step[1])
				if node == null:
					_fail(label, "missing node " + step[1])
					ok = false
				elif not await _go_and_use_retry(node, step[0], 4 if with_zombies else 1):
					_fail(label, "%s %s failed (bot at %s)" % [step[0], node.name, str((p.global_position / 16.0).floor())])
					ok = false
		if not ok:
			break
	if ok and not (t.is_chain_complete() and game.ending_panel.visible):
		_fail(label, "chain not complete / ending not shown at the end")
		ok = false
	var minutes: float = (Engine.get_physics_frames() - start_ticks) / 60.0 / 60.0
	print("BOT %-16s %s  game time %.1f min  bites %d  kills %d" % [label, "ENDING REACHED" if ok else "STOPPED",
		minutes, _bites, int(GameState.stats.get("kills", 0))])
	if with_zombies and not ok:
		print("BOT   (report only) stopped at: ", failures[failures.size() - 1])
		failures.remove_at(failures.size() - 1)  # mode B is report-only (bots don't fight well)
	game.queue_free()
	await _frames(3)


func _fail(label: String, msg: String) -> void:
	failures.append("%s: %s" % [label, msg])


func _go_and_use_retry(node: Node, kind: String, attempts: int) -> bool:
	for i in attempts:
		if await _go_and_use(node, kind):
			return true
		await _defend(90)  # clear the area, then try again
	return false


## Mode B: bat swings and shoves at Walkers in reach (the bot can't aim like a person).
## Returns true if it acted this frame.
func _fight_if_close() -> bool:
	var best: Zombie = null
	var best_d := 26.0
	for z in get_tree().get_nodes_in_group(&"zombies"):
		var zz := z as Zombie
		if zz.state == Zombie.State.DEAD:
			continue
		var d: float = zz.global_position.distance_to(p.global_position)
		if d < best_d:
			best = zz
			best_d = d
	if best == null:
		return false
	p.aim_direction = p.global_position.direction_to(best.global_position)
	if p.weapons.current != 0:
		p.try_switch(0)
	if best.state != Zombie.State.STUNNED and p.shove_ready():
		p.try_shove()
	else:
		p.try_attack()
	return true


func _defend(frames: int) -> void:
	p.move_override = Vector2.ZERO
	for i in frames:
		_fight_if_close()
		await _frames(1)


## Walks to `node`'s interaction spot, presses E on it and finishes what it opens.
func _go_and_use(node: Node, kind: String) -> bool:
	var it: Interactable = node.get_node("Interact") as Interactable
	var shape := it.get_node("Shape") as CollisionShape2D
	var center: Vector2 = shape.global_position
	var map: RID = p.get_world_2d().navigation_map
	var goal: Vector2 = NavigationServer2D.map_get_closest_point(map, center)
	var deadline: int = Engine.get_physics_frames() + int(LEG_TIMEOUT_S * 60.0)
	var path := PackedVector2Array()
	var idx := 0
	var repath_at := 0
	var last_pos: Vector2 = p.global_position
	var stuck_check_at: int = Engine.get_physics_frames() + 90
	var wiggle_until := 0
	var wiggle := Vector2.ZERO
	while Engine.get_physics_frames() < deadline:
		var now: int = Engine.get_physics_frames()
		if p.current_interactable == it:
			break
		if p.global_position.distance_to(goal) < 6.0:
			p.move_override = Vector2.ZERO
			p.aim_direction = p.global_position.direction_to(center) if p.global_position.distance_to(center) > 0.5 else Vector2.DOWN
			await _frames(1)
			if p.current_interactable != it:
				# Facing it from the closest walkable point isn't enough: step a little toward it.
				p.move_override = p.global_position.direction_to(center) * 0.4
				await _frames(4)
			continue
		if now >= repath_at:
			path = NavigationServer2D.map_get_path(map, p.global_position, goal, true)
			idx = 0
			repath_at = now + 30
		while idx < path.size() and p.global_position.distance_to(path[idx]) < 4.0:
			idx += 1
		var target: Vector2 = path[idx] if idx < path.size() else goal
		var dir: Vector2 = p.global_position.direction_to(target)
		if now < wiggle_until:
			dir = wiggle
		p.move_override = dir
		if dir != Vector2.ZERO:
			p.aim_direction = dir
		# A closed door in front of the bot: open it (E), like a player would.
		if _fight_if_close():
			p.move_override = Vector2.ZERO
			await _frames(1)
			continue
		var cur := p.current_interactable
		if cur != null and cur != it and cur.get_parent() is Door:
			var d := cur.get_parent() as Door
			if not d.is_open and not d.locked:
				p.try_interact()
		if now >= stuck_check_at:
			if p.global_position.distance_to(last_pos) < 4.0:
				wiggle = Vector2.RIGHT.rotated(randf() * TAU)
				wiggle_until = now + 20
				repath_at = now
			last_pos = p.global_position
			stuck_check_at = now + 90
		await _frames(1)
	p.move_override = Vector2.ZERO
	if p.current_interactable != it:
		return false
	await _frames(2)
	if not p.try_interact():
		return false
	match kind:
		"search":
			var lc := node as LootContainer
			var wait_until: int = Engine.get_physics_frames() + int((lc.get_search_time() + 1.0) * 60.0)
			while not game.loot_panel.visible and Engine.get_physics_frames() < wait_until:
				await _frames(1)
			if not game.loot_panel.visible:
				return false
			# Take the quest items (a real player picks those first); the rest stays.
			for item_id in lc.all_guaranteed_items():
				var have: int = 0
				for e in GameState.get_contents(lc.container_id):
					if e.id == item_id:
						have += int(e.qty)
				if have > 0:
					GameState.take_from(lc.container_id, item_id, have, p.inventory)
			game.loot_panel.close()
		"stash":
			await _frames(2)
			if not game.stash_panel.visible:
				return false
			game.stash_panel.store_all()
			game.stash_panel.close()
		"use":
			await _frames(2)
	await _frames(5)
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
