extends "res://tests/test_case.gd"
## Stamina rules (GDD §5, QA: Phase 1 — Movement & stamina).
## Drives Player.update_stamina() directly with fixed 1/60 s steps.

const DT: float = 1.0 / 60.0


func _player() -> Player:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(100, 100))
	p.set_physics_process(false)  # we drive stamina manually
	return p


func _steps(p: Player, seconds: float, wants_run: bool, moving: bool) -> void:
	for i in int(round(seconds * 60.0)):
		p.update_stamina(DT, wants_run, moving)


func test_running_drains_20_per_second() -> void:
	var p := _player()
	_steps(p, 0.5, true, true)
	check(p.is_running, "running while Shift held and moving")
	check_near(p.stamina, 90.0, 0.05, "stamina after 0.5 s of running")


func test_no_drain_when_standing_still() -> void:
	var p := _player()
	_steps(p, 1.0, true, false)
	check(not p.is_running, "holding Shift without moving is not running")
	check_near(p.stamina, 100.0, 0.001, "no drain while still")


func test_minimum_stamina_to_start_running() -> void:
	var p := _player()
	p.stamina = 9.9
	p.update_stamina(DT, true, true)
	check(not p.is_running, "cannot START running below 10 stamina")
	p.stamina = 10.0
	p.update_stamina(DT, true, true)
	check(p.is_running, "can start running at exactly 10 stamina")


func test_runs_to_zero_then_cannot_restart_below_minimum() -> void:
	var p := _player()
	p.stamina = 12.0
	_steps(p, 1.0, true, true)  # 12 stamina lasts 0.6 s
	check_near(p.stamina, 0.0, 0.001, "stamina reaches 0")
	check(not p.is_running, "running stops at 0 stamina")
	# Stamina hit 0 at t = 0.6 s. Holding Shift: regen starts at t = 1.6 s and reaches
	# 10 at t ≈ 2.27 s (10 / 15 per second). We're at t = 1.0 s now.
	_steps(p, 1.1, true, true)  # t = 2.1 s
	check(not p.is_running, "still walking while below 10 (stamina %.2f)" % p.stamina)
	check(p.stamina > 0.0 and p.stamina < 10.0, "regenerating but below 10")
	_steps(p, 0.3, true, true)  # t = 2.4 s
	check(p.is_running, "running resumes once stamina reaches 10")


func test_regeneration_waits_one_second_then_15_per_second() -> void:
	var p := _player()
	p.stamina = 50.0
	_steps(p, 0.1, true, true)  # run briefly -> 48
	var after_run: float = p.stamina
	_steps(p, 0.95, false, true)
	check_near(p.stamina, after_run, 0.001, "no regeneration during the 1 s delay")
	_steps(p, 0.05, false, true)  # delay over
	_steps(p, 1.0, false, true)
	check_near(p.stamina, after_run + 15.0, 0.3, "15 stamina regenerated in the following second")


func test_stamina_stays_within_bounds() -> void:
	var p := _player()
	_steps(p, 10.0, false, false)
	check(p.stamina <= p.stats.max_stamina, "never above max")
	_steps(p, 10.0, true, true)
	check(p.stamina >= 0.0, "never below 0")


func test_spend_stamina_restarts_regen_delay() -> void:
	# Used by the shove in Phase 2: spending stamina must also delay regeneration.
	var p := _player()
	check(p.spend_stamina(15.0), "spend succeeds with enough stamina")
	check_near(p.stamina, 85.0, 0.001, "stamina after spending 15")
	_steps(p, 0.9, false, false)
	check_near(p.stamina, 85.0, 0.001, "no regeneration within 1 s of spending")
	p.stamina = 5.0
	check(not p.spend_stamina(15.0), "spend refused when not enough stamina")
	check_near(p.stamina, 5.0, 0.001, "refused spend changes nothing")
