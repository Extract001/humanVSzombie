class_name HealthComponent
extends Node
## Reusable health for the player and zombies.
## Damage does NOT depend on the owner's state: only death stops it (no invincibility frames).

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal died

@export var max_health: float = 100.0

var current_health: float = 100.0
var is_dead: bool = false


func _ready() -> void:
	current_health = max_health


## Sets a new maximum and refills. Call before gameplay starts or on respawn.
func setup(new_max: float, start_health: float = -1.0) -> void:
	max_health = new_max
	current_health = new_max if start_health < 0.0 else clampf(start_health, 0.0, new_max)
	is_dead = current_health <= 0.0
	health_changed.emit(current_health, max_health)


## Returns the damage actually applied (0 when already dead or amount <= 0).
func take_damage(amount: float, source: Node = null) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var applied: float = minf(amount, current_health)
	current_health -= applied
	damaged.emit(applied, source)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		current_health = 0.0
		is_dead = true
		died.emit()
	return applied


## Returns the health actually restored.
func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var restored: float = minf(amount, max_health - current_health)
	current_health += restored
	health_changed.emit(current_health, max_health)
	return restored
