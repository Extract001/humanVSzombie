extends Node2D
## Shows the player's noises as rings in the world (GDD §8: "cause and effect are learnable").
## A ring grows to the noise radius, then fades. Quiet noises (running, searching) get a faint ring,
## loud ones (gunshots) a strong ring. Only noises the player makes are shown; small ones (< 55 px)
## such as a shove are skipped. Drawn unshaded, so rings stay visible inside dark interiors.

const MIN_RADIUS: float = 55.0
const STRONG_RADIUS: float = 200.0
const GROW_TIME: float = 0.35
const FADE_TIME: float = 0.6
const MAX_RINGS: int = 16

## Each ring: {"pos": Vector2, "radius": float, "age": float}
var rings: Array[Dictionary] = []


func _ready() -> void:
	z_index = 50
	light_mask = 0
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	NoiseSystem.noise_emitted.connect(_on_noise)


func _on_noise(pos: Vector2, radius: float, source: Node) -> void:
	if radius < MIN_RADIUS or not (source is Player):
		return
	if rings.size() >= MAX_RINGS:
		rings.pop_front()
	rings.append({"pos": pos, "radius": radius, "age": 0.0})
	queue_redraw()


func _process(delta: float) -> void:
	if rings.is_empty():
		return
	for r in rings:
		r.age += delta
	rings = rings.filter(func(r: Dictionary) -> bool: return r.age < GROW_TIME + FADE_TIME)
	queue_redraw()


func _draw() -> void:
	for r in rings:
		var strong: bool = r.radius >= STRONG_RADIUS
		var grow: float = clampf(r.age / GROW_TIME, 0.0, 1.0)
		var size: float = r.radius * (1.0 - pow(1.0 - grow, 2.0))
		var fade: float = 1.0 - clampf((r.age - GROW_TIME) / FADE_TIME, 0.0, 1.0)
		var alpha: float = (0.55 if strong else 0.22) * fade
		var color := Color(1.0, 0.9, 0.6, alpha) if strong else Color(0.85, 0.9, 1.0, alpha)
		draw_arc(r.pos, size, 0.0, TAU, 64 if strong else 40, color, 2.0 if strong else 1.0)
