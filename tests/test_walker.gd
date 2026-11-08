extends "res://tests/test_case.gd"
## Walker behaviour simulations (QA: Phase 1 — Walker; sight checks for Phase 3 groundwork).


func test_walker_reaches_player_and_bites_12_at_safe_intervals() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(100, 0))
	p.set_physics_process(false)  # player stands still
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	var bite_frames: Array[int] = []
	var amounts: Array[float] = []
	p.health.damaged.connect(func(amount: float, _src: Node) -> void:
		bite_frames.append(Engine.get_physics_frames())
		amounts.append(amount))
	await physics_frames(60 * 6)  # 6 seconds
	check(bite_frames.size() >= 3, "walker reached the player and bit (bites=%d)" % bite_frames.size())
	for a in amounts:
		check_near(a, 12.0, 0.001, "bite damage")
	for i in range(1, bite_frames.size()):
		var gap: float = (bite_frames[i] - bite_frames[i - 1]) / 60.0
		check(gap >= 1.2 - 0.02, "bite interval %.2f s >= 1.2 s" % gap)
	check_near(p.health.current_health, 100.0 - 12.0 * bite_frames.size(), 0.001, "health matches bites")


func test_walker_chase_speed_is_45() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(150, 0))
	p.set_physics_process(false)
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	await physics_frames(30)
	check_eq(z.state, Zombie.State.CHASE, "chasing")
	check_near(z.velocity.length(), 45.0, 0.5, "chase speed")


func test_walking_player_outpaces_a_walker() -> void:
	# Intentional design (GDD §7): a single Walker can't catch a walking player in the open.
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(60, 0))
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	Input.action_press(&"move_right")
	var bitten := [false]
	p.health.damaged.connect(func(_a: float, _s: Node) -> void: bitten[0] = true)
	await physics_frames(60 * 4)
	check(not bitten[0], "not bitten while walking away")
	check(p.global_position.x - z.global_position.x > 150.0, "gap grows")
	release_all_actions()


func test_walker_cannot_see_through_wall() -> void:
	var sandbox := make_sandbox()
	add_wall(sandbox, Rect2(40, -60, 16, 120))
	var p := spawn_player(sandbox, Vector2(100, 0))
	p.set_physics_process(false)
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	await physics_frames(3)
	check(not z.can_see(p), "wall blocks sight")
	await physics_frames(60)
	check_eq(z.state, Zombie.State.IDLE, "stays idle behind the wall")


func test_walker_cannot_see_behind_itself() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(-80, 0))
	p.set_physics_process(false)
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	await physics_frames(3)
	check(not z.can_see(p), "player behind the view cone is not seen")


func test_walker_senses_player_bumping_from_behind() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(-20, 0))  # within 24 px proximity sense
	p.set_physics_process(false)
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	await physics_frames(3)
	check(z.can_see(p), "very close player is noticed even from behind")


func test_walker_out_of_range_does_not_see() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(170, 0))  # sight range is 160
	p.set_physics_process(false)
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	await physics_frames(3)
	check(not z.can_see(p), "beyond 160 px")


func test_walker_searches_then_gives_up_after_losing_sight() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(100, 0))
	p.set_physics_process(false)
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	await physics_frames(20)
	check_eq(z.state, Zombie.State.CHASE, "chasing first")
	# Player "disappears" behind a new wall.
	add_wall(sandbox, Rect2(z.global_position.x + 12, -80, 8, 160))
	p.global_position = Vector2(z.global_position.x + 60, 0)
	await physics_frames(20)
	check_eq(z.state, Zombie.State.SEARCH, "searching last known position")
	await physics_frames(60 * 8)
	check_eq(z.state, Zombie.State.IDLE, "gives up after the search duration")


func test_walker_stops_attacking_dead_player() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(14, 0))
	p.set_physics_process(false)
	var z := spawn_walker(sandbox, Vector2(0, 0), Vector2.RIGHT)
	p.health.take_damage(95.0)
	await physics_frames(60 * 3)
	check(p.is_dead(), "player died")
	var hits := [0]
	p.health.damaged.connect(func(_a: float, _s: Node) -> void: hits[0] += 1)
	await physics_frames(60 * 2)
	check_eq(hits[0], 0, "no damage after death")
	check(z.state != Zombie.State.ATTACK and z.state != Zombie.State.CHASE, "walker stopped")


func test_damage_applies_in_every_living_state() -> void:
	# No invincibility (TECHNICAL_ARCHITECTURE §4.3). Phase 1 only enters NORMAL/DEAD,
	# but forcing each declared state proves damage never depends on state.
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.set_physics_process(false)
	for s in [Player.State.NORMAL, Player.State.ATTACKING, Player.State.RELOADING,
			Player.State.SHOVING, Player.State.HURT]:
		p.state = s
		var before: float = p.health.current_health
		p.hurtbox.receive_hit(5.0, null)
		check_near(p.health.current_health, before - 5.0, 0.001,
			"damage applied in state %s" % Player.State.keys()[s])
	p.state = Player.State.NORMAL
	p.health.take_damage(1000.0)
	check_eq(p.state, Player.State.DEAD, "enters DEAD at 0 health")
