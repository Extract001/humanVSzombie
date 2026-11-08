extends "res://tests/test_case.gd"
## Zombie intelligence (QA: Phase 3). Noise, navigation, search, wander, group alert, dormant mode.


func _still_player(parent: Node, pos: Vector2) -> Player:
	var p := spawn_player(parent, pos)
	p.set_physics_process(false)
	return p


func test_noise_inside_radius_is_investigated_outside_is_not() -> void:
	var sandbox := make_sandbox()
	_still_player(sandbox, Vector2(-500, -500))
	var near := spawn_walker(sandbox, Vector2(150, 0), Vector2.RIGHT)
	var far := spawn_walker(sandbox, Vector2(250, 0), Vector2.RIGHT)
	await physics_frames(3)
	var heard: int = NoiseSystem.emit_noise(Vector2.ZERO, 200.0, null)
	check_eq(heard, 1, "one listener heard it")
	check_eq(near.state, Zombie.State.INVESTIGATE, "zombie at 150 px investigates a 200 px noise")
	check(far.state != Zombie.State.INVESTIGATE, "zombie at 250 px doesn't hear it")


func test_wall_halves_noise_radius() -> void:
	var sandbox := make_sandbox()
	add_wall(sandbox, Rect2(70, -100, 10, 200))
	_still_player(sandbox, Vector2(-500, -500))
	var behind_wall := spawn_walker(sandbox, Vector2(150, 0), Vector2.RIGHT)
	var behind_wall_close := spawn_walker(sandbox, Vector2(95, 0), Vector2.RIGHT)
	await physics_frames(3)
	NoiseSystem.emit_noise(Vector2.ZERO, 200.0, null)
	check(behind_wall.state != Zombie.State.INVESTIGATE, "150 px behind a wall: 200 px noise counts as 100 px -> not heard")
	check_eq(behind_wall_close.state, Zombie.State.INVESTIGATE, "95 px behind a wall: still heard")


func test_investigation_paths_around_a_wall() -> void:
	var sandbox := make_sandbox()
	# A long wall with a gap at the bottom: the zombie must walk around it.
	add_wall(sandbox, Rect2(100, -200, 12, 300))
	_still_player(sandbox, Vector2(-400, -400))
	var z := spawn_walker(sandbox, Vector2(40, 0), Vector2.RIGHT)
	await add_navigation(sandbox, Rect2(-300, -300, 700, 600))
	var noise_at := Vector2(180, 0)
	z.hear_noise(noise_at, 300.0, null)
	check_eq(z.state, Zombie.State.INVESTIGATE, "investigating")
	var start: Vector2 = z.global_position
	var travelled := 0.0
	var last: Vector2 = start
	for i in 60 * 12:
		await physics_frames(1)
		travelled += z.global_position.distance_to(last)
		last = z.global_position
		if z.state == Zombie.State.SEARCH:
			break
	check_eq(z.state, Zombie.State.SEARCH, "arrived and started searching")
	check(z.global_position.distance_to(noise_at) < 12.0, "reached the noise (%.1f px away)" % z.global_position.distance_to(noise_at))
	check(travelled > start.distance_to(noise_at) * 1.5, "walked around the wall (%.0f px vs straight %.0f px)" % [travelled, start.distance_to(noise_at)])


func test_search_looks_around_then_gives_up() -> void:
	var sandbox := make_sandbox()
	_still_player(sandbox, Vector2(-500, -500))
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	await physics_frames(2)
	z.hear_noise(Vector2(10, 0), 100.0, null)
	await physics_frames(30)
	check_eq(z.state, Zombie.State.SEARCH, "searching at the noise spot")
	var facings: Array[Vector2] = []
	for i in 4:
		await physics_frames(65)
		facings.append(z.facing)
	var turned := false
	for i in range(1, facings.size()):
		if facings[i].angle_to(facings[i - 1]) != 0.0:
			turned = true
	check(turned, "turns to look around while searching")
	await physics_frames(60 * 3)
	check_eq(z.state, Zombie.State.IDLE, "gives up after the 6 s search")


func test_chase_follows_player_around_a_corner() -> void:
	# The search phase looks around in random directions, so whether it spots a player standing
	# still around the corner is a dice roll (~12% misses unseeded, measured 2026-11-08). That is
	# intended gameplay ("you can lose them"); the test fixes the dice so it checks path-following.
	seed(20261108)
	var sandbox := make_sandbox()
	add_wall(sandbox, Rect2(60, -200, 12, 230))  # wall with an opening below y = 30
	var p := spawn_player(sandbox, Vector2(30, -40))
	var z := spawn_walker(sandbox, Vector2(-60, -40), Vector2.RIGHT)
	await add_navigation(sandbox, Rect2(-300, -300, 600, 600))
	await physics_frames(20)
	check_eq(z.state, Zombie.State.CHASE, "chasing the visible player")
	# Player walks down, around the end of the wall and up the other side (out of sight).
	p.move_override = Vector2.DOWN
	await physics_frames(70)
	p.move_override = Vector2.RIGHT
	await physics_frames(50)
	p.move_override = Vector2.UP
	await physics_frames(60)
	p.move_override = Vector2.ZERO
	var reached := false
	for i in 60 * 10:
		await physics_frames(1)
		if z.global_position.distance_to(p.global_position) < 24.0:
			reached = true
			break
	check(reached, "zombie found the player behind the wall (ended %.0f px away, state %s)" % [
		z.global_position.distance_to(p.global_position), Zombie.State.keys()[z.state]])


func test_idle_zombie_wanders_near_home() -> void:
	var sandbox := make_sandbox()
	_still_player(sandbox, Vector2(400, 0))
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.LEFT, true)
	var states := {}
	z.state_changed.connect(func(st: Zombie.State) -> void: states[st] = true)
	var max_dist := 0.0
	for i in 60 * 14:
		await physics_frames(1)
		max_dist = maxf(max_dist, z.global_position.length())
	check(states.has(Zombie.State.WANDER), "it wandered")
	check(states.has(Zombie.State.IDLE), "and stopped again")
	check(max_dist > 5.0, "it actually moved (%.1f px)" % max_dist)
	check(max_dist < 80.0 * 3.0, "it stayed in its area (%.1f px)" % max_dist)


func test_spotting_player_alerts_nearby_zombies() -> void:
	var sandbox := make_sandbox()
	_still_player(sandbox, Vector2(0, 0))
	var spotter := spawn_walker(sandbox, Vector2(60, 0), Vector2.LEFT)       # sees the player
	var nearby := spawn_walker(sandbox, Vector2(170, 0), Vector2.RIGHT)      # facing away, 110 px from the spotter
	var far_away := spawn_walker(sandbox, Vector2(320, 0), Vector2.RIGHT)    # 260 px from the spotter
	var groans := [0]
	var count := func(_pos: Vector2, _r: float, src: Node) -> void:
		if src == spotter:
			groans[0] += 1
	NoiseSystem.noise_emitted.connect(count)
	await physics_frames(20)
	NoiseSystem.noise_emitted.disconnect(count)
	check_eq(spotter.state, Zombie.State.CHASE, "spotter chases")
	check_eq(groans[0], 1, "spotter groaned once")
	check(nearby.state == Zombie.State.INVESTIGATE or nearby.state == Zombie.State.CHASE,
		"nearby zombie reacts to the groan (state %s)" % Zombie.State.keys()[nearby.state])
	check(far_away.state != Zombie.State.INVESTIGATE and far_away.state != Zombie.State.CHASE,
		"zombie 260 px away doesn't hear the 140 px groan")


func test_investigating_zombies_do_not_cascade_groans() -> void:
	# Only zombies that actually SEE the player groan; hearing a groan never makes another groan.
	var sandbox := make_sandbox()
	_still_player(sandbox, Vector2(-900, -900))
	for i in 6:
		spawn_walker(sandbox, Vector2(i * 60, 0), Vector2.UP)
	await physics_frames(2)
	var noises := [0]
	var count := func(_p: Vector2, _r: float, _s: Node) -> void: noises[0] += 1
	NoiseSystem.noise_emitted.connect(count)
	NoiseSystem.emit_noise(Vector2(0, 0), 400.0, null)
	await physics_frames(60)
	NoiseSystem.noise_emitted.disconnect(count)
	check_eq(noises[0], 1, "only the original noise was emitted (no chain reaction)")


func test_gunshot_pulls_zombies_in_range_only() -> void:
	var sandbox := make_sandbox()
	add_wall(sandbox, Rect2(-20, 150, 300, 12))
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.aim_direction = Vector2.LEFT
	var open_300 := spawn_walker(sandbox, Vector2(300, 0), Vector2.RIGHT)
	var walled_300 := spawn_walker(sandbox, Vector2(0, 300), Vector2.DOWN)   # wall between: 480 -> 240
	var far_600 := spawn_walker(sandbox, Vector2(-600, 0), Vector2.LEFT)
	p.try_switch(1)
	await physics_frames(15)
	check(p.try_attack(), "pistol fired")
	check_eq(open_300.state, Zombie.State.INVESTIGATE, "zombie 300 px away in the open investigates")
	check(walled_300.state != Zombie.State.INVESTIGATE, "zombie 300 px away behind a wall doesn't hear it")
	check(far_600.state != Zombie.State.INVESTIGATE, "zombie 600 px away doesn't hear it")
	check_near(open_300._move_goal.distance_to(Vector2(0, -7)), 0.0, 1.0, "it heads to where the shot was fired")


func test_far_calm_zombies_go_dormant_and_wake_on_noise() -> void:
	var sandbox := make_sandbox()
	_still_player(sandbox, Vector2(0, 0))
	var z := spawn_walker(sandbox, Vector2(900, 0), Vector2.LEFT, true)
	await physics_frames(70)
	check(z.is_dormant, "zombie 900 px away is dormant")
	check_eq(z.state, Zombie.State.IDLE, "dormant zombies don't wander")
	z.hear_noise(Vector2(850, 0), 200.0, null)
	check(not z.is_dormant, "a noise wakes it")
	check_eq(z.state, Zombie.State.INVESTIGATE, "and it investigates")


func test_test_yard_has_a_navigation_mesh_to_every_area() -> void:
	var yard: Node = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	var nav: NavigationRegion2D = yard.get_node("Navigation")
	var spawn_point: Vector2 = yard.get_node("PlayerSpawn").global_position
	# The navigation server syncs in the background: wait (max 5 s; > 1 s seen under CPU load) until it answers.
	var ready_after := -1
	for f in 300:
		await physics_frames(1)
		var m: RID = (yard as Node2D).get_world_2d().navigation_map
		if not NavigationServer2D.map_get_path(m, spawn_point, Vector2(560, 150), true).is_empty():
			ready_after = f
			break
	check(ready_after >= 0, "navigation map ready within 5 s (took %d frames)" % ready_after)
	check(nav.navigation_polygon.get_polygon_count() > 10, "mesh baked (%d polygons)" % nav.navigation_polygon.get_polygon_count())
	var map: RID = (yard as Node2D).get_world_2d().navigation_map
	var spawn: Vector2 = yard.get_node("PlayerSpawn").global_position
	var dark: DarkZone = yard.get_node("DarkRoom")
	for goal in [dark.global_position + dark.size * 0.5, Vector2(560, 150), Vector2(900, 600)]:
		var path: PackedVector2Array = NavigationServer2D.map_get_path(map, spawn, goal, true)
		check(path.size() > 1 and path[-1].distance_to(goal) < 8.0, "path from the safehouse to %s" % str(goal))
	var near_wall: Vector2 = NavigationServer2D.map_get_closest_point(map, Vector2(33 * 16 + 8, 9 * 16 + 8))
	check(near_wall.x >= 33 * 16 + 16 + 5.5 or near_wall.x <= 33 * 16 - 5.5, "mesh keeps ~6 px away from walls")
	yard.queue_free()


func test_all_six_difficulty_arenas_build_with_navigation() -> void:
	for i in 6:
		var a: Dictionary = ArenaBuilder.build(i)
		add_child(a.root)
		var ok := false
		for f in 300:
			await physics_frames(1)
			var map: RID = (a.root as Node2D).get_world_2d().navigation_map
			var goal: Vector2 = (a.exit as Rect2).get_center() if (a.exit as Rect2).has_area() else a.player_spawn + Vector2(40, 0)
			if not NavigationServer2D.map_get_path(map, a.player_spawn, goal, true).is_empty():
				ok = true
				break
		check(ok, "arena %d has a walkable path from the player's spawn" % (i + 1))
		check(a.walkers.size() >= 1, "arena %d has Walkers" % (i + 1))
		(a.root as Node).queue_free()
		await physics_frames(2)
