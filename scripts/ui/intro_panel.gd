class_name IntroPanel
extends CanvasLayer
## Opening cinematic transmission: establishes the stakes, world, and 10-night goal immediately.

signal closed

var player: Player
var _opened_frame: int = -1


func _ready() -> void:
	layer = 14
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Letterbox bars
	var top_bar := ColorRect.new()
	top_bar.color = Color.BLACK
	top_bar.custom_minimum_size = Vector2(0, 24)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top_bar)

	var btm_bar := ColorRect.new()
	btm_bar.color = Color.BLACK
	btm_bar.custom_minimum_size = Vector2(0, 24)
	btm_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(btm_bar)

	var box: VBoxContainer = UiKit.centered_panel(self, Vector2(210, 105))
	var tag: Label = UiKit.label("[EMERGENCY BROADCAST - ASHFORD 104.7 MHz]", 8, Color(0.95, 0.65, 0.3))
	box.add_child(tag)

	var title: Label = UiKit.title("EXTRACTION INBOUND: 10 DAYS")
	title.add_theme_color_override(&"font_color", UiKit.OBJECTIVE)
	box.add_child(title)

	var msg: Label = UiKit.label(
		"\"MAYDAY... TO ANY SURVIVORS IN ASHFORD LANE.\n" +
		"THE QUARANTINE PERIMETER HAS COLLAPSED.\n\n" +
		"AN EVACUATION CONVOY WILL SWEEP ASHFORD AT DAWN OF DAY 10.\n" +
		"SCAVENGE BY DAY. BOARD UP YOUR WINDOWS BEFORE DUSK.\n" +
		"THE NIGHTS BELONG TO THE HORDE. SURVIVE.\"",
		10,
		UiKit.TEXT
	)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(380, 0)
	box.add_child(msg)

	var btn: Button = UiKit.button("Begin Day 1 [Space / Enter]", close)
	btn.name = "BeginButton"
	box.add_child(btn)


func bind(p: Player) -> void:
	player = p


func play_intro() -> void:
	_opened_frame = Engine.get_process_frames()
	visible = true
	if player != null:
		player.ui_open = true
	get_tree().paused = true
	AudioManager.play_at(preload("res://assets/audio/sfx/radio_on.wav"), Vector2.ZERO, 2.0)


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if player != null:
		player.ui_open = false
		player.message.emit("Day 1: Scavenge supplies and prepare before dusk.")
	GameState.add_unlock(&"intro_seen")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed(&"attack") or event.is_action_pressed(&"interact") \
			or event.is_action_pressed(&"shove") or event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
