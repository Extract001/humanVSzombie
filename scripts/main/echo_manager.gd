class_name EchoManager
extends Node
## Slice 2 — Your Echo. When you die carrying things, your backpack doesn't just lie there: after a
## moment your dead self gets up and wanders off with it (a tough, pale zombie in your clothes).
## Kill your Echo and the backpack drops where it falls. GameState.piles[id].echo marks a carried
## backpack; its position follows the Echo (saved), so a loaded game puts the Echo back there.

signal echo_risen(echo: Zombie)
signal echo_killed(pile_id: StringName)

const WALKER: PackedScene = preload("res://scenes/zombies/walker.tscn")
const ECHO: ZombieData = preload("res://data/zombies/echo.tres")
const PLAYER_FRAMES: SpriteFrames = preload("res://assets/sprites/player_frames.tres")
## Seconds after death before the Echo rises.
const RISE_DELAY: float = 1.5

var game: Node
var player: Player
var actors: Node2D
var _frames: SpriteFrames
var _track_left: float = 0.0


func setup(game_root: Node, p: Player, actors_root: Node2D) -> void:
	game = game_root
	player = p
	actors = actors_root
	player.backpack_dropped.connect(_on_backpack_dropped)
	# A loaded game: Echoes that were out there come back where they were.
	for id in GameState.piles:
		if GameState.piles[id].get("echo", false):
			spawn_echo(id)


func echoes() -> Array:
	return get_tree().get_nodes_in_group(&"echoes").filter(func(z: Node) -> bool:
		return (z as Zombie).state != Zombie.State.DEAD)


func _on_backpack_dropped(pile_id: StringName) -> void:
	if pile_id == &"":
		return
	await get_tree().create_timer(RISE_DELAY, false).timeout
	if not is_inside_tree() or not GameState.piles.has(pile_id):
		return
	rise(pile_id)


## Your dead self gets up with backpack `pile_id`.
func rise(pile_id: StringName) -> Zombie:
	GameState.piles[pile_id].echo = true
	GameState.piles_changed.emit()   # the backpack leaves the ground
	var z: Zombie = spawn_echo(pile_id)
	Fx.burst(actors, z.global_position + Vector2(0, -6), Fx.DUST, 12, 40.0, Vector2.UP, 0.6)
	AudioManager.play_at(preload("res://assets/audio/sfx/zombie_grunt.wav"), z.global_position, 2.0)
	get_tree().call_group(&"hud", &"show_toast", "Your Echo rises... and it has your backpack.")
	echo_risen.emit(z)
	return z


func spawn_echo(pile_id: StringName) -> Zombie:
	var z: Zombie = WALKER.instantiate()
	z.data = ECHO
	z.position = GameState.piles[pile_id].position
	z.initial_facing = Vector2.RIGHT.rotated(randf() * TAU)
	actors.add_child(z)
	z.sprite.sprite_frames = _echo_frames()
	z.add_to_group(&"echoes")
	z.set_meta(&"pile_id", pile_id)
	var tag := Label.new()
	tag.name = "EchoTag"
	tag.text = "YOUR ECHO"
	tag.add_theme_font_size_override(&"font_size", 10)
	tag.add_theme_color_override(&"font_color", Color(0.72, 1.0, 0.82))
	tag.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.85))
	tag.add_theme_constant_override(&"shadow_offset_x", 1)
	tag.add_theme_constant_override(&"shadow_offset_y", 1)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size = Vector2(80, 10)
	tag.position = Vector2(-40, -34)
	tag.z_index = 20
	z.add_child(tag)
	z.died.connect(_on_echo_died.bind(z, pile_id))
	return z


func _on_echo_died(z: Zombie, pile_id: StringName) -> void:
	if not GameState.piles.has(pile_id):
		return
	GameState.piles[pile_id].position = player.snap_to_navigation(z.global_position)
	GameState.piles[pile_id].echo = false
	GameState.piles_changed.emit()   # the backpack drops where your Echo fell
	var tag: Node = z.get_node_or_null("EchoTag")
	if tag != null:
		tag.queue_free()
	get_tree().call_group(&"hud", &"show_toast", "You put your Echo to rest. Your backpack is here.")
	echo_killed.emit(pile_id)


func _physics_process(delta: float) -> void:
	_track_left -= delta
	if _track_left > 0.0:
		return
	_track_left = 0.5
	# The backpack goes where your Echo goes (the HUD arrow and the save follow it).
	for z in echoes():
		var id: StringName = z.get_meta(&"pile_id", &"")
		if GameState.piles.has(id):
			GameState.piles[id].position = (z as Node2D).global_position


## The player's own sprites, with "attack" borrowed from the melee swing.
func _echo_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	_frames = PLAYER_FRAMES.duplicate(true)
	for dir in ["down", "left", "right", "up"]:
		var src := StringName("melee_" + dir)
		var dst := StringName("attack_" + dir)
		if not _frames.has_animation(src):
			continue
		if not _frames.has_animation(dst):
			_frames.add_animation(dst)
		_frames.set_animation_speed(dst, _frames.get_animation_speed(src))
		_frames.set_animation_loop(dst, false)
		for i in _frames.get_frame_count(src):
			_frames.add_frame(dst, _frames.get_frame_texture(src, i), _frames.get_frame_duration(src, i))
	return _frames
