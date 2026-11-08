extends Node2D
## Render test for the flashlight in the real map (QA Phase 6):
## warehouse interior dark, street brightness unchanged, the beam lights the floor, a shelf blocks it.
## Needs a real renderer (NOT --headless):
##   godot --path . --rendering-driver opengl3 res://tests/render/flashlight_render_test.tscn
## Prints "FLASHLIGHT RENDER TEST PASSED" / "FAILED" and exits with 0 / 1.
##
## Warehouse layout (tiles): shelf rows at y 6, 9, 12 from x 10-20 and 23-33; x 21-22 is a free cross aisle.
## Beam pointing DOWN from y 4.7:
##   open column x 21.5 -> probe at y 7.5 is lit
##   column x 15.5      -> the shelf at y 6 is in the way, so the probe at y 7.5 stays dark

const TILE := 16.0
const OPEN_PLAYER := Vector2(21.5, 4.7)
const OPEN_PROBE := Vector2(21.5, 7.5)
const SHADOW_PLAYER := Vector2(15.5, 4.7)
const SHADOW_PROBE := Vector2(15.5, 7.5)
const STREET_PROBES: Array[Vector2] = [Vector2(20.5, 23.5), Vector2(28.5, 25.0)]
const DARK_PROBE := Vector2(30.5, 10.5)

var _failures: Array[String] = []
var map: Node2D
var player: Player
var cam: Camera2D


func _ready() -> void:
	GameState.new_game(1)
	map = load("res://scenes/world/ashford_lane.tscn").instantiate()
	add_child(map)
	player = load("res://scenes/player/player.tscn").instantiate()
	player.use_mouse_aim = false
	map.add_child(player)
	player.camera.enabled = false
	cam = Camera2D.new()
	cam.position = Vector2(22, 14) * TILE  # shows the warehouse and the street below it
	add_child(cam)
	cam.make_current()

	player.global_position = Vector2(20, 25) * TILE  # out in the street
	var outside: Dictionary = await _capture("street")
	player.aim_direction = Vector2.DOWN
	player.global_position = OPEN_PLAYER * TILE
	var dark: Dictionary = await _capture("inside_light_off")
	player.set_flashlight(true)
	var open_lit: Dictionary = await _capture("inside_open_column")
	player.global_position = SHADOW_PLAYER * TILE
	var behind_shelf: Dictionary = await _capture("inside_behind_shelf")

	_check(player.in_darkness, "player in the warehouse reports darkness")
	for i in STREET_PROBES.size():
		var a: float = outside.street[i]
		_check(a > 0.2, "street probe %d lit (%.3f)" % [i, a])
		for cap in [dark, open_lit, behind_shelf]:
			_check(absf(cap.street[i] - a) < 0.01, "street probe %d unchanged by being inside / by the flashlight (%.3f vs %.3f)" % [i, a, cap.street[i]])
	_check(dark.open < 0.10, "warehouse aisle dark with the light off (%.3f)" % dark.open)
	_check(dark.far < 0.10, "far warehouse floor dark (%.3f)" % dark.far)
	_check(open_lit.open > 0.25 and open_lit.open > dark.open * 3.0, "beam lights the floor (%.3f vs %.3f dark)" % [open_lit.open, dark.open])
	_check(behind_shelf.shadow < dark.open * 1.5 + 0.02, "shelf blocks the beam (%.3f behind the shelf)" % behind_shelf.shadow)
	_check(open_lit.far < 0.10, "floor outside the beam stays dark (%.3f)" % open_lit.far)

	for f in _failures:
		print("  ✗ " + f)
	print("FLASHLIGHT RENDER TEST PASSED" if _failures.is_empty() else "FLASHLIGHT RENDER TEST FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _capture(label: String) -> Dictionary:
	for i in 40:  # roofs fade out when the player is inside
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://flashlight_render_%s.png" % label)
	var xf: Transform2D = get_viewport().get_canvas_transform()
	var lum := func(tile_pos: Vector2) -> float:
		return img.get_pixelv(Vector2i(xf * (tile_pos * TILE))).get_luminance()
	var street: Array[float] = []
	for p in STREET_PROBES:
		street.append(lum.call(p))
	var out := {"street": street, "open": lum.call(OPEN_PROBE), "shadow": lum.call(SHADOW_PROBE), "far": lum.call(DARK_PROBE)}
	print("%s: %s" % [label, str(out)])
	return out


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)
