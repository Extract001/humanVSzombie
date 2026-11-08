extends Node2D
## Playable difficulty arenas (debug only, not in exported builds).
## Open scenes/debug/arena_playground.tscn in Godot and press F6 ("Run Current Scene").
## In the game: F1–F6 load arenas S1–S6 (pressing the same key again restarts it).

var _arena: Dictionary = {}
var _player: Player
var _kills: int = 0

@onready var hud: CanvasLayer = $HUD
@onready var info: Label = $Info/Label


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_load(0)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_F1 and key.keycode <= KEY_F6:
		_load(key.keycode - KEY_F1)
		get_viewport().set_input_as_handled()


func _load(index: int) -> void:
	if not _arena.is_empty():
		(_arena.root as Node).queue_free()
		await get_tree().process_frame
	_arena = ArenaBuilder.build(index)
	add_child(_arena.root)
	move_child(_arena.root, 0)
	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.position = _arena.player_spawn
	(_arena.root as Node).get_node("Actors").add_child(_player)
	var b: Rect2 = _arena.bounds
	_player.camera.limit_left = int(b.position.x)
	_player.camera.limit_top = int(b.position.y)
	_player.camera.limit_right = int(b.end.x)
	_player.camera.limit_bottom = int(b.end.y)
	_player.camera.reset_smoothing()
	hud.bind(_player)
	_kills = 0
	for z in _arena.walkers:
		(z as Zombie).died.connect(func() -> void:
			_kills += 1
			hud.set_kills(_kills))
	_player.died.connect(func() -> void:
		info.text = "%s\nYOU DIED - press F%d to retry, or F1-F6 for another arena" % [_arena.name, index + 1])
	info.text = "%s\nF1-F6: choose arena   (same key = restart)%s" % [_arena.name,
		"\nExit: reach the right-hand side" if (_arena.exit as Rect2).has_area() else ""]
	if index == 5:
		info.text += "\nTry: press 2 and fire one shot, then watch who comes"
