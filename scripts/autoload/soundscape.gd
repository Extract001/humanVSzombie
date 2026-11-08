extends Node
## Soundscape (autoload): background ambience and music, with slow crossfades between moods.
## Moods: "menu" (calm music, rain), "outside" (wind + tense music), "safehouse" (rain on the roof + calm music),
## "silent". Music plays on the "Music" bus, ambience on "SFX" (Settings sliders).
## Also plays the occasional distant groan from a zombie far away (positional, game only).

const TRACKS := {
	"outside": ["res://assets/audio/music/amb_outside.ogg", "res://assets/audio/music/music_outside.ogg"],
	"safehouse": ["res://assets/audio/music/amb_safehouse.ogg", "res://assets/audio/music/music_safehouse.ogg"],
	"menu": ["res://assets/audio/music/amb_safehouse.ogg", "res://assets/audio/music/music_safehouse.ogg"],
}
const FADE_TIME: float = 2.5
const AMBIENCE_DB: float = -10.0
const MUSIC_DB: float = -8.0
const GROAN_MIN: float = 10.0
const GROAN_MAX: float = 24.0
const GROANS: Array[AudioStream] = [preload("res://assets/audio/sfx/groan_distant_1.wav"),
	preload("res://assets/audio/sfx/groan_distant_2.wav")]

var mood: String = "silent"
## Set by the game while it runs; distant groans need a player to be "distant" from.
var player: Node2D = null

var _amb: Array[AudioStreamPlayer] = []    ## [current, fading out]
var _music: Array[AudioStreamPlayer] = []
var _groan_left: float = 15.0
var _enabled: bool = true
## Own random generator: never disturbs the gameplay random sequence.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # music keeps playing in the pause menu
	_enabled = AudioServer.get_driver_name() != "Dummy"   # headless tests: no playback (avoids leaks)
	for i in 2:
		_amb.append(_player(&"SFX"))
		_music.append(_player(&"Music"))


func set_mood(new_mood: String) -> void:
	if new_mood == mood:
		return
	mood = new_mood
	if not _enabled:
		return
	var tracks: Array = TRACKS.get(new_mood, [])
	_crossfade(_amb, tracks[0] if tracks.size() > 0 else "", AMBIENCE_DB)
	_crossfade(_music, tracks[1] if tracks.size() > 1 else "", MUSIC_DB)


func _crossfade(pair: Array[AudioStreamPlayer], path: String, db: float) -> void:
	var old: AudioStreamPlayer = pair[0]
	var new: AudioStreamPlayer = pair[1]
	pair[0] = new
	pair[1] = old
	_fade(old, -60.0, true)
	if path == "":
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	if old.stream == stream and old.playing:   # same track (e.g. menu -> safehouse): keep it going
		pair[0] = old
		pair[1] = new
		_fade(old, db, false)
		return
	new.stream = stream
	new.volume_db = -60.0
	new.play()
	_fade(new, db, false)


func _fade(p: AudioStreamPlayer, db: float, stop_after: bool) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(p, "volume_db", db, FADE_TIME)
	if stop_after:
		tw.tween_callback(p.stop)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or get_tree().paused or mood != "outside":
		return
	_groan_left -= delta
	if _groan_left > 0.0:
		return
	_groan_left = _rng.randf_range(GROAN_MIN, GROAN_MAX)
	# A living zombie 250-650 px away (heard, not seen) groans.
	var candidates: Array = get_tree().get_nodes_in_group(&"zombies").filter(func(z: Node) -> bool:
		var d: float = (z as Node2D).global_position.distance_to(player.global_position)
		return d > 250.0 and d < 650.0)
	if candidates.is_empty():
		return
	var z: Node2D = candidates[_rng.randi() % candidates.size()]
	AudioManager.play_at(GROANS[_rng.randi() % GROANS.size()], z.global_position, -4.0, 0.12)


func _player(bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -60.0
	add_child(p)
	return p


func stop_all() -> void:
	for p in _amb + _music:
		p.stop()
		p.stream = null
	mood = "silent"
