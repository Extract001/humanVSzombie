@tool
class_name Barricade
extends StaticBody2D
## A boarded-up window of the safehouse (Slice 1, night siege). The node's position is the
## top-left of the 1-tile window gap in the wall.
##
## Planks: 0..max_planks, all planks share one health pool (GameState.barricades[id]).
## - Any planks left: blocks player and zombie bodies (physics layer 6 "barricades"), but NOT
##   bullets, sight or light: you can shoot and swing through the gaps, and Walkers can see
##   and reach through to bite you.
## - 0 planks: the window is open; anyone can climb through.
## Walkers pushing against it hit it (zombie.gd). The player nails planks with E (costs scrap).
## Navigation: the window is cut out of the walkable mesh (a nav-only blocker on physics layer 7)
## and bridged by a NavigationLink2D on navigation layer 2, which only zombies use. So Walkers
## path through windows (and hit the boards), while ordinary paths go round to the door.

signal broken
signal changed

const TILE: int = 16
const THICKNESS: float = 6.0
const LAYER: int = 32  # physics layer 6 "barricades"
const SIEGE: SiegeData = preload("res://data/siege/siege_data.tres")

@export var barricade_id: StringName = &""
## Vertical = the window is in a west/east wall (planks run up and down).
@export var vertical: bool = false:
	set(v):
		vertical = v
		_rebuild()

var _shape: CollisionShape2D
var _visual: Node2D
var _interact: Interactable
var _hit_flash: float = 0.0


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	_shape = $Shape
	_visual = $Visual
	_interact = $Interact
	_rebuild()
	if Engine.is_editor_hint():
		return
	add_to_group(&"barricades")
	_add_navigation()
	_interact.prompt_provider = get_prompt
	_interact.interacted.connect(_on_interacted)
	_visual.draw.connect(_draw_planks)
	refresh()


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(&"nav_source")   # before the deferred navigation bake


func _add_navigation() -> void:
	var block := StaticBody2D.new()
	block.name = "NavBlock"
	block.collision_layer = NavigationBaker.NAV_ONLY_LAYER
	block.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = span()
	cs.shape = rect
	cs.position = span() * 0.5
	block.add_child(cs)
	add_child(block)
	var across: Vector2 = Vector2.RIGHT if vertical else Vector2.DOWN
	var link := NavigationLink2D.new()
	link.name = "WindowLink"
	link.bidirectional = true
	link.navigation_layers = NavigationBaker.WINDOW_NAV_LAYER
	link.start_position = span() * 0.5 - across * 15.0
	link.end_position = span() * 0.5 + across * 15.0
	add_child(link)


func span() -> Vector2:
	return Vector2(TILE, TILE)


func center() -> Vector2:
	return global_position + span() * 0.5


func health() -> float:
	if not GameState.barricades.has(barricade_id):
		GameState.barricades[barricade_id] = SIEGE.start_planks * SIEGE.plank_health
	return float(GameState.barricades[barricade_id])


func planks() -> int:
	return int(ceil(health() / SIEGE.plank_health - 0.001))


func is_broken() -> bool:
	return health() <= 0.0


## A Walker's hit. Returns true if this hit broke the last plank.
func take_hit(amount: float, attacker: Node = null) -> bool:
	if is_broken():
		return false
	GameState.barricades[barricade_id] = maxf(0.0, health() - amount)
	_hit_flash = 0.25
	AudioManager.play_at(preload("res://assets/audio/sfx/barricade_hit.wav"), center(), -2.0, 0.1)
	Fx.burst(get_parent(), center(), Color(0.55, 0.39, 0.22), 4, 40.0, Vector2.ZERO)  # splinters
	if GameState.has_upgrade(&"spikes") and attacker != null and attacker.has_node("Health"):
		(attacker.get_node("Health") as HealthComponent).take_damage(15.0)
	refresh()
	if is_broken():
		AudioManager.play_at(preload("res://assets/audio/sfx/barricade_break.wav"), center(), 0.0)
		broken.emit()
		return true
	return false


## Nails one more plank (no cost check: callers pay). Returns false if already full.
func add_plank() -> bool:
	if planks() >= SIEGE.max_planks:
		return false
	# A new plank also tops the damaged one up: health = (planks + 1) full planks.
	GameState.barricades[barricade_id] = float(mini(planks() + 1, SIEGE.max_planks)) * SIEGE.plank_health
	refresh()
	return true


func set_planks(n: int) -> void:
	GameState.barricades[barricade_id] = float(clampi(n, 0, SIEGE.max_planks)) * SIEGE.plank_health
	refresh()


func refresh() -> void:
	if _shape == null:
		return
	_shape.set_deferred("disabled", is_broken())
	if _visual != null:
		_visual.queue_redraw()
	changed.emit()


func get_prompt() -> String:
	var n: int = planks()
	if n >= SIEGE.max_planks:
		return "Window boarded up (%d/%d)" % [n, SIEGE.max_planks]
	return "Board up window: %d scrap (%d/%d)" % [SIEGE.plank_cost, n, SIEGE.max_planks]


func _on_interacted(by: Node) -> void:
	var p := by as Player
	if p == null:
		return
	if planks() >= SIEGE.max_planks:
		p.message.emit("This window is fully boarded")
		return
	if p.inventory.count(&"scrap") < SIEGE.plank_cost:
		p.message.emit("You need scrap to board it up")
		return
	p.start_work(SIEGE.plank_build_time, "BOARDING UP...", func() -> void: _finish_plank(p))
	AudioManager.play_at(preload("res://assets/audio/sfx/barricade_build.wav"), center(), -3.0, 0.05)


func _finish_plank(p: Player) -> void:
	if p.inventory.count(&"scrap") < SIEGE.plank_cost or planks() >= SIEGE.max_planks:
		return
	p.inventory.remove_item(&"scrap", SIEGE.plank_cost)
	add_plank()
	NoiseSystem.emit_noise(center(), SIEGE.plank_noise_radius, p)
	AudioManager.play_at(preload("res://assets/audio/sfx/barricade_build.wav"), center(), 0.0, 0.05)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _hit_flash <= 0.0:
		return
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_visual.queue_redraw()


func _rebuild() -> void:
	if _shape == null:
		return
	var s: Vector2 = span()
	var c: Vector2 = s * 0.5
	var rect := RectangleShape2D.new()
	rect.size = Vector2(THICKNESS, s.y) if vertical else Vector2(s.x, THICKNESS)
	_shape.shape = rect
	_shape.position = c
	var area_shape := _interact.get_node("Shape") as CollisionShape2D
	var reach := RectangleShape2D.new()
	reach.size = s + (Vector2(28, 0) if vertical else Vector2(0, 28))
	area_shape.shape = reach
	area_shape.position = c
	if _visual != null:
		_visual.queue_redraw()


## Window frame + planks across it; cracks show as darker, shorter planks.
func _draw_planks() -> void:
	var s: Vector2 = span()
	var frame := Color(0.16, 0.13, 0.11)
	var glass := Color(0.22, 0.28, 0.33)
	var sill: Rect2 = Rect2(s.x * 0.5 - THICKNESS * 0.5, 0, THICKNESS, s.y) if vertical \
		else Rect2(0, s.y * 0.5 - THICKNESS * 0.5, s.x, THICKNESS)
	_visual.draw_rect(sill, frame)
	_visual.draw_rect(sill.grow(-1.0), glass if not is_broken() else Color(0.08, 0.07, 0.07))
	var n: int = planks()
	if Engine.is_editor_hint():
		n = 1
	var frac: float = 1.0
	if not Engine.is_editor_hint() and n > 0:
		frac = (health() - (n - 1) * SIEGE.plank_health) / SIEGE.plank_health
	var wood := Color(0.55, 0.39, 0.22).lerp(Color(1, 0.9, 0.8), _hit_flash * 2.0)
	for i in n:
		var damaged: bool = i == n - 1 and frac < 0.99
		var len: float = (s.y if vertical else s.x) + 4.0
		if damaged:
			len *= 0.55 + 0.45 * frac
		var offset: float = (float(i) - (SIEGE.max_planks - 1) * 0.5) * 4.0
		var col: Color = wood.darkened(0.25 if damaged else (0.08 * i))
		var r: Rect2
		if vertical:
			r = Rect2(s.x * 0.5 + offset - 1.5, (s.y - len) * 0.5, 3.0, len)
		else:
			r = Rect2((s.x - len) * 0.5, s.y * 0.5 + offset - 1.5, len, 3.0)
		_visual.draw_rect(r, col)
		_visual.draw_rect(r, col.darkened(0.4), false, 1.0)
