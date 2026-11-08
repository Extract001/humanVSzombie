extends "res://tests/test_case.gd"
## Movement simulation with real physics and real input actions (QA: Phase 1).


func test_diagonal_input_is_not_faster() -> void:
	Input.action_press(&"move_right")
	Input.action_press(&"move_down")
	var v: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	check(v.length() <= 1.0001, "diagonal input length <= 1 (got %.4f)" % v.length())
	release_all_actions()


func test_walk_speed_reached() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	Input.action_press(&"move_right")
	await physics_frames(30)
	check_near(p.velocity.length(), 80.0, 0.5, "walk speed")
	release_all_actions()


func test_diagonal_walk_speed_equals_straight() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	Input.action_press(&"move_right")
	Input.action_press(&"move_up")
	await physics_frames(30)
	check_near(p.velocity.length(), 80.0, 0.5, "diagonal walk speed")
	release_all_actions()


func test_run_speed_reached() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	Input.action_press(&"move_left")
	Input.action_press(&"run")
	await physics_frames(30)
	check(p.is_running, "is running")
	check_near(p.velocity.length(), 140.0, 0.5, "run speed")
	release_all_actions()


func test_stops_quickly_without_sliding() -> void:
	var sandbox := make_sandbox()
	var p := spawn_player(sandbox, Vector2(0, 0))
	Input.action_press(&"move_down")
	await physics_frames(30)
	release_all_actions()
	await physics_frames(6)  # 0.1 s
	check_near(p.velocity.length(), 0.0, 0.01, "stopped within 0.1 s")


func test_cannot_walk_through_wall() -> void:
	var sandbox := make_sandbox()
	add_wall(sandbox, Rect2(40, -100, 16, 200))
	var p := spawn_player(sandbox, Vector2(0, 0))
	await physics_frames(2)
	Input.action_press(&"move_right")
	Input.action_press(&"run")
	await physics_frames(90)
	check(p.global_position.x < 40.0, "player stopped by wall (x=%.1f)" % p.global_position.x)
	release_all_actions()


func test_slides_along_wall_corner() -> void:
	# Pushing diagonally into a wall must slide along it, not stick.
	var sandbox := make_sandbox()
	add_wall(sandbox, Rect2(-200, 30, 400, 16))
	var p := spawn_player(sandbox, Vector2(0, 0))
	await physics_frames(2)
	Input.action_press(&"move_down")
	Input.action_press(&"move_right")
	await physics_frames(60)
	check(p.global_position.y < 30.0, "did not pass through")
	check(p.global_position.x > 30.0, "kept sliding along the wall (x=%.1f)" % p.global_position.x)
	release_all_actions()
