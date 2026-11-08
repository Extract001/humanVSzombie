@tool
class_name Roof
extends Node2D
## A building's roof. It hides the interior from the street; when the player walks inside,
## it fades out so you can see the rooms, and the location name pops up on the HUD.
## The node's position is the top-left of the building's INTERIOR (inside the walls), so the
## walls and doors stay visible from the street while the rooms stay hidden.

const FADE_TIME: float = 0.25
const TILE: int = 16

@export var size: Vector2 = Vector2(160, 128):
	set(v):
		size = v
		_rebuild()
@export var location_name: String = ""

var player_inside: bool = false

var _sprite: Sprite2D
var _area: Area2D
var _tween: Tween


func _ready() -> void:
	_sprite = $Sprite
	_area = $Inside
	z_index = 20  # above characters and props
	_rebuild()
	if not Engine.is_editor_hint():
		add_to_group(&"roofs")
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)


func _rebuild() -> void:
	if _sprite == null:
		return
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(Vector2.ZERO, size)
	_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_sprite.light_mask = 1  # never darkened by interior darkness
	var shape := _area.get_child(0) as CollisionShape2D
	var box := RectangleShape2D.new()
	box.size = size  # the roof covers exactly the interior (inside the walls)
	shape.shape = box
	shape.position = size * 0.5


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_inside = true
		_fade_to(0.0)
		if location_name != "":
			get_tree().call_group(&"hud", &"show_toast", location_name)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		player_inside = false
		_fade_to(1.0)


func _fade_to(alpha: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_sprite, "modulate:a", alpha, FADE_TIME)
