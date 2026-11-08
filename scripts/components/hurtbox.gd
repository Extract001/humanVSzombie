class_name Hurtbox
extends Area2D
## "This thing can be hit." Attacks call receive_hit(); the damage goes to the linked
## HealthComponent, and the owner (parent) gets on_hit() for reactions such as knockback.

@export var health: HealthComponent


## knockback: push velocity (pixels/second) to apply. stun_time: extra stun seconds.
func receive_hit(amount: float, source: Node = null, knockback: Vector2 = Vector2.ZERO,
		stun_time: float = 0.0) -> float:
	if health == null:
		push_warning("Hurtbox on %s has no HealthComponent linked." % get_parent())
		return 0.0
	if health.is_dead:
		return 0.0
	var applied: float = health.take_damage(amount, source)
	var body: Node = get_parent()
	if body != null and body.has_method(&"on_hit"):
		body.on_hit(applied, knockback, stun_time, source)
	return applied
