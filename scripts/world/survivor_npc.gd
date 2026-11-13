class_name SurvivorNPC
extends Node2D
## Batch 2 — a survivor in town. WAITING: hides at their spot and calls out when you come near;
## press E and they FOLLOW you (along the navigation mesh, no collisions); walk them into the
## safehouse and they're HOME: they go to their spot inside and do their job (see Survivors).
## Placeholder look: the player's sprite sheet in the survivor's own colours (Batch 3 art pass).

signal rescued(npc: SurvivorNPC)

enum Mode { WAITING, FOLLOWING, HOME }

const FRAMES: SpriteFrames = preload("res://assets/sprites/player_frames.tres")
const FOLLOW_GAP: float = 22.0
const WALK_SPEED: float = 92.0
const CATCH_UP_SPEED: float = 150.0
## Too far behind (a closed door, a fence): they slip through and catch up.
const TELEPORT_DISTANCE: float = 260.0

var survivor_id: StringName
var info: Dictionary = {}
var mode: int = Mode.WAITING
var player: Player
var home_spot: Vector2
var sprite: AnimatedSprite2D
var interactable: Interactable
var _path: PackedVector2Array = PackedVector2Array()
var _repath: float = 0.0
var _facing: Vector2 = Vector2.DOWN
var _called_out: bool = false
var _bob: float = 0.0


func setup(id: StringName, data: Dictionary, p: Player, start_mode: int) -> void:
	survivor_id = id
	info = data
	player = p
	mode = start_mode
	name = "Survivor_" + String(id)
	home_spot = (data.home as Vector2 + Vector2(0.5, 0.5)) * 16.0
	add_to_group(&"survivors")


func _ready() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = FRAMES
	sprite.self_modulate = info.get("tint", Color.WHITE)
	sprite.scale = Vector2.ONE * float(info.get("scale", 1.0))
	sprite.offset = Vector2(0, -10)
	add_child(sprite)
	sprite.play(&"idle_down")
	interactable = Interactable.new()
	interactable.name = "Interactable"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	shape.position = Vector2(0, -6)
	interactable.add_child(shape)
	interactable.prompt_provider = _prompt
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)
	y_sort_enabled = false


func _prompt() -> String:
	match mode:
		Mode.WAITING:
			return "Rescue %s (%s)" % [info.name, info.job]
		Mode.FOLLOWING:
			return "%s is following you" % info.name
	return "%s, %s: %s" % [info.name, info.job, info.short]


func _on_interacted(_by: Node) -> void:
	if mode == Mode.WAITING:
		start_following()
	elif mode == Mode.HOME:
		say(String(info.get("line_home", "Still here.")))


func start_following() -> void:
	mode = Mode.FOLLOWING
	_repath = 0.0
	say(String(info.get("line_join", "Lead the way.")))
	AudioManager.play_ui(preload("res://assets/audio/sfx/radio_on.wav"), -8.0)


## The player died: they stay where they are and wait to be picked up again.
func stop_following() -> void:
	if mode == Mode.FOLLOWING:
		mode = Mode.WAITING
		_path = PackedVector2Array()


func go_home() -> void:
	mode = Mode.HOME
	_path = _nav_path(home_spot)


func say(text: String) -> void:
	Juice.popup(get_parent(), global_position + Vector2(0, -26), text, Color(0.7, 1.0, 0.75), 8)


func _physics_process(delta: float) -> void:
	_bob += delta
	match mode:
		Mode.WAITING:
			_wait()
		Mode.FOLLOWING:
			_follow(delta)
		Mode.HOME:
			_walk_path(delta, WALK_SPEED * 0.7)


func _wait() -> void:
	_animate(Vector2.ZERO)
	if player == null or _called_out:
		return
	if player.global_position.distance_to(global_position) < 90.0:
		_called_out = true
		say(String(info.get("line_call", "Over here! Please!")))


func _follow(delta: float) -> void:
	if player == null or player.is_dead():
		stop_following()
		return
	var to_player: float = global_position.distance_to(player.global_position)
	if to_player > TELEPORT_DISTANCE:
		global_position = player.global_position - player.velocity.normalized() * FOLLOW_GAP
		_path = PackedVector2Array()
		return
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.4
		_path = _nav_path(player.global_position)
	if to_player <= FOLLOW_GAP:
		_animate(Vector2.ZERO)
		return
	_walk_path(delta, CATCH_UP_SPEED if to_player > 70.0 else WALK_SPEED)


func _walk_path(delta: float, speed: float) -> void:
	while not _path.is_empty() and global_position.distance_to(_path[0]) < 3.0:
		_path.remove_at(0)
	if _path.is_empty():
		_animate(Vector2.ZERO)
		return
	var step: Vector2 = global_position.direction_to(_path[0]) * speed * delta
	if step.length() > global_position.distance_to(_path[0]):
		step = _path[0] - global_position
	global_position += step
	_animate(step / maxf(delta, 0.0001))


func _nav_path(to: Vector2) -> PackedVector2Array:
	if not is_inside_tree():
		return PackedVector2Array()
	var map: RID = get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return PackedVector2Array([to])
	var path: PackedVector2Array = NavigationServer2D.map_get_path(map, global_position, to, true, 1)
	return path if not path.is_empty() else PackedVector2Array([to])


func _animate(velocity: Vector2) -> void:
	if sprite == null:
		return
	if velocity.length() > 5.0:
		_facing = velocity.normalized()
	var dir: String = Player._direction_name(_facing)
	var anim := StringName(("walk_" if velocity.length() > 5.0 else "idle_") + dir)
	if sprite.animation != anim:
		sprite.play(anim)
	# Waiting survivors crouch a little and look around (reads as "hiding").
	sprite.position.y = 1.0 if mode == Mode.WAITING else 0.0
	if mode == Mode.WAITING and int(_bob * 0.5) % 2 == 0:
		_facing = Vector2.LEFT if int(_bob) % 4 < 2 else Vector2.RIGHT
