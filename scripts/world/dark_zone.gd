@tool
class_name DarkZone
extends Node2D
## Local interior darkness (TECHNICAL_ARCHITECTURE §4.6).
##
## Visual: a Subtract-mode light shaped like the room floor darkens ONLY this area.
##         It affects items whose light mask includes layer 2 ("interior_darkness"):
##         floors, props, characters. Walls and roofs leave that layer off, so they
##         aren't blackened. Nothing outside the rectangle changes, so the street stays lit.
## Gameplay: an Area2D tells the player (and later the AI) "you are in the dark".
## Place it so `size` covers the room floor; the node's position is the top-left corner.

const DARKNESS_LIGHT_LAYER: int = 2  # bit value of render layer 2

@export var size: Vector2 = Vector2(160, 128):
	set(value):
		size = value
		_rebuild()
## How much brightness is removed (0 = none, 1 = pitch black).
@export_range(0.0, 1.0) var darkness: float = 0.88:
	set(value):
		darkness = value
		_rebuild()
## Soft edge width in pixels, so doorways fade instead of showing a hard box.
@export var feather: int = 12:
	set(value):
		feather = value
		_rebuild()

var _light: PointLight2D
var _area: Area2D
var _shape: CollisionShape2D


func _ready() -> void:
	_light = $Light
	_area = $Area
	_shape = $Area/Shape
	_rebuild()
	if not Engine.is_editor_hint():
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)


func _rebuild() -> void:
	if _light == null or not is_inside_tree():
		return
	_light.texture = _make_mask(Vector2i(size), feather)
	_light.position = size * 0.5
	_light.blend_mode = Light2D.BLEND_MODE_SUB
	_light.energy = darkness
	_light.shadow_enabled = false
	_light.range_item_cull_mask = DARKNESS_LIGHT_LAYER
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	_shape.position = size * 0.5


## White = full darkness, fading to black at the edges over `feather_px`.
static func _make_mask(px: Vector2i, feather_px: int) -> ImageTexture:
	px = px.max(Vector2i.ONE)
	var img := Image.create(px.x, px.y, false, Image.FORMAT_L8)
	var f: float = maxf(1.0, float(feather_px))
	for y in px.y:
		var dy: int = mini(y, px.y - 1 - y)
		for x in px.x:
			var d: int = mini(dy, mini(x, px.x - 1 - x))
			var v: float = clampf(float(d) / f, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


func contains_point(global_point: Vector2) -> bool:
	return Rect2(global_position, size).has_point(global_point)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method(&"enter_darkness"):
		body.enter_darkness()


func _on_body_exited(body: Node2D) -> void:
	if body.has_method(&"exit_darkness"):
		body.exit_darkness()
