class_name ScoreKeeper
extends Node
## Fun pass: score, kill streaks, popups and blood splats.
## - Kill: zombie's score × streak (kills less than 4 s apart chain; ×2, ×3 … up to ×5).
## - Loot: +2 per item taken from a container (with a "+2 Scrap" popup).
## - Objective complete: +100.  Night survived: +50 × night number.
## Records (best score, most nights) are kept in Settings and shown at dawn and in the menu.

signal streak_changed(streak: int)

const STREAK_WINDOW_MS: int = 4000
const MAX_MULT: int = 5
const MAX_SPLATS: int = 80

var world: Node2D
var splats_root: Node2D
var player: Player
var streak: int = 0
var best_streak: int = 0
var _last_kill_ms: int = -100000
## Batch 2: characters already unlocked when this game screen opened (to spot new unlocks).
var _unlocked_before: Array[StringName] = []
var _new_unlocks: Array[StringName] = []


func setup(world_root: Node2D, splat_parent: Node2D, p: Player) -> void:
	world = world_root
	splats_root = splat_parent
	player = p
	add_to_group(&"score_listeners")
	GameState.item_taken.connect(_on_item_taken)
	_unlocked_before = Characters.unlocked_ids()


func _process(_delta: float) -> void:
	if streak > 0 and Time.get_ticks_msec() - _last_kill_ms > STREAK_WINDOW_MS:
		streak = 0
		streak_changed.emit(0)


func on_zombie_killed(z: Zombie) -> void:
	if not GameState.records_disabled:
		Settings.lifetime_kills += 1   # saved with the records (dawn, death, menu)
	var now: int = Time.get_ticks_msec()
	streak = streak + 1 if now - _last_kill_ms <= STREAK_WINDOW_MS else 1
	_last_kill_ms = now
	best_streak = maxi(best_streak, streak)
	var mult: int = mini(streak, MAX_MULT)
	var pts: int = (z.data.score if z.data != null else 10) * mult
	if GameState.night_event == NightEvents.BLOOD_MOON and GameState.phase == GameState.Phase.NIGHT:
		pts *= 2   # Batch 1: Blood Moon
	GameState.add_score(pts)
	Juice.popup(world, z.global_position, "+%d" % pts, Color(1, 0.88, 0.45) if mult == 1 else Color(1, 0.55, 0.3))
	if streak >= 2:
		AudioManager.play_ui(preload("res://assets/audio/sfx/streak.wav"), -8.0 + mini(streak, 5))
	streak_changed.emit(streak)
	_splat(z.global_position)
	if Perks.kill_heal() > 0.0 and player != null and not player.is_dead():
		player.health.heal(Perks.kill_heal())   # Slice 2: Bloodlust


func on_objective_completed() -> void:
	GameState.add_score(100)
	if player != null:
		Juice.popup(world, player.global_position + Vector2(0, -10), "+100 OBJECTIVE", Color(0.62, 0.86, 0.9), 10)


func on_night_survived(night: int) -> int:
	var pts: int = 50 * night
	GameState.add_score(pts)
	return pts


## Records. Returns true if this is a new best score.
func record() -> bool:
	if GameState.records_disabled:
		return false
	var new_best: bool = GameState.score > Settings.best_score
	Settings.best_score = maxi(Settings.best_score, GameState.score)
	Settings.best_nights = maxi(Settings.best_nights, GameState.nights_survived)
	Settings.save_settings()
	_check_unlocks()
	return new_best


## Batch 2: newly unlocked characters get a banner (once).
func _check_unlocks() -> void:
	for id in Characters.unlocked_ids():
		if not _unlocked_before.has(id):
			_unlocked_before.append(id)
			_new_unlocks.append(id)
			get_tree().call_group(&"hud", &"show_banner", "NEW SURVIVOR UNLOCKED",
				"%s - pick them in the main menu." % Characters.display_name(id))
			get_tree().call_group(&"session_log", &"log_event", "unlock", String(id))


## Unlocks since the last call (for the dawn summary).
func take_new_unlocks() -> Array[StringName]:
	_check_unlocks()
	var out: Array[StringName] = _new_unlocks.duplicate()
	_new_unlocks.clear()
	return out


func _on_item_taken(container_id: StringName, item_id: StringName, quantity: int) -> void:
	if String(container_id).begins_with("pile_") or player == null:
		return   # picking your own dropped things back up isn't new loot
	GameState.add_score(2 * quantity)
	var item: ItemData = ItemRegistry.get_item(item_id)
	var name: String = item.display_name if item != null else String(item_id)
	Juice.popup(world, player.global_position + Vector2(randf_range(-10, 10), -14), "+%d %s" % [quantity, name], Color(0.8, 0.95, 0.7), 8)


## A blood splat on the ground where a zombie died (oldest ones fade away).
func _splat(at: Vector2) -> void:
	if splats_root == null:
		return
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	var r: float = randf_range(5.0, 9.0)
	for i in 10:
		var a: float = TAU * i / 10.0
		pts.append(Vector2(cos(a), sin(a) * 0.6) * r * randf_range(0.6, 1.3))
	poly.polygon = pts
	poly.color = Color(0.32, 0.05, 0.05, 0.75)
	poly.position = at + Vector2(0, 2)
	splats_root.add_child(poly)
	while splats_root.get_child_count() > MAX_SPLATS:
		var old: Node = splats_root.get_child(0)
		splats_root.remove_child(old)
		old.queue_free()
