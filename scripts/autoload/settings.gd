extends Node
## Settings (autoload): volume, display options and key bindings, saved to user://settings.cfg
## (on Windows: %APPDATA%\Godot\app_userdata\LAST SIGNAL\settings.cfg; in a browser: the site's storage).
## Loaded and applied at startup, saved whenever the settings screen changes something.

signal changed

const DEFAULT_PATH := "user://settings.cfg"

## Actions the player can rebind, in the order shown on the Controls tab, with their labels.
const REBINDABLE: Array = [
	[&"move_up", "Move up"], [&"move_down", "Move down"], [&"move_left", "Move left"], [&"move_right", "Move right"],
	[&"run", "Run"], [&"attack", "Attack / fire"], [&"shove", "Quick shove"], [&"reload", "Reload"],
	[&"interact", "Use / interact"], [&"flashlight", "Flashlight"], [&"inventory", "Inventory"],
	[&"weapon_1", "Weapon 1"], [&"weapon_2", "Weapon 2"], [&"weapon_3", "Weapon 3"], [&"weapon_4", "Weapon 4"],
]

var config_path: String = DEFAULT_PATH
var master_volume: float = 1.0   ## 0..1
var sfx_volume: float = 1.0      ## 0..1
var music_volume: float = 0.8    ## 0..1
## Fills the whole screen by default on desktop (browsers only allow fullscreen after a click).
var fullscreen: bool = not OS.has_feature("web")
var vsync: bool = true
var show_fps: bool = true
## Flashlight shadows (walls block the beam). Off = faster on weak graphics chips; the beam then
## shines through walls. Visual only: zombies still can't see through walls either way.
var flashlight_shadows: bool = true
## Fun pass: personal records (kept across games, saved with the settings).
var best_score: int = 0
const LAYOUT_VERSION: int = 1
const BASE_SIZE := Vector2i(640, 360)
## The most world the game shows at once (keeps fights readable on unusual screens).
const MAX_VIEW := Vector2i(860, 484)
var best_nights: int = 0

## The project's default bindings (copied at startup, before anything is changed).
var _defaults: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in REBINDABLE:
		_defaults[a[0]] = InputMap.action_get_events(a[0]).duplicate()
	load_settings()
	apply()
	# Fill any screen shape (no black bars) with sharp pixels: see fit_screen().
	get_tree().root.size_changed.connect(fit_screen)
	fit_screen()


## The base picture is 640×360. The game picks the largest whole-number zoom that fits the
## window (2× on 1366×768, 3× on 1920×1080, 4× on 2560×1440) and shows a little more of the
## world to fill the rest, so every screen is covered and pixels stay square and sharp.
## Very odd sizes (more than ~860×484 at 1×) fall back to smooth scaling of 640×360.
func fit_screen() -> void:
	var root: Window = get_tree().root
	if root.size.x <= 0 or root.size.y <= 0:
		return
	var view: Vector2i = view_for(root.size)
	if root.content_scale_size != view:
		root.content_scale_size = view


## The game's picture size for a window of `win` pixels (see fit_screen).
static func view_for(win: Vector2i) -> Vector2i:
	var zoom: int = int(floor(minf(win.x / float(BASE_SIZE.x), win.y / float(BASE_SIZE.y))))
	if zoom >= 1:
		var fitted := Vector2i(int(ceil(win.x / float(zoom))), int(ceil(win.y / float(zoom))))
		if fitted.x <= MAX_VIEW.x and fitted.y <= MAX_VIEW.y:
			return fitted
	return BASE_SIZE   # odd sizes: smooth scaling (the "expand" aspect fills the screen)


## Reads the settings file (missing file = defaults). Key bindings from the file replace the defaults.
func load_settings(path: String = config_path) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	# Settings files from before the "fill the screen" update (no layout_version) start in
	# fullscreen once; after that your own choice is kept.
	if int(cfg.get_value("display", "layout_version", 0)) >= LAYOUT_VERSION:
		fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	show_fps = bool(cfg.get_value("display", "show_fps", show_fps))
	flashlight_shadows = bool(cfg.get_value("display", "flashlight_shadows", flashlight_shadows))
	best_score = int(cfg.get_value("records", "best_score", 0))
	best_nights = int(cfg.get_value("records", "best_nights", 0))
	for a in REBINDABLE:
		if not cfg.has_section_key("controls", String(a[0])):
			continue
		var ev: Variant = cfg.get_value("controls", String(a[0]))
		if ev is InputEvent:
			_set_primary(a[0], ev)


func save_settings(path: String = config_path) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "layout_version", LAYOUT_VERSION)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "show_fps", show_fps)
	cfg.set_value("display", "flashlight_shadows", flashlight_shadows)
	cfg.set_value("records", "best_score", best_score)
	cfg.set_value("records", "best_nights", best_nights)
	for a in REBINDABLE:
		var ev: InputEvent = primary_event(a[0])
		if ev != null and not _same(ev, _default_primary(a[0])):
			cfg.set_value("controls", String(a[0]), ev)
	cfg.save(path)


## Applies volume and display settings to the engine.
func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	var sfx: int = AudioServer.get_bus_index(&"SFX")
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(sfx_volume, 0.0001)))
	var music: int = AudioServer.get_bus_index(&"Music")
	if music >= 0:
		AudioServer.set_bus_volume_db(music, linear_to_db(maxf(music_volume, 0.0001)))
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		var want: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	changed.emit()


## The browser only allows fullscreen from a click, so the settings screen calls this directly.
func set_fullscreen(on: bool) -> void:
	fullscreen = on
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	apply()
	save_settings()


## The first event of an action (the one shown and rebound on the Controls tab).
func primary_event(action: StringName) -> InputEvent:
	var evs: Array[InputEvent] = InputMap.action_get_events(action)
	return evs[0] if not evs.is_empty() else null


## Rebinds an action's primary key/button. If another rebindable action used the same input,
## that action gets this action's old input (a swap), so no action is ever left unbound.
func rebind(action: StringName, ev: InputEvent) -> void:
	var old: InputEvent = primary_event(action)
	for a in REBINDABLE:
		if a[0] != action and _same(primary_event(a[0]), ev) and old != null:
			_set_primary(a[0], old)
	_set_primary(action, ev)
	save_settings()
	changed.emit()


func reset_bindings(save: bool = true) -> void:
	for a in REBINDABLE:
		InputMap.action_erase_events(a[0])
		for ev in _defaults[a[0]]:
			InputMap.action_add_event(a[0], ev)
	if save:
		save_settings()
	changed.emit()


static func event_text(ev: InputEvent) -> String:
	if ev == null:
		return "-"
	if ev is InputEventKey:
		var k: InputEventKey = ev
		var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Left mouse"
			MOUSE_BUTTON_RIGHT: return "Right mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle mouse"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
		return "Mouse %d" % (ev as InputEventMouseButton).button_index
	return ev.as_text()


func _set_primary(action: StringName, ev: InputEvent) -> void:
	var evs: Array[InputEvent] = InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)
	for i in range(1, evs.size()):  # keep secondary bindings (e.g. I for the inventory)
		if not _same(evs[i], ev):
			InputMap.action_add_event(action, evs[i])


func _default_primary(action: StringName) -> InputEvent:
	var d: Array = _defaults.get(action, [])
	return d[0] if not d.is_empty() else null


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a is InputEventKey and b is InputEventKey:
		var ka: Key = (a as InputEventKey).physical_keycode if (a as InputEventKey).physical_keycode != KEY_NONE else (a as InputEventKey).keycode
		var kb: Key = (b as InputEventKey).physical_keycode if (b as InputEventKey).physical_keycode != KEY_NONE else (b as InputEventKey).keycode
		return ka == kb
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false
