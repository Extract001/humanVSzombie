extends "res://tests/test_case.gd"
## Combat simulations with real physics (QA: Phase 2 — Player states, Weapons & ammo).


func _setup(player_pos: Vector2, zombie_pos: Vector2, zombie_facing: Vector2) -> Array:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, player_pos)
	p.aim_direction = player_pos.direction_to(zombie_pos)
	var z := spawn_walker(sandbox, zombie_pos, zombie_facing)
	return [sandbox, p, z]


func _equip_pistol(p: Player) -> void:
	p.try_switch(1)
	await physics_frames(15)


func test_pistol_two_shots_kill_a_walker() -> void:
	var s := _setup(Vector2(0, 0), Vector2(60, 0), Vector2.UP)
	var p: Player = s[1]
	var z: Zombie = s[2]
	z.set_physics_process(false)  # stand still
	await _equip_pistol(p)
	check(p.try_attack(), "first shot")
	await physics_frames(25)
	check_near(z.health.current_health, 26.0, 0.01, "60 - 34 = 26 after one shot")
	check(p.try_attack(), "second shot")
	await physics_frames(5)
	check(z.health.is_dead, "dead after two pistol shots")
	check_eq(z.state, Zombie.State.DEAD, "DEAD state")


func test_bat_three_hits_kill_a_walker() -> void:
	var s := _setup(Vector2(0, 0), Vector2(20, 0), Vector2.UP)
	var p: Player = s[1]
	var z: Zombie = s[2]
	z.set_physics_process(false)
	var deaths := [0]
	z.died.connect(func() -> void: deaths[0] += 1)
	for i in 3:
		z.global_position = Vector2(20, 0)  # undo knockback between swings
		check(p.try_attack(), "swing %d" % (i + 1))
		await physics_frames(40)
	check(z.health.is_dead, "dead after 3 bat hits (hp %.0f)" % z.health.current_health)
	check_eq(deaths[0], 1, "died exactly once")
	p.try_attack()
	await physics_frames(40)
	check_eq(deaths[0], 1, "hitting a corpse doesn't count another kill")


func test_bat_misses_targets_behind_or_out_of_range() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.aim_direction = Vector2.RIGHT
	var behind := spawn_walker(sandbox, Vector2(-20, 0), Vector2.UP)
	var far := spawn_walker(sandbox, Vector2(60, 0), Vector2.UP)
	for z in [behind, far]:
		z.set_physics_process(false)
	await physics_frames(2)
	p.try_attack()
	await physics_frames(30)
	check_eq(behind.health.current_health, 60.0, "zombie behind is not hit")
	check_eq(far.health.current_health, 60.0, "zombie 60 px away is not hit")


func test_attacks_do_not_go_through_walls() -> void:
	var sandbox := make_sandbox()
	add_wall(sandbox, Rect2(30, -40, 6, 80))
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.aim_direction = Vector2.RIGHT
	var z := spawn_walker(sandbox, Vector2(80, 0), Vector2.UP)
	z.set_physics_process(false)
	await _equip_pistol(p)
	p.try_attack()
	await physics_frames(5)
	check_eq(z.health.current_health, 60.0, "bullet stopped by the wall")
	# Melee through a thin wall
	var sandbox2 := make_sandbox()
	add_wall(sandbox2, Rect2(110, -40, 4, 80))
	var p2 := spawn_player(sandbox2, Vector2(100, 200))
	p2.global_position = Vector2(100, 0)
	p2.aim_direction = Vector2.RIGHT
	var z2 := spawn_walker(sandbox2, Vector2(122, 0), Vector2.UP)
	z2.set_physics_process(false)
	await physics_frames(3)
	p2.try_attack()
	await physics_frames(30)
	check_eq(z2.health.current_health, 60.0, "bat stopped by the wall")


func test_hit_interrupts_bite_windup_and_knocks_back() -> void:
	var s := _setup(Vector2(0, 0), Vector2(16, 0), Vector2.LEFT)
	var p: Player = s[1]
	var z: Zombie = s[2]
	p.set_physics_process(false)
	await physics_frames(20)
	check_eq(z.state, Zombie.State.ATTACK, "walker winding up a bite")
	var start_x: float = z.global_position.x
	var hits := [0]
	p.health.damaged.connect(func(_a: float, _s: Node) -> void: hits[0] += 1)
	z.hurtbox.receive_hit(10.0, p, Vector2.RIGHT * 120.0, 0.0)
	check_eq(z.state, Zombie.State.STUNNED, "hit stuns")
	await physics_frames(20)
	check(z.global_position.x > start_x + 5.0, "knocked back (moved %.1f px)" % (z.global_position.x - start_x))
	check_eq(hits[0], 0, "interrupted bite never landed")


func test_illegal_transitions_are_refused() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.aim_direction = Vector2.RIGHT
	await physics_frames(2)
	check(p.try_attack(), "bat swing")
	check_eq(p.state, Player.State.ATTACKING, "ATTACKING")
	check(not p.try_shove(), "no shove while ATTACKING")
	check(not p.try_reload(), "no reload while ATTACKING")
	check(not p.try_switch(1), "no switching while ATTACKING")
	check(not p.try_attack(), "no second attack while ATTACKING")
	await physics_frames(30)
	check_eq(p.state, Player.State.NORMAL, "back to NORMAL after the swing")
	check(p.try_switch(1), "switch to pistol")
	await physics_frames(15)
	p.weapons.rounds_in_mag[1] = 3
	check(p.try_reload(), "reload")
	check_eq(p.state, Player.State.RELOADING, "RELOADING")
	check(not p.try_attack(), "no firing while RELOADING")
	check(p.try_switch(0), "switching during reload is allowed")
	check_eq(p.state, Player.State.NORMAL, "switch cancels reload -> NORMAL")
	check_eq(p.weapons.rounds_in_mag[1], 3, "cancelled reload moved no ammo")


func test_empty_attack_starts_reload() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	await _equip_pistol(p)
	p.weapons.rounds_in_mag[1] = 0
	check(p.try_attack(), "attack accepted")
	check_eq(p.state, Player.State.RELOADING, "empty pistol auto-reloads")
	await physics_frames(80)
	check_eq(p.weapons.loaded_rounds(), 8, "reloaded")
	check_eq(p.state, Player.State.NORMAL, "back to NORMAL")


func test_fire_rate_cannot_be_exceeded_by_spamming() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	await _equip_pistol(p)
	var shots := [0]
	p.weapons.attacked.connect(func(_o: Vector2, _w: WeaponData) -> void: shots[0] += 1)
	for frame in 60:  # click every frame for 1 second
		p.try_attack()
		await physics_frames(1)
	check(shots[0] <= 3, "at most 3 shots in 1 s (got %d)" % shots[0])
	check(shots[0] >= 2, "but it does fire repeatedly (got %d)" % shots[0])


func test_light_bites_never_cause_hurt_but_heavy_hits_do() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	await physics_frames(2)
	p.hurtbox.receive_hit(12.0, null)
	check_eq(p.state, Player.State.NORMAL, "a Walker-strength hit doesn't stun")
	await _equip_pistol(p)
	p.weapons.rounds_in_mag[1] = 2
	p.try_reload()
	p.hurtbox.receive_hit(30.0, null)
	check_eq(p.state, Player.State.HURT, "heavy hit -> HURT")
	check(not p.weapons.is_reloading, "HURT cancels the reload")
	check_eq(p.weapons.rounds_in_mag[1], 2, "no ammo moved")
	await physics_frames(20)
	check_eq(p.state, Player.State.NORMAL, "HURT lasts 0.3 s")


func test_kill_counted_once_by_game() -> void:
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(3)
	var z: Zombie = get_tree().get_nodes_in_group(&"zombies")[0]
	z.hurtbox.receive_hit(1000.0, null)
	z.hurtbox.receive_hit(1000.0, null)
	await physics_frames(2)
	check_eq(game.kills, 1, "one kill counted")
	check_eq(game.get_node("HUD").get_node("%KillsLabel").text, "KILLS 1", "HUD shows kills")
	game.queue_free()


func test_combat_actions_request_their_sounds() -> void:
	var heard: Array[String] = []
	var record := func(stream: AudioStream, _pos: Vector2) -> void: heard.append(stream.resource_path.get_file())
	AudioManager.sound_requested.connect(record)
	var s := _setup(Vector2(0, 0), Vector2(60, 0), Vector2.UP)
	var p: Player = s[1]
	var z: Zombie = s[2]
	z.set_physics_process(false)
	await physics_frames(2)
	p.try_attack()  # bat swing (nothing in reach)
	await physics_frames(40)
	p.try_shove()
	await physics_frames(70)
	await _equip_pistol(p)
	p.try_attack()  # pistol hits the zombie
	await physics_frames(25)
	p.try_attack()  # second shot kills it
	await physics_frames(25)
	p.weapons.rounds_in_mag[1] = 0
	p.inventory.remove_item(&"ammo_pistol", 999)
	p.try_attack()  # dry fire
	await physics_frames(5)
	AudioManager.sound_requested.disconnect(record)
	for expected in ["bat_swing.wav", "shove.wav", "pistol_shot.wav", "flesh_hit.wav",
			"zombie_death.wav", "dry_fire.wav"]:
		check(heard.has(expected), "sound requested: " + expected)


func test_dead_zombie_stays_visible_as_a_corpse() -> void:
	# Regression: corpses were drawn below the ground tiles (z_index -1) and disappeared.
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(3)
	var ground: TileMapLayer = game.get_node("World/Map/Ground")
	var z: Zombie = get_tree().get_nodes_in_group(&"zombies")[0]
	z.hurtbox.receive_hit(1000.0, null)
	await physics_frames(30)
	check(z.is_inside_tree() and z.visible and z.sprite.visible, "corpse still in the world and visible")
	check(z.z_index >= ground.z_index, "corpse drawn above the ground (z %d vs %d)" % [z.z_index, ground.z_index])
	check(z.sprite.modulate.a > 0.5, "corpse not faded out")
	check_eq(z.collision_layer, 0, "corpse no longer blocks movement")
	check_eq(z.hurtbox.collision_layer, 0, "corpse can't be hit again")
	game.queue_free()
