extends CanvasLayer
## Slice 1: the morning summary after a survived night (and the evacuation after night 10).
## Pauses the game while open. E / Enter / Esc / the button closes it.

signal opened
signal closed
signal workbench_requested

var player: Player
var _title: Label
var _text: Label
var _button: Button
var _opened_frame: int = -1


func _ready() -> void:
	layer = 13
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box: VBoxContainer = UiKit.centered_panel(self, Vector2(170, 80))
	_title = UiKit.title("DAWN")
	_title.add_theme_color_override(&"font_color", UiKit.OBJECTIVE)
	box.add_child(_title)
	_text = UiKit.label("", 10)
	_text.name = "Summary"
	_text.custom_minimum_size = Vector2(320, 0)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override(&"separation", 6)
	box.add_child(btn_row)

	var wb_btn: Button = UiKit.button("Workbench", func() -> void:
		workbench_requested.emit())
	wb_btn.name = "WorkbenchButton"
	btn_row.add_child(wb_btn)

	_button = UiKit.button("Continue", close)
	_button.name = "Continue"
	btn_row.add_child(_button)


func bind(p: Player) -> void:
	player = p


func show_summary(s: Dictionary) -> void:
	var lines: PackedStringArray = []
	if s.get("evac", false):
		_title.text = "RESCUED"
		lines.append("At first light the convoy rolls in over the rail bridge.")
		lines.append("You survived %d nights in Ashford Lane." % int(s.night))
		lines.append("")
		_button.text = "Keep surviving"
	else:
		_title.text = "DAWN - NIGHT %d SURVIVED" % int(s.night)
		_button.text = "Continue"
	lines.append("The horde: %d   Killed tonight: %d   Left at dawn: %d" % [int(s.horde), int(s.killed), int(s.left)])
	lines.append("Boards broken: %d   Yesterday's Heat: %d" % [int(s.boards_lost), roundi(float(s.heat))])
	if s.has("score"):
		lines.append("Night bonus +%d   SCORE %d   %s" % [int(s.night_points), int(s.score),
			"NEW BEST!" if s.get("new_best", false) else "Best %d" % int(s.get("best", 0))])
	if int(s.get("restocked", 0)) > 0:
		lines.append("Fresh supplies turned up in %d places around town." % int(s.restocked))
	if not s.get("evac", false):
		lines.append("Day %d begins. Game saved." % GameState.day)
	_text.text = "\n".join(lines)
	_opened_frame = Engine.get_process_frames()
	visible = true
	if player != null:
		player.ui_open = true
	get_tree().paused = true
	_button.grab_focus.call_deferred()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if player != null:
		player.ui_open = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		close()
		get_viewport().set_input_as_handled()
