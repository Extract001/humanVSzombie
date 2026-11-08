@tool
class_name Vehicle
extends StaticBody2D
## An abandoned vehicle: solid, blocks bullets and zombie paths (it's part of the navigation mesh).
## Phase 6 adds the car alarm; trunks are separate LootContainers placed behind the car.

enum Kind { CAR, PICKUP, BUS }

const TEXTURES: Array[String] = [
	"res://assets/sprites/car.png",
	"res://assets/sprites/pickup.png",
	"res://assets/sprites/bus.png",
]

@export var kind: Kind = Kind.CAR:
	set(v):
		kind = v
		_rebuild()

var _sprite: Sprite2D
var _shape: CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_sprite = $Sprite
	_shape = $Shape
	_rebuild()


func _enter_tree() -> void:
	# Joined before any _ready(), so the (deferred) navigation bake treats vehicles as obstacles.
	if not Engine.is_editor_hint():
		add_to_group(&"nav_source")


func _rebuild() -> void:
	if _sprite == null:
		return
	var tex: Texture2D = load(TEXTURES[int(kind)])
	_sprite.texture = tex
	_sprite.light_mask = 1 | 2
	var box := RectangleShape2D.new()
	box.size = tex.get_size() - Vector2(2, 2)
	_shape.shape = box
