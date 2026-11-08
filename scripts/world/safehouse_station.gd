@tool
class_name SafehouseStation
extends StaticBody2D
## Safehouse furniture you can use with E: stash, bed, radio desk, objective board.
## The station only reports "used"; game.gd decides what happens (opens the stash panel, sleeps, ...).

signal used(station: SafehouseStation, by: Node)

enum Kind { STASH, BED, RADIO, BOARD }

const PROMPTS: Array[String] = ["Open stash", "Sleep", "Use radio", "Read objectives"]
## Body size per kind (px). The board hangs on the wall, so it has no body.
const SIZES: Array[Vector2] = [Vector2(28, 14), Vector2(14, 28), Vector2(30, 12), Vector2.ZERO]

@export var kind: Kind = Kind.STASH:
	set(v):
		kind = v
		_rebuild()

var _sprite: Sprite2D
var _shape: CollisionShape2D
var _interact: Interactable


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_sprite = $Sprite
	_shape = $Shape
	_interact = $Interact
	_rebuild()
	if Engine.is_editor_hint():
		return
	add_to_group(&"safehouse_stations")
	_interact.prompt_provider = func() -> String: return PROMPTS[kind]
	_interact.interacted.connect(func(by: Node) -> void: used.emit(self, by))


func _enter_tree() -> void:
	if not Engine.is_editor_hint() and SIZES[kind] != Vector2.ZERO:
		add_to_group(&"nav_source")  # zombies path around furniture


func _rebuild() -> void:
	if _sprite == null:
		return
	_sprite.hframes = 4
	_sprite.frame = int(kind)
	_sprite.light_mask = 1 | 2
	var size: Vector2 = SIZES[kind]
	_shape.disabled = size == Vector2.ZERO
	var rect := RectangleShape2D.new()
	rect.size = size if size != Vector2.ZERO else Vector2(4, 4)
	_shape.shape = rect
	var reach := RectangleShape2D.new()
	reach.size = (size if size != Vector2.ZERO else Vector2(24, 12)) + Vector2(12, 12)
	(_interact.get_node("Shape") as CollisionShape2D).shape = reach
