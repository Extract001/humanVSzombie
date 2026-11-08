class_name Fx
extends RefCounted
## Small one-shot particle effects (blood on hits, dust where a bullet hits a wall).
## CPUParticles2D works in the Compatibility renderer and in the browser. Each burst frees itself.

const BLOOD := Color(0.48, 0.1, 0.09)
const DUST := Color(0.62, 0.58, 0.5)
const SPARK := Color(1.0, 0.86, 0.5)


static func burst(parent: Node, at: Vector2, color: Color, amount: int = 8, speed: float = 50.0,
		direction: Vector2 = Vector2.ZERO, lifetime: float = 0.35) -> CPUParticles2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = direction if direction != Vector2.ZERO else Vector2.UP
	p.spread = 70.0 if direction != Vector2.ZERO else 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 90)
	p.damping_min = 40.0
	p.damping_max = 80.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = color
	p.z_index = 4
	p.global_position = at
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p
