extends CanvasLayer
## Pause menu (Esc): Resume / Settings / Controls / Main menu.
## Pausing stops the whole game tree: zombies, the player, timers, healing, the flashlight battery.
## Only this menu and the settings screen keep running (process_mode ALWAYS).

signal opened
signal closed

var game: Node
var resume_button: Button
var save_note: Label
## Slice 2: your perks so far.
var perks_note: Label


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box: VBoxContainer = UiKit.centered_panel(self, Vector2(100, 95))
	box.add_child(UiKit.title("PAUSED"))
	resume_button = _btn(box, "Resume", resume)
	_btn(box, "Settings", func() -> void: game.settings_menu.open(false))
	_btn(box, "Controls", func() -> void: game.settings_menu.open(true))
	_btn(box, "Main menu", func() -> void: game.go_to_main_menu())
	save_note = UiKit.label("", 10, UiKit.TEXT.darkened(0.25))
	save_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_note.custom_minimum_size = Vector2(160, 0)
	box.add_child(save_note)
	perks_note = UiKit.label("", 10, Color(1, 0.88, 0.45))
	perks_note.name = "PerksNote"
	perks_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perks_note.custom_minimum_size = Vector2(160, 0)
	box.add_child(perks_note)


func bind(g: Node) -> void:
	game = g
	game.settings_menu.closed.connect(func() -> void:
		if visible:
			resume_button.grab_focus())


func pause() -> void:
	save_note.text = "Leaving now saves the game." if game.is_in_safehouse() \
		else "Not in the safehouse: progress since the last save (safehouse, bed) will be lost."
	perks_note.text = "Perks: " + Perks.summary()
	visible = true
	get_tree().paused = true
	resume_button.grab_focus()
	opened.emit()


func resume() -> void:
	if game.settings_menu.visible:
		game.settings_menu.close()
	visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if visible:
		resume()
	elif game.can_pause():
		pause()
	else:
		return
	get_viewport().set_input_as_handled()


func _btn(parent: Control, text: String, action: Callable) -> Button:
	var b: Button = UiKit.button(text, action)
	b.name = text.replace(" ", "") + "Button"
	b.custom_minimum_size = Vector2(160, 18)
	parent.add_child(b)
	return b
