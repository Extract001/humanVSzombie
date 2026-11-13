class_name DayCycle
extends Node
## Slice 1 — the day/night cycle and the night siege (GDD §16).
##
## DAY (scavenge) → DUSK (get home, board up) → NIGHT (the horde attacks the safehouse) → dawn:
## the horde leaves, a summary screen, the night counts as survived, Heat resets, some emptied
## containers are restocked, autosave. The clock state lives in GameState (saved).
##
## Heat ("the town listens"): loud noises (≥ 200 px) during the day and dusk raise Heat;
## the horde = base + per_night × night + per_heat × Heat, capped so that no more than
## max_zombies_total Walkers are awake.
## Created by game.gd at runtime (no scene change needed).

signal phase_changed(phase: int)
## A night was survived. summary: night, horde, killed, boards_lost, heat, restocked, evac.
signal dawn(summary: Dictionary)

const WALKER: PackedScene = preload("res://scenes/zombies/walker.tscn")
## Horde Walkers never appear closer than this to the player (they walk in from the edges).
const MIN_SPAWN_DISTANCE: float = 360.0
## Fun pass: a quarter of the night horde are fast Lurchers.
const LURCHER: ZombieData = preload("res://data/zombies/lurcher.tres")
const LURCHER_SHARE: float = 0.25
## Batch 1: special zombies and events.
const BRUTE: ZombieData = preload("res://data/zombies/brute.tres")
const SCREAMER: ZombieData = preload("res://data/zombies/screamer.tres")
signal night_event_announced(id: StringName)
## Brutes still to place tonight (Brute night).
var _brutes_left: int = 0
## Batch 2: windows broken tonight (survivors can die when the horde breaks in).
var _breaches: int = 0

var data: SiegeData = preload("res://data/siege/siege_data.tres")
var game: Node
var player: Player
var actors: Node2D
var tint: CanvasModulate
var lamp: PointLight2D

## Horde Walkers still to spawn tonight: seconds into the night when each arrives.
var _spawn_times: Array[float] = []
var _horde: Array[Zombie] = []
var _night_kills: int = 0
var _night_horde_size: int = 0
var _boards_at_dusk: int = 0
var _heat_at_dusk: float = 0.0


func setup(game_root: Node, p: Player, actors_root: Node2D, world: Node2D) -> void:
	game = game_root
	player = p
	actors = actors_root
	tint = CanvasModulate.new()
	tint.name = "NightTint"
	world.add_child(tint)
	lamp = PointLight2D.new()
	lamp.name = "SafehouseLamp"
	lamp.texture = _radial_texture()
	lamp.texture_scale = 3.2
	lamp.energy = 0.9
	lamp.color = Color(1.0, 0.82, 0.55)
	lamp.position = Vector2(78.5, 71.5) * 16.0
	lamp.range_item_cull_mask = 1 | 2
	world.add_child(lamp)
	NoiseSystem.noise_emitted.connect(_on_noise)
	for b in get_tree().get_nodes_in_group(&"barricades"):
		(b as Barricade).broken.connect(func() -> void:
			if GameState.phase == GameState.Phase.NIGHT:
				_breaches += 1)
	# A save made at dusk or during the night (e.g. a death) restarts at the beginning of dusk.
	if GameState.phase != GameState.Phase.DAY:
		GameState.phase = GameState.Phase.DUSK
		GameState.phase_time = 0.0
		_boards_at_dusk = _total_boards()
		_heat_at_dusk = GameState.heat
	_apply_look()


func _physics_process(delta: float) -> void:
	if player == null or player.is_dead():
		return
	GameState.phase_time += delta
	match GameState.phase:
		GameState.Phase.DAY:
			if GameState.phase_time >= day_length():
				start_dusk()
		GameState.Phase.DUSK:
			if GameState.phase_time >= data.dusk_length:
				start_night()
		GameState.Phase.NIGHT:
			while not _spawn_times.is_empty() and GameState.phase_time >= _spawn_times[0]:
				_spawn_times.pop_front()
				_spawn_horde_walker()
			if GameState.phase_time >= data.night_length:
				end_night()
	_apply_look()


# ---------------- phases ----------------

func start_dusk() -> void:
	GameState.phase = GameState.Phase.DUSK
	GameState.phase_time = 0.0
	_boards_at_dusk = _total_boards()
	_heat_at_dusk = GameState.heat
	GameState.night_event = NightEvents.pick(GameState.nights_survived + 1, GameState.night_event, GameState.world_seed)
	AudioManager.play_ui(preload("res://assets/audio/sfx/dusk_bell.wav"), -2.0)
	if GameState.night_event != NightEvents.NONE:
		AudioManager.play_ui(preload("res://assets/audio/sfx/event_sting.wav"), -1.0)
		get_tree().call_group(&"hud", &"show_banner", "TONIGHT: " + NightEvents.title(GameState.night_event),
			NightEvents.description(GameState.night_event))
	_toast("Dusk. About %d of them will come tonight. Get inside and board up." % horde_estimate())
	night_event_announced.emit(GameState.night_event)
	phase_changed.emit(GameState.phase)


func start_night() -> void:
	GameState.phase = GameState.Phase.NIGHT
	GameState.phase_time = 0.0
	_night_kills = 0
	_heat_at_dusk = GameState.heat
	_night_horde_size = horde_estimate()
	_spawn_times.clear()
	for i in _night_horde_size:
		# Spread over the first part of the night, a little bunched toward the start.
		var t: float = pow(float(i) / maxf(1.0, _night_horde_size), 1.3) * data.night_length * data.arrival_share
		_spawn_times.append(t + randf_range(0.0, 2.0))
	_spawn_times.sort()
	_brutes_left = (1 + GameState.nights_survived / 4) if GameState.night_event == NightEvents.BRUTES else 0
	_brutes_left = maxi(_brutes_left, DailyChallenge.forced_brutes())
	_breaches = 0
	AudioManager.play_ui(preload("res://assets/audio/sfx/horde_howl.wav"), -1.0)
	_toast("Night %d. They're coming." % (GameState.nights_survived + 1))
	phase_changed.emit(GameState.phase)


func end_night() -> void:
	_spawn_times.clear()
	# The horde shambles off into the morning fog (and its dead are cleared, so corpses
	# don't pile up night after night).
	var gone := 0
	for z in _horde:
		if is_instance_valid(z):
			if z.state != Zombie.State.DEAD:
				gone += 1
			z.queue_free()
	_horde.clear()
	GameState.nights_survived += 1
	GameState.day += 1
	GameState.phase = GameState.Phase.DAY
	GameState.phase_time = 0.0
	var restocked: int = restock_town()
	var summary := {
		"night": GameState.nights_survived,
		"horde": _night_horde_size,
		"killed": _night_kills,
		"left": gone,
		"boards_lost": maxi(0, _boards_at_dusk - _total_boards()),
		"heat": _heat_at_dusk,
		"restocked": restocked,
		"breaches": _breaches,
		"evac": GameState.nights_survived >= data.nights_to_win and GameState.has_unlock(&"radio_repaired"),
	}
	GameState.reset_heat()
	_apply_look()
	phase_changed.emit(GameState.phase)
	dawn.emit(summary)


## Seconds of daylight (Batch 2: the daily twist "Short Days" cuts it).
func day_length() -> float:
	return data.day_length * DailyChallenge.day_length_mult()


## Skip the rest of the day (the bed). Only during the day.
func skip_to_dusk() -> bool:
	if GameState.phase != GameState.Phase.DAY:
		return false
	start_dusk()
	return true


func is_night() -> bool:
	return GameState.phase == GameState.Phase.NIGHT


## Expected horde size if night fell now (the HUD shows this all day).
func horde_estimate() -> int:
	var night: int = GameState.nights_survived + 1
	var n: int = data.horde_base + roundi(data.horde_per_night * (night - 1) + data.horde_per_heat * GameState.heat)
	if GameState.phase != GameState.Phase.DAY:
		n = roundi(n * NightEvents.horde_mult(GameState.night_event))
	n = roundi(n * DailyChallenge.horde_mult())
	var awake := 0
	for z in get_tree().get_nodes_in_group(&"zombies"):
		if (z as Zombie).state != Zombie.State.DEAD:
			awake += 1
	return clampi(n, 0, maxi(0, data.max_zombies_total - awake))


## 06:00 at the start of the day, 18:00 at dusk, 20:00 at night, 05:00 at the end of the night.
func clock_minutes() -> int:
	var t: float = GameState.phase_time
	match GameState.phase:
		GameState.Phase.DAY:
			return int(6 * 60 + 12 * 60 * clampf(t / day_length(), 0.0, 1.0))
		GameState.Phase.DUSK:
			return int(18 * 60 + 2 * 60 * clampf(t / data.dusk_length, 0.0, 1.0))
		_:
			return int(20 * 60 + 9 * 60 * clampf(t / data.night_length, 0.0, 1.0)) % (24 * 60)


func clock_text() -> String:
	var m: int = clock_minutes()
	return "%02d:%02d" % [m / 60, m % 60]


## Seconds until the next phase change.
func time_left() -> float:
	match GameState.phase:
		GameState.Phase.DAY:
			return day_length() - GameState.phase_time
		GameState.Phase.DUSK:
			return data.dusk_length - GameState.phase_time
		_:
			return data.night_length - GameState.phase_time


func horde_alive() -> int:
	var n := 0
	for z in _horde:
		if is_instance_valid(z) and z.state != Zombie.State.DEAD:
			n += 1
	return n + _spawn_times.size()


# ---------------- horde ----------------

func _spawn_horde_walker() -> void:
	var map: Node = game.get_node("World/Map")
	var spawns: Array = []
	var holder: Node = map.get_node_or_null("HordeSpawns")
	if holder != null:
		for m in holder.get_children():
			if (m as Node2D).global_position.distance_to(player.global_position) >= min_spawn_distance():
				spawns.append(m)
	if spawns.is_empty():
		return
	var at: Vector2 = (spawns[randi() % spawns.size()] as Node2D).global_position + Vector2(randf_range(-12, 12), randf_range(-12, 12))
	var z: Zombie = WALKER.instantiate()
	match GameState.night_event:
		NightEvents.BRUTES:
			if _brutes_left > 0:
				_brutes_left -= 1
				z.data = BRUTE
		NightEvents.SCREAMERS:
			if randf() < 0.3:
				z.data = SCREAMER
		NightEvents.FOG:
			if randf() < 0.5:
				z.data = LURCHER
	if _brutes_left > 0 and GameState.night_event != NightEvents.BRUTES:
		_brutes_left -= 1   # Batch 2: daily twist "Heavy Hitters"
		z.data = BRUTE
	if z.data == null or z.data.id == &"walker":
		if randf() < LURCHER_SHARE:
			z.data = LURCHER
	z.position = at
	z.siege_goal = _pick_window_goal(at)
	actors.add_child(z)
	z.add_to_group(&"horde")
	z.died.connect(func() -> void: _night_kills += 1)
	_horde.append(z)


## Never in view, whatever the screen shape (the visible area grows on wide screens).
func min_spawn_distance() -> float:
	var half_diag: float = player.get_viewport().get_visible_rect().size.length() * 0.5
	return maxf(MIN_SPAWN_DISTANCE, half_diag + 30.0)


## A point just inside one of the safehouse windows (nearest windows more likely).
func _pick_window_goal(from: Vector2) -> Vector2:
	var windows: Array = get_tree().get_nodes_in_group(&"barricades")
	if windows.is_empty():
		return Vector2(78.5, 71.5) * 16.0
	windows.sort_custom(func(a: Barricade, b: Barricade) -> bool:
		return a.center().distance_squared_to(from) < b.center().distance_squared_to(from))
	var pick: Barricade = windows[0] if randf() < 0.6 or windows.size() == 1 else windows[randi() % windows.size()]
	var inward: Vector2 = pick.center().direction_to(Vector2(78.5, 71.5) * 16.0)
	return pick.center() + inward * 20.0


func _total_boards() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group(&"barricades"):
		n += (b as Barricade).planks()
	return n


# ---------------- heat, restock, look ----------------

func _on_noise(_at: Vector2, radius: float, source: Node) -> void:
	if GameState.phase == GameState.Phase.NIGHT or source is Zombie or radius < data.heat_min_radius:
		return
	GameState.add_heat(radius / data.heat_radius_per_point)


## Morning: a few emptied town containers get new loot (never quest containers or piles).
func restock_town() -> int:
	var empty: Array = []
	for c in get_tree().get_nodes_in_group(&"loot_containers"):
		var lc := c as LootContainer
		if lc == null or lc.is_pile or not lc.all_guaranteed_items().is_empty():
			continue
		if GameState.is_rolled(lc.container_id) and GameState.get_contents(lc.container_id).is_empty():
			empty.append(lc.container_id)
	empty.shuffle()
	var pick: Array = empty.slice(0, data.restock_per_dawn)
	GameState.restock(pick)
	return pick.size()


func _apply_look() -> void:
	if tint == null:
		return
	var t: float = GameState.phase_time
	var c := Color.WHITE
	match GameState.phase:
		GameState.Phase.DAY:
			var late: float = clampf((t - day_length() * 0.85) / (day_length() * 0.15), 0.0, 1.0)
			c = Color.WHITE.lerp(data.dusk_tint, late)
		GameState.Phase.DUSK:
			c = data.dusk_tint.lerp(NightEvents.night_tint(GameState.night_event, data.night_tint), clampf(t / data.dusk_length, 0.0, 1.0))
		GameState.Phase.NIGHT:
			var morning: float = clampf((t - (data.night_length - 8.0)) / 8.0, 0.0, 1.0)
			c = NightEvents.night_tint(GameState.night_event, data.night_tint).lerp(data.dusk_tint, morning)
	tint.color = c
	var dark: bool = c.v < 0.75
	lamp.enabled = c != Color.WHITE and not DailyChallenge.lamp_dead() \
		and not (GameState.night_event == NightEvents.BLACKOUT and GameState.phase != GameState.Phase.DAY)
	if player != null:
		player.set_outdoor_dark(dark and not game.is_in_safehouse())


func _toast(text: String) -> void:
	get_tree().call_group(&"hud", &"show_toast", text)


static func _radial_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex
