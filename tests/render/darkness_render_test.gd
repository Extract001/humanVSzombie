extends Node2D
## Render test for local interior darkness (QA: Phase 1 — Local darkness test room).
## Needs a real renderer (NOT --headless):
##   godot --path . --rendering-driver opengl3 res://tests/render/darkness_render_test.tscn
## Prints "RENDER TEST PASSED" / "RENDER TEST FAILED" and exits with 0 / 1.

const YARD_PROBES: Array[Vector2] = [Vector2(420, 330), Vector2(600, 470), Vector2(560, 610)]
const ROOM_PROBES: Array[Vector2] = [Vector2(700, 470), Vector2(820, 560), Vector2(760, 450)]

var _failures: Array[String] = []


func _ready() -> void:
	var yard: Node2D = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	player.use_mouse_aim = false
	player.position = Vector2(420, 400)
	yard.add_child(player)
	player.camera.enabled = false
	var cam := Camera2D.new()
	cam.position = Vector2(640, 440)
	add_child(cam)
	cam.make_current()

	# Reference: the same room floor with the darkness light switched off.
	var dark_light: PointLight2D = yard.get_node("DarkRoom/Light")
	dark_light.enabled = false
	var unlit: Dictionary = await _capture("no_darkness_reference")
	dark_light.enabled = true
	var outside: Dictionary = await _capture("outside")
	player.global_position = Vector2(740, 520)  # inside the dark room
	var inside: Dictionary = await _capture("inside")

	for i in YARD_PROBES.size():
		var a: float = outside["yard"][i]
		var b: float = inside["yard"][i]
		_check(absf(a - b) < 0.01, "yard probe %d unchanged when player enters room (%.3f vs %.3f)" % [i, a, b])
		_check(a > 0.2, "yard probe %d is lit (%.3f)" % [i, a])
	for i in ROOM_PROBES.size():
		var r: float = outside["room"][i]
		var ref: float = unlit["room"][i]
		_check(r < ref * 0.15, "room probe %d dark: %.3f < 15%% of the same floor without darkness (%.3f)" % [i, r, ref])
		_check(absf(unlit["yard"][i] - outside["yard"][i]) < 0.01, "yard probe %d identical with darkness on/off" % i)
	_check(player.in_darkness, "player reports being in darkness")

	for f in _failures:
		print("  ✗ " + f)
	print("RENDER TEST PASSED" if _failures.is_empty() else "RENDER TEST FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _capture(label: String) -> Dictionary:
	for i in 20:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://darkness_render_%s.png" % label)
	var xf: Transform2D = get_viewport().get_canvas_transform()
	var yard: Array[float] = []
	var room: Array[float] = []
	for p in YARD_PROBES:
		yard.append(img.get_pixelv(Vector2i(xf * p)).get_luminance())
	for p in ROOM_PROBES:
		room.append(img.get_pixelv(Vector2i(xf * p)).get_luminance())
	print("%s: yard=%s room=%s" % [label, str(yard), str(room)])
	return {"yard": yard, "room": room}


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)
