extends CanvasLayer
## Objective board: the chain so far. Done ✓, current ▶ (with progress and a hint), the rest hidden.

signal opened
signal closed

var tracker: ObjectiveTracker
var player: Player
var _text: RichTextLabel
var _opened_frame: int = -1


func _ready() -> void:
	layer = 12
	visible = false
	var box: VBoxContainer = UiKit.centered_panel(self, Vector2(170, 100))
	box.add_child(UiKit.title("OBJECTIVES"))
	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.custom_minimum_size = Vector2(330, 150)
	_text.add_theme_color_override(&"default_color", UiKit.TEXT)
	box.add_child(_text)
	box.add_child(UiKit.button("Close [E]", close))


func bind(p: Player, t: ObjectiveTracker) -> void:
	player = p
	tracker = t


func open() -> void:
	_opened_frame = Engine.get_process_frames()
	_text.text = board_text()
	visible = true
	player.ui_open = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	player.ui_open = false
	closed.emit()


func board_text() -> String:
	var lines: Array[String] = []
	var cur: ObjectiveData = tracker.current()
	var shown_next := false
	for o in tracker.chain():
		if tracker.is_completed(o.id):
			lines.append("[color=#8a8]✓ %s[/color]" % o.title)
		elif o == cur:
			lines.append("[b][color=#9edbe6]▶ %s[/color][/b]" % o.title)
			lines.append("   " + o.description)
			var prog: String = tracker.progress_text(o)
			if prog != "":
				lines.append("   " + prog)
			if o.hint != "":
				lines.append("   [i]%s[/i]" % o.hint)
		elif not shown_next:
			lines.append("[color=#777]• ???[/color]")
			shown_next = true
	if cur == null:
		lines.append("")
		lines.append("[color=#9edbe6]The radio works. Listen for the broadcast at the desk.[/color]")
	return "\n".join(lines)


func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"interact") or event.is_action_pressed(&"inventory"):
		close()
		get_viewport().set_input_as_handled()
