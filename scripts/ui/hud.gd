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
## Slice 1: the clock and Heat at the top centre.
var _cycle: DayCycle
var clock_label: Label
var heat_label: Label
## Fun pass: score, streak, damage flash, low-health heartbeat, goal arrow.
var score_label: Label
var streak_label: Label
var hurt_flash: TextureRect
var goal_marker: Control
## Batch 1: second arrow (supply drop) and the big announcement banner.
var drop_marker: Control
var banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
## Batch 2: banners that arrive while one is showing wait their turn; green survivor arrow.
var _banner_queue: Array = []
var survivor_marker: Control
var _heartbeat_left: float = 0.0
var _noise_hold: float = 0.0

const NOISE_METER_MAX: float = 480.0  # a pistol shot fills the meter
const NOISE_HOLD_TIME: float = 0.4
const NOISE_FADE_PER_SECOND: float = 400.0


func _ready() -> void:
	add_to_group(&"hud")
	prompt_label.visible = false
	toast_label.modulate.a = 0.0
	fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # longer text ("MEM ...") grows to the left


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
	_build_fun_widgets()
	player.health.damaged.connect(func(_a: float, _s: Node) -> void: flash_hurt())


func _build_fun_widgets() -> void:
	var root: Control = $Root
	# A red vignette: clear in the middle, red at the screen edges.
	hurt_flash = TextureRect.new()
	hurt_flash.name = "HurtFlash"
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.75, 0.0, 0.0, 1.0))
	g.add_point(0.55, Color(0.75, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	tex.width = 64
	tex.height = 64
	hurt_flash.texture = tex
	hurt_flash.stretch_mode = TextureRect.STRETCH_SCALE
	hurt_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hurt_flash.modulate.a = 0.0
	hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt_flash)
	root.move_child(hurt_flash, 0)
	score_label = UiKit.label("SCORE 0", 10, Color(1, 0.88, 0.45))
	score_label.name = "ScoreLabel"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.offset_left = -160
	score_label.offset_right = -8
	score_label.offset_top = 18
	score_label.offset_bottom = 28
	root.add_child(score_label)
	streak_label = UiKit.label("", 20, Color(1, 0.55, 0.3))
	streak_label.name = "StreakLabel"
	streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	streak_label.offset_left = -120
	streak_label.offset_right = 120
	streak_label.offset_top = 30
	streak_label.offset_bottom = 52
	streak_label.pivot_offset = Vector2(120, 11)
	streak_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	streak_label.add_theme_constant_override(&"shadow_offset_x", 2)
	streak_label.add_theme_constant_override(&"shadow_offset_y", 2)
	root.add_child(streak_label)
	goal_marker = Control.new()
	goal_marker.name = "GoalMarker"
	goal_marker.set_script(load("res://scripts/ui/goal_marker.gd"))
	root.add_child(goal_marker)
	drop_marker = Control.new()
	drop_marker.name = "DropMarker"
	drop_marker.set_script(load("res://scripts/ui/goal_marker.gd"))
	root.add_child(drop_marker)
	survivor_marker = Control.new()
	survivor_marker.name = "SurvivorMarker"
	survivor_marker.set_script(load("res://scripts/ui/goal_marker.gd"))
	root.add_child(survivor_marker)
	banner = VBoxContainer.new()
	banner.name = "Banner"
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left = -200
	banner.offset_right = 200
	banner.offset_top = 228   # below the player, clear of the objective list and the toast
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	_banner_title = UiKit.label("", 20, Color(1.0, 0.45, 0.35))
	_banner_sub = UiKit.label("", 10, UiKit.TEXT)
	for l in [_banner_title, _banner_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override(&"shadow_offset_x", 2)
		l.add_theme_constant_override(&"shadow_offset_y", 2)
		banner.add_child(l)
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_sub.custom_minimum_size = Vector2(400, 0)
	root.add_child(banner)
	# A method (not a lambda): autoload signals drop method connections when the HUD is freed.
	GameState.score_changed.connect(_on_score_changed)
	_on_score_changed(GameState.score)


func _on_score_changed(s: int) -> void:
	score_label.text = "SCORE %d" % s


## Top-right column, one line each, no overlaps: FPS (if shown) → SCORE → IN DARKNESS.
const TOP_RIGHT_LINE: float = 12.0

func _layout_top_right() -> void:
	var y: float = 6.0
	for l in [fps_label, score_label, dark_label]:
		if l == null or not l.visible:
			continue
		l.offset_top = y
		l.offset_bottom = y + 10.0
		y += TOP_RIGHT_LINE


## Fun pass: the goal arrow needs the game (objectives, safehouse, phase).
func bind_game(game: Node) -> void:
	if goal_marker != null:
		goal_marker.game = game
	if drop_marker != null and game.get("supply_drops") != null:
		drop_marker.game = game
		drop_marker.provider = game.supply_drops.target
		drop_marker.color = Color(1.0, 0.85, 0.3)
		drop_marker.ring_radius = 66.0
	if survivor_marker != null and game.get("survivors") != null:
		survivor_marker.game = game
		survivor_marker.provider = game.survivors.target
		survivor_marker.color = Color(0.5, 1.0, 0.6)
		survivor_marker.ring_radius = 80.0


## Batch 1: a big two-line announcement in the upper middle ("TONIGHT: BRUTE NIGHT").
func show_banner(title: String, subtitle: String = "") -> void:
	if banner == null:
		return
	if _banner_tween != null and _banner_tween.is_valid() and _banner_tween.is_running():
		if _banner_queue.size() < 4 and not (_banner_title.text == title and _banner_sub.text == subtitle):
			_banner_queue.append([title, subtitle])
		return
	_banner_title.text = title
	_banner_sub.text = subtitle
	if _banner_tween != null:
		_banner_tween.kill()
	banner.modulate.a = 0.0
	banner.scale = Vector2(1.15, 1.15)
	banner.pivot_offset = Vector2(200, 12)
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_property(banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(3.5)
	_banner_tween.chain().tween_property(banner, "modulate:a", 0.0, 0.8)
	_banner_tween.chain().tween_callback(_next_banner)


func _next_banner() -> void:
	_banner_tween = null
	if not _banner_queue.is_empty():
		var b: Array = _banner_queue.pop_front()
		show_banner(b[0], b[1])


func show_streak(streak: int) -> void:
	if streak_label == null:
		return
	if streak < 2:
		var fade: Tween = create_tween()
		fade.tween_property(streak_label, "modulate:a", 0.0, 0.3)
		return
	streak_label.text = "x%d STREAK!" % mini(streak, ScoreKeeper.MAX_MULT) if streak <= ScoreKeeper.MAX_MULT else "x%d STREAK! (%d)" % [ScoreKeeper.MAX_MULT, streak]
	streak_label.modulate.a = 1.0
	streak_label.scale = Vector2(1.5, 1.5)
	var t: Tween = create_tween()
	t.tween_property(streak_label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Red flash at the screen edges when you're hurt.
func flash_hurt() -> void:
	if hurt_flash == null:
		return
	hurt_flash.modulate.a = 0.65
	var t: Tween = create_tween()
	t.tween_property(hurt_flash, "modulate:a", 0.0, 0.45)


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
	# Long messages: smaller letters, wrapped on two lines (never cut off at the screen edge).
	var long: bool = text.length() > 34
	toast_label.add_theme_font_size_override(&"font_size", 10 if long else 20)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if long else TextServer.AUTOWRAP_OFF
	if _toast_tween != null:
		_toast_tween.kill()
	toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6 + text.length() / 30.0)  # longer messages stay longer
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


## Slice 1: day/night clock ("DAY 2  14:30") and Heat ("HEAT 3 - tonight ~9") at the top centre.
func bind_cycle(cycle: DayCycle) -> void:
	_cycle = cycle
	clock_label = UiKit.label("", 10)
	clock_label.name = "ClockLabel"
	heat_label = UiKit.label("", 8, Color(0.95, 0.62, 0.35))
	heat_label.name = "HeatLabel"
	for l in [clock_label, heat_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override(&"shadow_offset_x", 1)
		l.add_theme_constant_override(&"shadow_offset_y", 1)
		l.set_anchors_preset(Control.PRESET_CENTER_TOP)
		l.offset_left = -110
		l.offset_right = 110
		$Root.add_child(l)
	clock_label.offset_top = 5
	clock_label.offset_bottom = 15
	heat_label.offset_top = 16
	heat_label.offset_bottom = 25
	_update_cycle_labels()


func _event_prefix() -> String:
	return "" if GameState.night_event == NightEvents.NONE else NightEvents.title(GameState.night_event) + "  -  "


func _update_cycle_labels() -> void:
	if _cycle == null:
		return
	var night_no: int = GameState.nights_survived + 1
	match GameState.phase:
		GameState.Phase.DAY:
			clock_label.text = "DAY %d   %s" % [GameState.day, _cycle.clock_text()]
			clock_label.add_theme_color_override(&"font_color", UiKit.TEXT)
			heat_label.text = "HEAT %d  -  tonight: ~%d of them" % [roundi(GameState.heat), _cycle.horde_estimate()]
		GameState.Phase.DUSK:
			clock_label.text = "DUSK   %s   -   night in %d s" % [_cycle.clock_text(), ceili(_cycle.time_left())]
			clock_label.add_theme_color_override(&"font_color", Color(1.0, 0.7, 0.45))
			heat_label.text = "%sHEAT %d  -  tonight: ~%d of them" % [_event_prefix(), roundi(GameState.heat), _cycle.horde_estimate()]
		_:
			clock_label.text = "NIGHT %d   %s   -   dawn in %d s" % [night_no, _cycle.clock_text(), ceili(_cycle.time_left())]
			clock_label.add_theme_color_override(&"font_color", Color(0.75, 0.8, 1.0))
			heat_label.text = "%sLeft tonight: %d" % [_event_prefix(), _cycle.horde_alive()]


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
	if _cycle != null and Engine.get_process_frames() % 10 == 0:
		_update_cycle_labels()
		_layout_top_right()
	# Low health: heartbeat, and the screen edge stays faintly red.
	if _player != null and not _player.is_dead() and _player.health.current_health <= _player.health.max_health * 0.3:
		_heartbeat_left -= delta
		if _heartbeat_left <= 0.0:
			_heartbeat_left = 0.9
			AudioManager.play_ui(preload("res://assets/audio/sfx/heartbeat.wav"), -6.0)
		if hurt_flash != null and hurt_flash.modulate.a < 0.35:
			hurt_flash.modulate.a = 0.35
	elif hurt_flash != null and hurt_flash.modulate.a > 0.0 and hurt_flash.modulate.a <= 0.35:
		hurt_flash.modulate.a = 0.0
	fps_label.visible = Settings.show_fps
	if fps_label.visible:
		# Phase 11: memory next to the FPS for long play sessions (only reported by debug/editor runs).
		var mem_mb: float = OS.get_static_memory_usage() / 1048576.0
		fps_label.text = ("FPS %d  MEM %d MB" % [Engine.get_frames_per_second(), roundi(mem_mb)]) if mem_mb > 0.0 \
			else "FPS %d" % Engine.get_frames_per_second()
	if _player == null:
		return
	dark_label.visible = _player.in_darkness
	reload_bar.visible = _player.weapons.is_reloading
	reload_bar.value = _player.weapons.reload_progress() * 100.0
	if search_bar != null:
		var working: bool = _player.is_working()
		search_bar.visible = _player.is_searching() or working
		search_label.visible = search_bar.visible
		search_label.text = _player.work_label if working else "SEARCHING..."
		search_bar.value = (_player.work_progress() if working else _player.search_progress()) * 100.0
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
