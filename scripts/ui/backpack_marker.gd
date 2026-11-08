extends Control
## HUD arrow toward the nearest death backpack, with its distance (1 m = 1 tile = 16 px).
## Hidden when there's no backpack or you're standing on it.

const RING_RADIUS: float = 70.0
const PX_PER_METRE: float = 16.0
const COLOR := Color(0.95, 0.75, 0.3)

var player: Player
var target: Vector2 = Vector2.INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Nearest backpack position, or Vector2.INF if none.
func nearest_backpack() -> Vector2:
	var best := Vector2.INF
	for id in GameState.backpack_ids():
		var pos: Vector2 = GameState.piles[id].position
		if best == Vector2.INF or player.global_position.distance_to(pos) < player.global_position.distance_to(best):
			best = pos
	return best


func distance_metres() -> int:
	return int(round(player.global_position.distance_to(target) / PX_PER_METRE)) if target != Vector2.INF else -1


func _process(_delta: float) -> void:
	target = nearest_backpack() if player != null else Vector2.INF
	visible = target != Vector2.INF and not player.is_dead() and player.global_position.distance_to(target) > 20.0
	queue_redraw()


func _draw() -> void:
	if not visible or player == null or target == Vector2.INF:
		return
	var center: Vector2 = player.get_global_transform_with_canvas().origin + Vector2(0, -8)
	var dir: Vector2 = player.global_position.direction_to(target)
	var tip: Vector2 = center + dir * RING_RADIUS
	var side: Vector2 = dir.orthogonal() * 4.0
	var pts := PackedVector2Array([tip + dir * 6.0, tip + side, tip - side])
	draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
	draw_colored_polygon(PackedVector2Array([pts[0] - dir, pts[1] - dir * 0.5, pts[2] - dir * 0.5]), COLOR)
	var font: Font = get_theme_default_font()
	var text: String = "BACKPACK %d m" % distance_metres()
	var tpos: Vector2 = tip - dir * 12.0 + Vector2(-39, 3)
	draw_string(font, tpos + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.7))
	draw_string(font, tpos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR)
