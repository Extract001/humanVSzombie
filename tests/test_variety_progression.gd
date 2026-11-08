extends "res://tests/test_case.gd"
## Tests for Shotgun, Brute zombie, Workbench upgrades, and Intro narrative.

const DT: float = 1.0 / 60.0


func _armed_player() -> Player:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	p.set_physics_process(false)
	p.aim_direction = Vector2.RIGHT
	return p


func _advance(p: Player, seconds: float) -> void:
	for i in int(round(seconds * 60.0)):
		p.weapons.tick(DT)


func test_shotgun_data_and_unlock() -> void:
	var sg: WeaponData = load("res://data/weapons/shotgun.tres")
	check(sg != null, "shotgun resource exists")
	check_eq(sg.id, &"shotgun", "id is shotgun")
	check_eq(sg.pellets, 6, "shotgun fires 6 pellets")
	check_eq(sg.ammo_item_id, &"ammo_shotgun", "uses shotgun ammo")
	check(sg.damage >= 15.0, "pellet damage is substantial")

	var p := _armed_player()
	check_eq(p.weapons.slots.size(), 2, "starts with bat and pistol")
	p.unlock_shotgun(false)
	check_eq(p.weapons.slots.size(), 3, "shotgun added as 3rd slot")
	check(GameState.has_unlock(&"weapon_shotgun"), "unlock recorded in GameState")
	check(p.weapons.switch_to(2), "can switch to shotgun slot")
	check_eq(p.weapons.current_weapon().id, &"shotgun", "current weapon is shotgun")


func test_shotgun_firing_uses_shotgun_ammo() -> void:
	var p := _armed_player()
	p.unlock_shotgun(false)
	p.weapons.switch_to(2)
	_advance(p, 0.3)
	p.inventory.add_item(&"ammo_shotgun", 8)
	check_eq(p.weapons.loaded_rounds(), 4, "shotgun starts loaded with 4 shells")
	check_eq(p.inventory.count(&"ammo_shotgun"), 8, "8 shells in reserve")
	check(p.weapons.attack(Vector2.ZERO, Vector2.RIGHT), "fired shotgun")
	check_eq(p.weapons.loaded_rounds(), 3, "magazine 4 -> 3")
	check_eq(p.inventory.count(&"ammo_shotgun"), 8, "reserve untouched by firing")


func test_brute_zombie_stats() -> void:
	var bdata: ZombieData = load("res://data/zombies/brute.tres")
	check(bdata != null, "brute resource exists")
	check_eq(bdata.id, &"brute", "id is brute")
	check(bdata.max_health >= 150.0, "brute has high health (>= 150)")
	check(bdata.shove_resistance >= 0.5, "brute resists shoves")
	check(bdata.bite_damage >= 20.0, "brute deals heavy damage")

	var sb := make_sandbox()
	var z: Zombie = load("res://scenes/zombies/walker.tscn").instantiate()
	z.data = bdata
	sb.add_child(z)
	check_eq(z.health.max_health, bdata.max_health, "zombie health initialized from brute data")
	check_near(z.scale.x, 1.25, 0.05, "brute is scaled larger")


func test_workbench_upgrades_effects() -> void:
	GameState.new_game(99)
	var p := _armed_player()
	p.inventory.add_item(&"scrap", 15)

	check(not GameState.has_upgrade(&"cardio"), "no cardio upgrade initially")
	check(not GameState.has_upgrade(&"thick_skin"), "no thick_skin initially")

	var panel := UpgradesPanel.new()
	add_child(panel)
	panel.bind(p)

	# Craft cardio
	panel._craft({"id": &"cardio", "name": "Cardio", "cost": 3})
	check(GameState.has_upgrade(&"cardio"), "cardio upgrade learned")
	check_eq(p.inventory.count(&"scrap"), 12, "3 scrap deducted")

	# Craft thick_skin
	panel._craft({"id": &"thick_skin", "name": "Thick Skin", "cost": 5})
	check(GameState.has_upgrade(&"thick_skin"), "thick_skin upgrade learned")
	check_eq(p.inventory.count(&"scrap"), 7, "5 scrap deducted")
	check_eq(p.health.max_health, 130.0, "max health increased to 130")

	panel.queue_free()


func test_intro_panel_flow() -> void:
	GameState.new_game(101)
	var intro := IntroPanel.new()
	add_child(intro)
	var p := _armed_player()
	intro.bind(p)

	check(not GameState.has_unlock(&"intro_seen"), "intro not seen initially")
	intro.play_intro()
	check(intro.visible, "intro panel visible while playing")
	intro.close()
	check(not intro.visible, "intro panel hidden after close")
	check(GameState.has_unlock(&"intro_seen"), "intro_seen unlock saved")

	intro.queue_free()
