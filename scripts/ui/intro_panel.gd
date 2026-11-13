extends CanvasLayer
## Slice 2: the opening radio transmission of a new game (typewriter text over black).
## Pauses the game. Any key / click: first finishes the text, then starts the game.

signal finished

const LINES: Array[String] = [
	"...static...",
	"",
	"DAY 1 OF THE OUTBREAK.  ASHFORD LANE.",
	"",
	"The army pulled out last night. The phone lines are dead.",
	"You have a safehouse, a bat, a pistol, and not much else.",
	"",
	"By day: find food, water, and scrap to nail over your windows.",
	"By night: they come. Every gunshot tells them where you are.",
	"",
	"Somewhere in town is a part for the old radio.",
	"Fix it. Call for help. Survive ten nights.",
]
const CHARS_PER_SECOND: float = 55.0

var player: Player
var _label: Label
var _hint: Label
var _full: String = ""
var _shown: float = 0.0
var _opened_frame: int = -1


func _ready() -> void:
	layer = 14
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.03, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(380, 0)
	box.position = Vector2(-190, -90)
	bg.add_child(box)
	_label = UiKit.label("", 10, Color(0.62, 0.86, 0.9))
	_label.name = "Transmission"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(380, 150)
	box.add_child(_label)
	_hint = UiKit.label("Press any key", 10, UiKit.TEXT.darkened(0.3))
	_hint.name = "Hint"
	box.add_child(_hint)
	_full = "\n".join(LINES)


func play(p: Player) -> void:
	player = p
	_shown = 0.0
	_label.text = ""
	_hint.text = "Press any key to skip"
	visible = true
	_opened_frame = Engine.get_process_frames()
	if player != null:
		player.ui_open = true
	get_tree().paused = true
	AudioManager.play_ui(preload("res://assets/audio/sfx/radio_on.wav"), -4.0)


func is_done_typing() -> bool:
	return _shown >= _full.length()


func _process(delta: float) -> void:
	if not visible or is_done_typing():
		return
	_shown = minf(_full.length(), _shown + CHARS_PER_SECOND * delta)
	_label.text = _full.substr(0, int(_shown))
	if is_done_typing():
		_hint.text = "Press any key to begin"


## First press: show all the text. Second: start the game.
func advance() -> void:
	if not visible:
		return
	if not is_done_typing():
		_shown = _full.length()
		_label.text = _full
		_hint.text = "Press any key to begin"
		return
	visible = false
	get_tree().paused = false
	if player != null:
		player.ui_open = false
	finished.emit()


func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		advance()
		get_viewport().set_input_as_handled()
