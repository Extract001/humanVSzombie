extends Control
## Fun pass: HUD arrow to "where to go now" (GoalFinder), with a word and the distance.
## Pale cyan like the objective text; HOME turns orange at dusk/night. Hidden when you're there.

const RING_RADIUS: float = 52.0
const PX_PER_METRE: float = 16.0
const COLOR := Color(0.62, 0.86, 0.9)
const HOME_COLOR := Color(1.0, 0.6, 0.35)

var game: Node
var goal: Dictionary = {}
var _refresh: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if game == null:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		goal = GoalFinder.find(game)
	var p: Player = game.player
	visible = not goal.is_empty() and p != null and p.global_position.distance_to(goal.pos) > 28.0 and not p.ui_open
	queue_redraw()


func _draw() -> void:
	if not visible or goal.is_empty():
		return
	var p: Player = game.player
	var col: Color = HOME_COLOR if goal.label == "HOME" or goal.label == "BOARD UP" else COLOR
	var center: Vector2 = p.get_global_transform_with_canvas().origin + Vector2(0, -8)
	var dir: Vector2 = p.global_position.direction_to(goal.pos)
	var tip: Vector2 = center + dir * RING_RADIUS
	var side: Vector2 = dir.orthogonal() * 4.0
	var pts := PackedVector2Array([tip + dir * 6.0, tip + side, tip - side])
	draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
	draw_colored_polygon(PackedVector2Array([pts[0] - dir, pts[1] - dir * 0.5, pts[2] - dir * 0.5]), col)
	var font: Font = get_theme_default_font()
	var text: String = "%s %d m" % [goal.label, int(round(p.global_position.distance_to(goal.pos) / PX_PER_METRE))]
	var tpos: Vector2 = tip + dir * 14.0 + Vector2(-text.length() * 3.0, 4)
	draw_string(font, tpos + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.75))
	draw_string(font, tpos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
