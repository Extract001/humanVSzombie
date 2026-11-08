extends Node2D
## Simple crosshair that follows the mouse (drawn on a CanvasLayer, so it stays crisp).
## The system cursor is hidden while playing and shown again on menus.

const GAP: float = 2.0
const LENGTH: float = 3.0
const COLOR := Color(0.95, 0.92, 0.8, 0.9)
const SHADOW := Color(0, 0, 0, 0.6)


func _process(_delta: float) -> void:
	position = get_viewport().get_mouse_position().round()


func _draw() -> void:
	for offset in [Vector2(1, 1), Vector2.ZERO]:
		var c: Color = SHADOW if offset != Vector2.ZERO else COLOR
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(offset + dir * GAP, offset + dir * (GAP + LENGTH), c, 1.0)
		draw_rect(Rect2(offset, Vector2.ONE), c)
