extends Node
## Base class for tests. Each test file extends this; every method named test_* is run.
## Tests may `await` (e.g. physics frames). Failures are collected, not thrown.

var failures: Array[String] = []
var current_test: String = ""


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [current_test, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s (expected %.3f ±%.3f, got %.3f)" % [message, expected, tolerance, actual])


## Waits for n physics frames (each is 1/60 s of game time).
func physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A fresh 2D world container that is removed after each test.
func make_sandbox() -> Node2D:
	var sandbox := Node2D.new()
	sandbox.name = "Sandbox"
	add_child(sandbox)
	return sandbox


## A solid wall on physics layer 1 ("world").
func add_wall(parent: Node, rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = rect.get_center()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body


func spawn_player(parent: Node, pos: Vector2) -> Player:
	var p: Player = load("res://scenes/player/player.tscn").instantiate()
	p.use_mouse_aim = false
	p.position = pos
	parent.add_child(p)
	return p


## Test zombies don't wander unless asked, so their behaviour is predictable.
func spawn_walker(parent: Node, pos: Vector2, facing: Vector2, wanders: bool = false) -> Zombie:
	var z: Zombie = load("res://scenes/zombies/walker.tscn").instantiate()
	z.position = pos
	z.initial_facing = facing
	z.wanders = wanders
	parent.add_child(z)
	return z


func release_all_actions() -> void:
	for a in [&"move_up", &"move_down", &"move_left", &"move_right", &"run"]:
		Input.action_release(a)


## A navigation mesh for a sandbox: covers `bounds`, avoiding walls added with add_wall()
## (call after adding the walls). Waits until the navigation map has synced.
func add_navigation(parent: Node, bounds: Rect2) -> NavigationRegion2D:
	for child in parent.get_children():
		if child is StaticBody2D:
			child.add_to_group(&"nav_source")
	var nav := NavigationRegion2D.new()
	nav.set_script(load("res://scripts/world/navigation_baker.gd"))
	nav.set("bounds", bounds)
	parent.add_child(nav)
	# The navigation server syncs in the background: wait (max 5 s; > 1 s seen under CPU load) until usable.
	for i in 300:
		await physics_frames(1)
		var map: RID = nav.get_navigation_map()
		var probe: Vector2 = bounds.get_center()
		if NavigationServer2D.map_get_closest_point(map, probe) != Vector2.ZERO or probe == Vector2.ZERO:
			if i > 2 and not NavigationServer2D.map_get_path(map, probe, probe + Vector2(1, 1), true).is_empty():
				break
	return nav
