extends Control
## Main menu (GDD §12): New game / Continue / Settings / Credits / Exit.
## Continue loads the save (Phase 10); it's disabled when there is none. New game asks before replacing a save.
## Exit is hidden in the browser build (a web page can't close itself).

const GAME_SCENE := "res://scenes/main/game.tscn"

@onready var settings_menu: CanvasLayer = $SettingsMenu

var new_button: Button
var continue_button: Button
var settings_button: Button
var credits_button: Button
var exit_button: Button
var _credits: PanelContainer
var _dialog: PanelContainer
var _dialog_text: Label
var _dialog_yes: Button
var _dialog_no: Button
var _dialog_action: Callable
var save_label: Label


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Soundscape.player = null
	Soundscape.set_mood("menu")
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.045, 0.043)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var signal_art := Control.new()
	signal_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	signal_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	signal_art.draw.connect(_draw_signal.bind(signal_art))
	add_child(signal_art)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	box.offset_left = 60
	box.offset_right = 260
	box.offset_top = -110
	box.offset_bottom = 110
	box.add_theme_constant_override(&"separation", 6)
	add_child(box)
	var title := UiKit.title("LAST SIGNAL")
	title.add_theme_font_size_override(&"font_size", 30)  # 3x pixel font
	box.add_child(title)
	box.add_child(UiKit.label("Ashford Lane, day 1 of the outbreak.", 10, UiKit.TEXT.darkened(0.25)))
	box.add_child(Control.new())
	new_button = _menu_button(box, "New game", ask_new_game)
	continue_button = _menu_button(box, "Continue", continue_game)
	save_label = UiKit.label("", 10, UiKit.TEXT.darkened(0.3))
	box.add_child(save_label)
	settings_button = _menu_button(box, "Settings", func() -> void: settings_menu.open())
	credits_button = _menu_button(box, "Credits", show_credits)
	exit_button = _menu_button(box, "Exit", func() -> void: get_tree().quit())
	exit_button.visible = not OS.has_feature("web")
	var footer := UiKit.label("Early build - original art and sound", 10, Color(0.6, 0.55, 0.42))
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 8
	footer.offset_top = -16
	footer.offset_bottom = -4
	footer.offset_right = 400
	add_child(footer)
	_build_credits()
	_build_dialog()
	settings_menu.closed.connect(func() -> void: new_button.grab_focus())
	refresh_save_info()
	if continue_button.disabled:
		new_button.grab_focus()
	else:
		continue_button.grab_focus()
	var r: Dictionary = SaveSystem.read_save()
	print("LAST_SIGNAL_MENU continue=%s %s reason=%s" % [str(not continue_button.disabled), save_label.text,
		str(r.data.get("reason", "-")) if r.ok else "-"])


func refresh_save_info() -> void:
	var r: Dictionary = SaveSystem.read_save()
	continue_button.disabled = not r.ok
	continue_button.tooltip_text = "" if r.ok else "No saved game yet."
	save_label.text = SaveSystem.describe() if r.ok else ""
	save_label.visible = r.ok


func ask_new_game() -> void:
	if SaveSystem.read_save().ok:
		show_dialog("Start a new game?\nThis replaces your saved game (%s)." % SaveSystem.describe(), start_new_game, "New game", "Cancel")
	else:
		start_new_game()


func start_new_game() -> void:
	GameState.new_game()
	SaveSystem.pending_player = {}
	SaveSystem.fresh_start = true
	get_tree().change_scene_to_file(GAME_SCENE)


func continue_game() -> void:
	var r: Dictionary = SaveSystem.load_game()
	if r.ok:
		get_tree().change_scene_to_file(GAME_SCENE)
		return
	refresh_save_info()
	show_dialog(r.message + ("\nThe file was kept as save_v1.json.broken." if r.get("broken", false) else "")
		+ "\nYou can start a new game.", start_new_game, "New game", "Back")


## A small yes/no box (also used as a message with one useful choice).
func show_dialog(text: String, on_yes: Callable, yes_text: String, no_text: String) -> void:
	_dialog_text.text = text
	_dialog_action = on_yes
	_dialog_yes.text = yes_text
	_dialog_no.text = no_text
	_dialog.visible = true
	_dialog_no.grab_focus()


func _build_dialog() -> void:
	_dialog = PanelContainer.new()
	_dialog.name = "Dialog"
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dialog.offset_left = -170
	_dialog.offset_right = 170
	_dialog.offset_top = -50
	_dialog.offset_bottom = 50
	_dialog.visible = false
	add_child(_dialog)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	_dialog.add_child(box)
	_dialog_text = UiKit.label("")
	_dialog_text.name = "Text"
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(320, 40)
	box.add_child(_dialog_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_dialog_yes = UiKit.button("Yes", func() -> void:
		_dialog.visible = false
		_dialog_action.call())
	_dialog_yes.name = "Yes"
	row.add_child(_dialog_yes)
	_dialog_no = UiKit.button("No", func() -> void:
		_dialog.visible = false
		new_button.grab_focus())
	_dialog_no.name = "No"
	row.add_child(_dialog_no)


func show_credits() -> void:
	_credits.visible = true
	_credits.get_node("Box/Close").grab_focus()


func _menu_button(parent: Control, text: String, action: Callable) -> Button:
	var b: Button = UiKit.button(text, action)
	b.name = text.replace(" ", "") + "Button"
	b.custom_minimum_size = Vector2(150, 18)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(b)
	return b


## Credits, including the Godot Engine licence notice that every distributed build must show.
func _build_credits() -> void:
	_credits = PanelContainer.new()
	_credits.name = "Credits"
	_credits.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_credits.offset_left = -220
	_credits.offset_right = 220
	_credits.offset_top = -160
	_credits.offset_bottom = 160
	_credits.visible = false
	add_child(_credits)
	var box := VBoxContainer.new()
	box.name = "Box"
	_credits.add_child(box)
	box.add_child(UiKit.title("CREDITS"))
	var text := RichTextLabel.new()
	text.name = "Text"
	text.custom_minimum_size = Vector2(420, 250)
	text.scroll_active = true
	text.text = credits_text()
	box.add_child(text)
	var close := UiKit.button("Close", func() -> void: _credits.visible = false; credits_button.grab_focus())
	close.name = "Close"
	box.add_child(close)


static func credits_text() -> String:
	var lines: Array[String] = [
		"LAST SIGNAL - prototype",
		"Design and programming: the LAST SIGNAL team, with Claude (Anthropic) as development assistant.",
		"Art, animation, sound, music and the pixel font: original, made for this project from code (see ASSET_LICENSES.md).",
		"",
		"This game uses Godot Engine, available under the following license:",
		"",
		Engine.get_license_text().replace("\n\n", "\u00b6").replace("\n", " ").replace("\u00b6", "\n\n"),
		"",
		"Godot Engine includes third-party components:",
	]
	for info in Engine.get_copyright_info():
		lines.append("- " + String(info.get("name", "")))
	return "\n".join(lines)


func _draw_signal(c: Control) -> void:
	# A quiet radio-wave motif on the right side of the screen.
	var centre := Vector2(c.size.x * 0.78, c.size.y * 0.5)
	for i in 6:
		var r: float = 24.0 + i * 22.0
		c.draw_arc(centre, r, -0.6, 0.6, 24, Color(0.62, 0.86, 0.9, 0.22 - i * 0.03), 1.0)
		c.draw_arc(centre, r, PI - 0.6, PI + 0.6, 24, Color(0.62, 0.86, 0.9, 0.22 - i * 0.03), 1.0)
	c.draw_rect(Rect2(centre - Vector2(2, 2), Vector2(4, 40)), Color(0.42, 0.37, 0.28))
	c.draw_rect(Rect2(centre - Vector2(3, 3), Vector2(6, 6)), Color(0.87, 0.77, 0.47))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and _dialog.visible:
		_dialog.visible = false
		new_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause") and _credits.visible:
		_credits.visible = false
		credits_button.grab_focus()
		get_viewport().set_input_as_handled()
