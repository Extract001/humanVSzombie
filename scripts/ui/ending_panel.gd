extends CanvasLayer
## MVP ending (GDD §11): the repaired radio picks up a broadcast that reveals an evacuation route.
## The game continues afterwards ("Keep playing").

signal opened
signal closed

const BROADCAST := [
	"...static...",
	"\"...this is the Riverside relief convoy, repeating on all emergency bands.",
	"Survivors in the Ashford district: the old rail bridge east of the checkpoint is still standing.",
	"We will hold the far side at dawn, every third day. Bring only what you can carry.",
	"Signal with a light when you reach the bridge. Do not use the main road...\"",
	"...static...",
	"",
	"You have a way out. For now, you keep the radio on.",
]

var player: Player
var _text: Label
var _opened_frame: int = -1


func _ready() -> void:
	layer = 13
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box: VBoxContainer = UiKit.centered_panel(self, Vector2(220, 95))
	var t: Label = UiKit.title("LAST SIGNAL")
	t.add_theme_color_override(&"font_color", UiKit.OBJECTIVE)
	box.add_child(t)
	_text = UiKit.label("\n".join(BROADCAST), 8)
	_text.name = "Broadcast"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(420, 120)
	box.add_child(_text)
	var b: Button = UiKit.button("Keep playing", close)
	b.name = "KeepPlaying"
	box.add_child(b)


func bind(p: Player) -> void:
	player = p


func open() -> void:
	_opened_frame = Engine.get_process_frames()
	visible = true
	player.ui_open = true
	AudioManager.play_at(preload("res://assets/audio/sfx/radio_on.wav"), player.global_position, -4.0)
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	player.ui_open = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()
