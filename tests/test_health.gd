extends "res://tests/test_case.gd"
## HealthComponent rules (QA: Phase 1 — Health & death).


func _make(max_hp: float) -> HealthComponent:
	var h := HealthComponent.new()
	add_child(h)
	h.setup(max_hp)
	return h


func test_damage_reduces_health() -> void:
	var h := _make(100.0)
	check_eq(h.take_damage(12.0), 12.0, "applied damage")
	check_near(h.current_health, 88.0, 0.001, "health after one bite")


func test_health_clamps_to_zero_and_max() -> void:
	var h := _make(100.0)
	check_eq(h.take_damage(250.0), 100.0, "overkill applies only remaining health")
	check_eq(h.current_health, 0.0, "health never negative")
	var h2 := _make(100.0)
	h2.take_damage(10.0)
	check_eq(h2.heal(50.0), 10.0, "heal restores only up to max")
	check_eq(h2.current_health, 100.0, "health never above max")


func test_died_fires_exactly_once() -> void:
	var h := _make(30.0)
	var count := [0]
	h.died.connect(func() -> void: count[0] += 1)
	h.take_damage(20.0)
	h.take_damage(20.0)
	h.take_damage(20.0)
	check_eq(count[0], 1, "died signal count")
	check(h.is_dead, "is_dead set")


func test_no_damage_or_heal_after_death() -> void:
	var h := _make(10.0)
	h.take_damage(10.0)
	check_eq(h.take_damage(5.0), 0.0, "no damage after death")
	check_eq(h.heal(5.0), 0.0, "no healing after death")


func test_zero_or_negative_damage_ignored() -> void:
	var h := _make(50.0)
	check_eq(h.take_damage(0.0), 0.0, "zero damage")
	check_eq(h.take_damage(-5.0), 0.0, "negative damage does not heal")
	check_eq(h.current_health, 50.0, "unchanged")
