extends "res://tests/test_case.gd"
## Ammo rules (QA: Phase 2 — Weapons & ammo). Starting loadout: [1] bat, [2] pistol 8 + 16 reserve.

const DT: float = 1.0 / 60.0


func _armed_player() -> Player:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.set_physics_process(false)  # tests drive time with weapons.tick()
	p.aim_direction = Vector2.RIGHT
	return p


func _advance(p: Player, seconds: float) -> void:
	for i in int(round(seconds * 60.0)):
		p.weapons.tick(DT)


func _total_pistol_ammo(p: Player) -> int:
	return p.weapons.rounds_in_mag[1] + p.inventory.count(&"ammo_pistol")


func test_starting_loadout() -> void:
	var p := _armed_player()
	check_eq(p.weapons.slots.size(), 2, "two weapons")
	check_eq(p.weapons.current_weapon().id, &"bat", "starts with the bat in slot 1")
	check_eq(p.weapons.rounds_in_mag[1], 8, "pistol loaded with 8")
	check_eq(p.inventory.count(&"ammo_pistol"), 16, "16 reserve rounds")


func test_firing_uses_exactly_one_round() -> void:
	var p := _armed_player()
	p.weapons.switch_to(1)
	_advance(p, 0.3)
	check(p.weapons.attack(Vector2.ZERO, Vector2.RIGHT), "shot fired")
	check_eq(p.weapons.loaded_rounds(), 7, "magazine 8 -> 7")
	check_eq(p.inventory.count(&"ammo_pistol"), 16, "reserve untouched by firing")
	check(not p.weapons.attack(Vector2.ZERO, Vector2.RIGHT), "second shot blocked by fire-rate cooldown")
	check_eq(p.weapons.loaded_rounds(), 7, "no round used by the blocked shot")


func test_cannot_fire_empty_magazine() -> void:
	var p := _armed_player()
	p.weapons.switch_to(1)
	p.weapons.rounds_in_mag[1] = 0
	p.inventory.remove_item(&"ammo_pistol", 999)
	_advance(p, 0.3)
	var dry := [0]
	p.weapons.dry_fired.connect(func() -> void: dry[0] += 1)
	check(not p.weapons.attack(Vector2.ZERO, Vector2.RIGHT), "empty pistol does not fire")
	check_eq(p.weapons.loaded_rounds(), 0, "magazine stays 0 (never negative)")
	check_eq(dry[0], 1, "dry-fire click")


func test_reload_with_no_reserve_does_nothing() -> void:
	var p := _armed_player()
	p.weapons.switch_to(1)
	p.weapons.rounds_in_mag[1] = 3
	p.inventory.remove_item(&"ammo_pistol", 999)
	check(not p.weapons.start_reload(), "reload refused")
	check_eq(p.weapons.loaded_rounds(), 3, "magazine unchanged")


func test_reload_refused_when_full_or_melee() -> void:
	var p := _armed_player()
	check(not p.weapons.start_reload(), "bat can't reload")
	p.weapons.switch_to(1)
	check(not p.weapons.start_reload(), "full magazine can't reload")


func test_reload_is_atomic() -> void:
	var p := _armed_player()
	p.weapons.switch_to(1)
	p.weapons.rounds_in_mag[1] = 2
	var total_before: int = _total_pistol_ammo(p)
	check(p.weapons.start_reload(), "reload starts")
	_advance(p, 0.6)  # halfway through the 1.2 s reload
	check_eq(p.weapons.loaded_rounds(), 2, "nothing moved mid-reload")
	check_eq(p.inventory.count(&"ammo_pistol"), 16, "reserve untouched mid-reload")
	_advance(p, 0.7)
	check(not p.weapons.is_reloading, "reload finished")
	check_eq(p.weapons.loaded_rounds(), 8, "magazine full")
	check_eq(p.inventory.count(&"ammo_pistol"), 10, "6 rounds taken from reserve")
	check_eq(_total_pistol_ammo(p), total_before, "total ammo conserved")


func test_partial_reload_with_small_reserve() -> void:
	var p := _armed_player()
	p.weapons.switch_to(1)
	p.weapons.rounds_in_mag[1] = 1
	p.inventory.remove_item(&"ammo_pistol", 13)  # 3 left
	p.weapons.start_reload()
	_advance(p, 1.3)
	check_eq(p.weapons.loaded_rounds(), 4, "1 + 3 loaded")
	check_eq(p.inventory.count(&"ammo_pistol"), 0, "reserve emptied, never negative")


func test_cancelled_reload_moves_nothing() -> void:
	var p := _armed_player()
	p.weapons.switch_to(1)
	p.weapons.rounds_in_mag[1] = 5
	p.weapons.start_reload()
	_advance(p, 1.0)
	p.weapons.switch_to(0)  # switching cancels
	_advance(p, 1.0)
	check(not p.weapons.is_reloading, "reload cancelled")
	check_eq(p.weapons.rounds_in_mag[1], 5, "magazine unchanged")
	check_eq(p.inventory.count(&"ammo_pistol"), 16, "reserve unchanged")


func test_each_weapon_keeps_its_magazine_when_switching() -> void:
	var p := _armed_player()
	p.weapons.switch_to(1)
	_advance(p, 0.3)
	p.weapons.attack(Vector2.ZERO, Vector2.RIGHT)
	_advance(p, 0.4)
	p.weapons.attack(Vector2.ZERO, Vector2.RIGHT)
	check_eq(p.weapons.loaded_rounds(), 6, "two shots fired")
	p.weapons.switch_to(0)
	_advance(p, 0.5)
	p.weapons.switch_to(1)
	check_eq(p.weapons.loaded_rounds(), 6, "pistol still has 6 after switching away and back")
	check_eq(p.inventory.count(&"ammo_pistol"), 16, "switching never moves ammo")


func test_ammo_conserved_over_1000_random_action_sequences() -> void:
	var p := _armed_player()
	var fired := [0]
	p.weapons.attacked.connect(func(_o: Vector2, w: WeaponData) -> void:
		if w.uses_ammo():
			fired[0] += 1)
	var total: int = _total_pistol_ammo(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261108
	for step in 1000:
		match rng.randi_range(0, 5):
			0, 1:
				p.weapons.attack(Vector2.ZERO, Vector2.RIGHT)
			2:
				p.weapons.start_reload()
			3:
				p.weapons.switch_to(rng.randi_range(0, 1))
			4:
				p.weapons.cancel_reload()
			5:
				p.inventory.add_item(&"ammo_pistol", 0)  # no-op "noise"
		_advance(p, rng.randf_range(0.0, 0.5))
		var now: int = _total_pistol_ammo(p) + fired[0]
		if now != total:
			check(false, "ammo invariant broken at step %d: %d != %d" % [step, now, total])
			return
		if p.weapons.rounds_in_mag[1] < 0 or p.weapons.rounds_in_mag[1] > 8:
			check(false, "magazine out of range at step %d" % step)
			return
	check(fired[0] > 0, "the sequence actually fired shots (%d)" % fired[0])
