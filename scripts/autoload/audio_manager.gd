extends Node
## AudioManager (autoload): a small pool of positional players, so firing doesn't
## create a new node every shot. Use AudioManager.play_at(stream, position).

signal sound_requested(stream: AudioStream, world_position: Vector2)

const POOL_SIZE: int = 16
const MAX_DISTANCE: float = 700.0

var _pool: Array[AudioStreamPlayer2D] = []
var _ui: AudioStreamPlayer
## Own random generator for pitch variation (keeps the gameplay random sequence untouched).
var _rng := RandomNumberGenerator.new()
var _next: int = 0
## False when there is no real audio output (headless test runs use the "Dummy" driver,
## which never frees finished sounds). Sounds are then only announced, not played.
var output_enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	output_enabled = AudioServer.get_driver_name() != "Dummy"
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = MAX_DISTANCE
		p.attenuation = 1.5
		p.bus = &"SFX"  # Settings: effects volume
		add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	_ui.bus = &"SFX"
	add_child(_ui)


## Plays a sound at a world position. Small random pitch changes stop repeats sounding robotic.
func play_at(stream: AudioStream, world_position: Vector2, volume_db: float = 0.0,
		pitch_jitter: float = 0.06) -> void:
	if stream == null:
		return
	sound_requested.emit(stream, world_position)
	if not output_enabled:
		return
	var p: AudioStreamPlayer2D = _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.global_position = world_position
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Non-positional interface sound (button clicks). Works while the game is paused.
func play_ui(stream: AudioStream = preload("res://assets/audio/sfx/ui_click.wav"), volume_db: float = -8.0) -> void:
	if not output_enabled or stream == null:
		return
	_ui.stream = stream
	_ui.volume_db = volume_db
	_ui.play()


## Stops everything (used before quitting so no sound is left playing).
func stop_all() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
	_ui.stop()
	_ui.stream = null


func _exit_tree() -> void:
	stop_all()
