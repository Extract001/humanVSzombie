extends CanvasLayer
## Settings screen (main menu and pause menu): volume, fullscreen, V-Sync, FPS counter, key rebinding.
## Every change is applied and saved straight away (Settings autoload).

signal closed

var _tabs: TabContainer
var _master: HSlider
var _sfx: HSlider
var _music: HSlider
var _fullscreen: CheckButton
var _vsync: CheckButton
var _shadows: CheckButton
var _playtest: CheckButton
var _fps: CheckButton
var _bind_buttons: Dictionary = {}   ## action -> Button
var _waiting_for: StringName = &""   ## action being rebound, or empty
var _hint: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var box: VBoxContainer = UiKit.centered_panel(self, Vector2(190, 160))
	box.add_child(UiKit.title("SETTINGS"))
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.custom_minimum_size = Vector2(360, 240)
	box.add_child(_tabs)

	var general := VBoxContainer.new()
	general.name = "Sound & display"
	_tabs.add_child(general)
	_master = _slider(general, "Master volume")
	_sfx = _slider(general, "Effects volume")
	_music = _slider(general, "Music volume")
	_fullscreen = _check(general, "Fullscreen")
	_vsync = _check(general, "V-Sync (off can raise FPS, may tear)")
	_fps = _check(general, "Show FPS counter")
	_shadows = _check(general, "Flashlight shadows (off = faster)")
	_playtest = _check(general, "Playtest mode (local log + fun rating)")
	_playtest.toggled.connect(func(on: bool) -> void: Settings.playtest_mode = on; _save())
	_master.value_changed.connect(func(v: float) -> void: Settings.master_volume = v / 100.0; _save())
	_sfx.value_changed.connect(func(v: float) -> void: Settings.sfx_volume = v / 100.0; _save())
	_music.value_changed.connect(func(v: float) -> void: Settings.music_volume = v / 100.0; _save())
	_fullscreen.toggled.connect(func(on: bool) -> void: Settings.set_fullscreen(on))
	_vsync.toggled.connect(func(on: bool) -> void: Settings.vsync = on; _save())
	_fps.toggled.connect(func(on: bool) -> void: Settings.show_fps = on; _save())
	_shadows.toggled.connect(func(on: bool) -> void: Settings.flashlight_shadows = on; _save())

	var controls := VBoxContainer.new()
	controls.name = "Controls"
	_tabs.add_child(controls)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	controls.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for a in Settings.REBINDABLE:
		var l := UiKit.label(a[1])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var b := UiKit.button("-", func() -> void: start_rebind(a[0]))
		b.name = "Bind_" + String(a[0])
		b.custom_minimum_size = Vector2(120, 0)
		grid.add_child(b)
		_bind_buttons[a[0]] = b
	_hint = UiKit.label("Click a key, then press the new key (Esc cancels).")
	controls.add_child(_hint)
	controls.add_child(UiKit.button("Reset controls to default", func() -> void: Settings.reset_bindings(); refresh()))

	var back := UiKit.button("Back", close)
	back.name = "Back"
	box.add_child(back)
	Settings.changed.connect(refresh)


func open(controls_tab: bool = false) -> void:
	visible = true
	_tabs.current_tab = 1 if controls_tab else 0
	refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_waiting_for = &""
	visible = false
	closed.emit()


func refresh() -> void:
	_master.set_value_no_signal(Settings.master_volume * 100.0)
	_sfx.set_value_no_signal(Settings.sfx_volume * 100.0)
	_music.set_value_no_signal(Settings.music_volume * 100.0)
	_fullscreen.set_pressed_no_signal(Settings.fullscreen)
	_vsync.set_pressed_no_signal(Settings.vsync)
	_fps.set_pressed_no_signal(Settings.show_fps)
	_shadows.set_pressed_no_signal(Settings.flashlight_shadows)
	_playtest.set_pressed_no_signal(Settings.playtest_mode)
	for action in _bind_buttons:
		var b: Button = _bind_buttons[action]
		b.text = "Press a key..." if action == _waiting_for else Settings.event_text(Settings.primary_event(action))


func start_rebind(action: StringName) -> void:
	_waiting_for = action
	refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _waiting_for != &"":
		var ev: InputEvent = capture_event(event)
		if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_waiting_for = &""
			refresh()
		elif ev != null:
			Settings.rebind(_waiting_for, ev)
			_waiting_for = &""
			refresh()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()


## Turns a key press or mouse click into a clean binding (no modifiers, any device), or null.
static func capture_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := InputEventKey.new()
		k.device = -1
		k.physical_keycode = (event as InputEventKey).physical_keycode if (event as InputEventKey).physical_keycode != KEY_NONE else (event as InputEventKey).keycode
		return k
	if event is InputEventMouseButton and event.pressed:
		var m := InputEventMouseButton.new()
		m.device = -1
		m.button_index = (event as InputEventMouseButton).button_index
		return m
	return null


func _save() -> void:
	Settings.apply()
	Settings.save_settings()


func _slider(parent: Control, text: String) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := UiKit.label(text)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.name = text.replace(" ", "")
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.custom_minimum_size = Vector2(180, 12)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	return s


func _check(parent: Control, text: String) -> CheckButton:
	var c := CheckButton.new()
	c.name = text.split(" ")[0]
	c.text = text
	parent.add_child(c)
	return c
