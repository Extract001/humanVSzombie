extends CanvasLayer
## HUD: health, stamina, weapon + ammo (magazine / reserve), reload progress, kills,
## FPS (for performance/browser checks) and a placeholder notice.
## Phase 5: search progress bar, player messages, and the arrow to your death backpack.

@onready var health_bar: ProgressBar = %HealthBar
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var fps_label: Label = %FpsLabel
@onready var dark_label: Label = %DarkLabel
@onready var weapon_label: Label = %WeaponLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var reload_bar: ProgressBar = %ReloadBar
@onready var kills_label: Label = %KillsLabel
@onready var prompt_label: Label = %PromptLabel
@onready var toast_label: Label = %ToastLabel

var _player: Player
var _stamina_fill: StyleBoxFlat
var _toast_tween: Tween
var search_bar: ProgressBar
var search_label: Label
var backpack_marker: Control
var objective_label: Label
var noise_bar: ProgressBar
var noise_label: Label
var light_bar: ProgressBar
var light_label: Label
## Loudest recent noise the player made (px), shown on the meter and fading out.
var noise_level: float = 0.0
var _noise_hold: float = 0.0

const NOISE_METER_MAX: float = 480.0  # a pistol shot fills the meter
const NOISE_HOLD_TIME: float = 0.4
const NOISE_FADE_PER_SECOND: float = 400.0


func _ready() -> void:
	add_to_group(&"hud")
	prompt_label.visible = false
	toast_label.modulate.a = 0.0


func bind(player: Player) -> void:
	_player = player
	player.health.health_changed.connect(_on_health_changed)
	player.stamina_changed.connect(_on_stamina_changed)
	player.weapons.weapon_changed.connect(_on_weapon_changed)
	player.weapons.ammo_changed.connect(_on_ammo_changed)
	_stamina_fill = stamina_bar.get_theme_stylebox(&"fill").duplicate() as StyleBoxFlat
	stamina_bar.add_theme_stylebox_override(&"fill", _stamina_fill)
	_on_health_changed(player.health.current_health, player.health.max_health)
	_on_stamina_changed(player.stamina, player.stats.max_stamina)
	_on_weapon_changed(player.weapons.current, player.weapons.current_weapon())
	set_kills(0)
	player.interactable_changed.connect(func(it: Interactable) -> void:
		show_prompt(it.get_prompt() if it != null else ""))
	player.message.connect(show_toast)
	player.search_cancelled.connect(func() -> void: show_toast("Search interrupted"))
	_build_phase5_widgets()
	_build_phase6_widgets()
	NoiseSystem.noise_emitted.connect(_on_noise)
	player.flashlight_changed.connect(_on_flashlight_changed)
	_on_flashlight_changed(player.flashlight_on, player.flashlight_charge_ratio())


func _build_phase6_widgets() -> void:
	var root: Control = $Root
	noise_label = _small_label("NOISE  quiet", Vector2(8, -58))
	noise_label.name = "NoiseLabel"
	root.add_child(noise_label)
	noise_bar = _small_bar(Vector2(8, -47), Color(0.85, 0.85, 0.8))
	noise_bar.name = "NoiseBar"
	root.add_child(noise_bar)
	light_label = _small_label("LIGHT off", Vector2(8, -40))
	light_label.name = "LightLabel"
	root.add_child(light_label)
	light_bar = _small_bar(Vector2(8, -29), Color(0.95, 0.85, 0.45))
	light_bar.name = "LightBar"
	root.add_child(light_bar)


func _small_label(text: String, at: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 10)
	l.add_theme_color_override(&"font_color", Color(0.9, 0.88, 0.8))
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = at.x
	l.offset_top = at.y
	l.offset_right = at.x + 90
	l.offset_bottom = at.y + 10
	return l


func _small_bar(at: Vector2, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = at.x
	b.offset_top = at.y
	b.offset_right = at.x + 70
	b.offset_bottom = at.y + 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	b.add_theme_stylebox_override(&"fill", fill)
	b.add_theme_stylebox_override(&"background", bg)
	return b


func _on_noise(_pos: Vector2, radius: float, source: Node) -> void:
	if source != _player or radius <= 0.0:
		return
	if radius >= noise_level:
		noise_level = radius
		_noise_hold = NOISE_HOLD_TIME


## Word shown next to the meter for a noise radius.
static func noise_word(radius: float) -> String:
	if radius < 1.0:
		return "quiet"
	if radius < 100.0:
		return "low"
	if radius < 300.0:
		return "medium"
	return "LOUD"


func _on_flashlight_changed(on: bool, charge: float) -> void:
	if light_bar == null:
		return
	light_bar.value = charge * 100.0
	var spares: int = _player.inventory.count(&"battery")
	light_label.text = "LIGHT %s %d%%%s" % ["on" if on else "off", int(round(charge * 100.0)),
		("  +%d" % spares) if spares > 0 else ""]


func _build_phase5_widgets() -> void:
	var root: Control = $Root
	search_label = Label.new()
	search_label.name = "SearchLabel"
	search_label.text = "SEARCHING..."
	search_label.add_theme_font_size_override(&"font_size", 10)
	search_label.add_theme_color_override(&"font_color", Color(0.95, 0.92, 0.8))
	search_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	search_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	search_label.offset_left = -40
	search_label.offset_right = 40
	search_label.offset_top = 14
	search_label.offset_bottom = 24
	search_label.visible = false
	root.add_child(search_label)
	search_bar = ProgressBar.new()
	search_bar.name = "SearchBar"
	search_bar.show_percentage = false
	search_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	search_bar.offset_left = -20
	search_bar.offset_right = 20
	search_bar.offset_top = 25
	search_bar.offset_bottom = 28
	search_bar.visible = false
	root.add_child(search_bar)
	backpack_marker = Control.new()
	backpack_marker.name = "BackpackMarker"
	backpack_marker.set_script(load("res://scripts/ui/backpack_marker.gd"))
	backpack_marker.set("player", _player)
	root.add_child(backpack_marker)


## "[E] Open door" near the bottom of the screen; empty text hides it.
func show_prompt(text: String) -> void:
	prompt_label.text = "[E] " + text
	prompt_label.visible = text != ""


## A short message in the middle of the screen that fades out (location names, "It's locked.").
func show_toast(text: String) -> void:
	toast_label.text = text
	if _toast_tween != null:
		_toast_tween.kill()
	toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)


## Current objective under the kill counter (pale cyan, GDD §12). Empty title hides it.
func set_objective(title: String, progress: String) -> void:
	if objective_label == null:
		objective_label = UiKit.label("", 8, UiKit.OBJECTIVE)
		objective_label.name = "ObjectiveLabel"
		objective_label.position = Vector2(8, 64)
		objective_label.size = Vector2(300, 22)
		$Root.add_child(objective_label)
	objective_label.visible = title != ""
	objective_label.text = "▶ " + title + (("\n   " + progress) if progress != "" else "")


## Short fade to black and back (sleeping).
func flash_black() -> void:
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 1)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(rect)
	var t: Tween = create_tween()
	t.tween_interval(0.4)
	t.tween_property(rect, "color:a", 0.0, 0.8)
	t.tween_callback(rect.queue_free)


func set_kills(kills: int) -> void:
	kills_label.text = "KILLS %d" % kills


func _process(delta: float) -> void:
	fps_label.visible = Settings.show_fps
	fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	if _player == null:
		return
	dark_label.visible = _player.in_darkness
	reload_bar.visible = _player.weapons.is_reloading
	reload_bar.value = _player.weapons.reload_progress() * 100.0
	if search_bar != null:
		search_bar.visible = _player.is_searching()
		search_label.visible = search_bar.visible
		search_bar.value = _player.search_progress() * 100.0
		if search_bar.visible:
			# Just under the player's feet, wherever the camera puts them on screen.
			var at: Vector2 = _player.get_global_transform_with_canvas().origin
			search_label.position = at + Vector2(-40, 6)
			search_bar.position = at + Vector2(-20, 17)
	if noise_bar != null:
		if _noise_hold > 0.0:
			_noise_hold -= delta
		else:
			noise_level = maxf(0.0, noise_level - NOISE_FADE_PER_SECOND * delta)
		# Square-root scale so quiet noises (60-120 px) still show clearly next to a 480 px gunshot.
		noise_bar.value = sqrt(clampf(noise_level / NOISE_METER_MAX, 0.0, 1.0)) * 100.0
		noise_label.text = "NOISE  " + noise_word(noise_level)
	if _player.is_dead() and prompt_label.visible:
		prompt_label.visible = false
	# Live prompt text (a door switches between "Open" and "Close").
	if _player.current_interactable != null:
		var text: String = "[E] " + _player.current_interactable.get_prompt()
		if prompt_label.text != text:
			prompt_label.text = text


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	if _stamina_fill != null:
		# Greyed out while below the minimum needed to start running.
		var can_run: bool = current >= _player.stats.min_stamina_to_run
		_stamina_fill.bg_color = Color(0.85, 0.65, 0.2) if can_run else Color(0.45, 0.42, 0.38)


func _on_weapon_changed(slot: int, weapon: WeaponData) -> void:
	weapon_label.text = "[%d] %s" % [slot + 1, weapon.display_name.to_upper() if weapon else "-"]
	_on_ammo_changed(_player.weapons.loaded_rounds(), _player.weapons.reserve_for(weapon))


func _on_ammo_changed(rounds: int, reserve: int) -> void:
	var weapon: WeaponData = _player.weapons.current_weapon()
	if weapon == null or not weapon.uses_ammo():
		ammo_label.text = ""
		return
	ammo_label.text = "%d / %d" % [rounds, reserve]
	# Red when the magazine is empty, amber when low.
	var color := Color(0.88, 0.85, 0.76)
	if rounds == 0:
		color = Color(0.85, 0.25, 0.2)
	elif rounds <= weapon.magazine_size / 4:
		color = Color(0.9, 0.65, 0.25)
	ammo_label.add_theme_color_override(&"font_color", color)
