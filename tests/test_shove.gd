extends "res://tests/test_case.gd"
## Quick shove (GDD §5, QA: Phase 2 — Shove).


func test_shove_costs_15_and_is_refused_below_15() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	await physics_frames(2)
	check(p.try_shove(), "shove at full stamina")
	check_near(p.stamina, 85.0, 0.01, "costs 15 stamina")
	await physics_frames(70)
	p.stamina = 14.9
	check(not p.try_shove(), "refused below 15 stamina")
	check_near(p.stamina, 14.9, 0.01, "refused shove costs nothing")


func test_shove_cooldown_is_one_second() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	await physics_frames(2)
	check(p.try_shove(), "first shove")
	await physics_frames(30)  # 0.5 s
	check(not p.try_shove(), "refused at 0.5 s")
	await physics_frames(33)  # 1.05 s
	check(p.try_shove(), "allowed after 1.0 s")


func test_shove_pushes_everyone_in_the_cone_and_nobody_outside() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.aim_direction = Vector2.RIGHT
	var origin := Vector2(0, -7)  # shove starts at chest height
	var inside: Array[Zombie] = []
	for angle in [0.0, 40.0, -40.0]:
		inside.append(spawn_walker(sandbox, origin + Vector2.RIGHT.rotated(deg_to_rad(angle)) * 26.0, Vector2.LEFT))
	var outside: Array[Zombie] = [
		spawn_walker(sandbox, origin + Vector2.LEFT * 24.0, Vector2.RIGHT),              # behind
		spawn_walker(sandbox, origin + Vector2.RIGHT.rotated(deg_to_rad(80.0)) * 26.0, Vector2.UP),  # beyond 60°
		spawn_walker(sandbox, origin + Vector2.RIGHT * 70.0, Vector2.LEFT),              # too far
	]
	for z in inside + outside:
		z.set_physics_process(false)
	await physics_frames(2)
	var before: Array[Vector2] = []
	for z in inside:
		before.append(z.global_position)
	check(p.try_shove(), "shove")
	for z in inside:
		check_eq(z.state, Zombie.State.STUNNED, "zombie in cone staggered")
		check_near(z.health.current_health, 58.0, 0.01, "shove deals 2 damage")
	for z in outside:
		check(z.state != Zombie.State.STUNNED, "zombie outside the cone not affected")
		check_eq(z.health.current_health, 60.0, "no damage outside the cone")
	for z in inside:
		z.set_physics_process(true)
	await physics_frames(20)
	for i in inside.size():
		var moved: float = inside[i].global_position.distance_to(before[i])
		check(moved > 15.0 and moved < 40.0, "pushed about 25 px (moved %.1f)" % moved)


func test_shoved_zombie_cannot_bite_for_stagger_time() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.aim_direction = Vector2.RIGHT
	p.set_physics_process(false)
	var z := spawn_walker(sandbox, Vector2(14, 0), Vector2.LEFT)
	await physics_frames(15)
	check_eq(z.state, Zombie.State.ATTACK, "winding up a bite")
	var bites := [0]
	p.health.damaged.connect(func(_a: float, _s: Node) -> void: bites[0] += 1)
	p._shove_cooldown_left = 0.0
	p.state = Player.State.NORMAL
	check(p.try_shove(), "shove")
	z.global_position = Vector2(14, 0)  # even if it stays adjacent...
	await physics_frames(34)  # 0.57 s
	check_eq(bites[0], 0, "no bite during the 0.6 s stagger")
	check_eq(z.state, Zombie.State.STUNNED, "still staggered just before 0.6 s")


func test_stamina_regeneration_after_shove() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	await physics_frames(2)
	p.stamina = 50.0
	check(p.try_shove(), "shove")
	await physics_frames(54)  # 0.9 s
	check_near(p.stamina, 35.0, 0.01, "no regeneration for 1 s after the shove")
	await physics_frames(66)  # +1.1 s -> ~1.5 s of regen time minus delay
	check(p.stamina > 35.0 + 15.0 * 0.9 and p.stamina < 35.0 + 15.0 * 1.2,
		"then about 15/s (stamina %.2f)" % p.stamina)


func test_shove_during_reload_cancels_reload_without_ammo_change() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.try_switch(1)
	await physics_frames(15)
	p.weapons.rounds_in_mag[1] = 4
	check(p.try_reload(), "reloading")
	await physics_frames(30)
	check(p.try_shove(), "shove allowed during reload")
	check_eq(p.state, Player.State.SHOVING, "SHOVING")
	check(not p.weapons.is_reloading, "reload cancelled")
	check_eq(p.weapons.rounds_in_mag[1], 4, "magazine unchanged")
	check_eq(p.inventory.count(&"ammo_pistol"), 16, "reserve unchanged")


func test_player_still_takes_damage_while_shoving() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	await physics_frames(2)
	p.try_shove()
	check_eq(p.state, Player.State.SHOVING, "SHOVING")
	p.hurtbox.receive_hit(12.0, null)
	check_near(p.health.current_health, 88.0, 0.01, "full damage during shove (no invincibility)")
