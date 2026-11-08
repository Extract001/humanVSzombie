class_name Player
extends CharacterBody2D
## The survivor: movement, stamina, combat states, quick shove, health.
## Numbers come from `stats` (data/player/player_stats.tres) and the weapons' WeaponData.
##
## State machine (TECHNICAL_ARCHITECTURE §4.3):
##   NORMAL → ATTACKING (attack) → NORMAL after weapon.attack_duration
##   NORMAL → RELOADING (R, or attack with empty magazine) → NORMAL when the reload completes
##   RELOADING → SHOVING / NORMAL on shove / weapon switch (reload cancelled, no ammo moved)
##   NORMAL → SHOVING (Space) → NORMAL after shove_duration
##   any living state → HURT on a heavy hit (≥ heavy_hit_threshold) → NORMAL after hurt_duration
##   any → DEAD at 0 health
## Damage never depends on state (only DEAD ignores it): there are no invincibility frames.
##
## Searching a container (Phase 5) is NOT a state: it's a timer that runs while the player stands
## still in NORMAL. Moving, attacking, reloading, shoving, switching weapons or being hit cancels it.

signal died
signal stamina_changed(current: float, maximum: float)
signal state_changed(new_state: State)
## The door/container the player would use with E right now (null = nothing in reach).
signal interactable_changed(interactable: Interactable)
signal search_started(container: LootContainer, duration: float)
signal search_cancelled
## A container/pile is open for taking items (the loot panel shows it).
signal loot_opened(container: LootContainer)
## Something to tell the player ("Already at full health", "Can't drop quest items").
signal message(text: String)
## Emitted on death after carried items were moved into a backpack (empty id = nothing carried).
signal backpack_dropped(pile_id: StringName)
signal respawned
## Flashlight switched on/off or its battery changed. charge = 0..1 of the battery in the light.
signal flashlight_changed(on: bool, charge: float)

enum State { NORMAL, ATTACKING, RELOADING, SHOVING, HURT, DEAD }

const ATTACK_ORIGIN_OFFSET := Vector2(0, -7)
## Interactables must be roughly in front of the player (within ~78° of the aim).
const INTERACT_FACING_DOT: float = 0.2

@export var stats: PlayerStats
## Off in automated tests, so the (absent) mouse doesn't change facing.
@export var use_mouse_aim: bool = true

var state: State = State.NORMAL
var stamina: float = 100.0
var is_running: bool = false
var aim_direction: Vector2 = Vector2.DOWN
var in_darkness: bool = false
## When set (not Vector2.INF), replaces keyboard movement. Used by test bots now,
## and by an on-screen joystick later (mobile).
var move_override: Vector2 = Vector2.INF
var current_interactable: Interactable = null
## Set by the loot/inventory panels: mouse clicks and E/Space go to the UI instead of the player.
var ui_open: bool = false
var searching_container: LootContainer = null

var _search_left: float = 0.0
var _search_total: float = 0.0
var _heal_left: float = 0.0
var _heal_rate: float = 0.0

var _regen_delay_left: float = 0.0
var _darkness_zones: int = 0
var _state_left: float = 0.0
var _shove_cooldown_left: float = 0.0
var _swing_offset: float = 0.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var health: HealthComponent = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var camera: Camera2D = $Camera
@onready var adaptation_light: PointLight2D = $AdaptationLight
@onready var inventory: Inventory = $Inventory
@onready var weapons: WeaponHolder = $Weapons
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: Sprite2D = $WeaponPivot/WeaponSprite
@onready var muzzle_light: PointLight2D = $WeaponPivot/MuzzleLight
@onready var muzzle_flash: Sprite2D = $WeaponPivot/MuzzleFlash
@onready var interactor: Area2D = $Interactor
@onready var flashlight: PointLight2D = $Flashlight

var flashlight_on: bool = false
var _run_noise_left: float = 0.0


func _ready() -> void:
	if stats == null:
		stats = PlayerStats.new()
	add_to_group(&"player")
	stamina = stats.max_stamina
	health.setup(stats.max_health)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	adaptation_light.enabled = false
	muzzle_light.enabled = false
	weapons.setup(self, inventory)
	weapons.weapon_changed.connect(_on_weapon_changed)
	weapons.reload_finished.connect(_on_reload_finished)
	weapons.attacked.connect(_on_weapon_attacked)
	# Every attack makes noise (pistol 480 px, bat swing 90 px): zombies come to investigate.
	weapons.attacked.connect(func(origin: Vector2, weapon: WeaponData) -> void:
		NoiseSystem.emit_noise(origin, weapon.noise_radius, self))
	weapons.dry_fired.connect(func() -> void:
		AudioManager.play_at(preload("res://assets/audio/sfx/dry_fire.wav"), global_position))
	_on_weapon_changed(weapons.current, weapons.current_weapon())
	sprite.play(&"idle_down")
	flashlight.enabled = false
	sprite.frame_changed.connect(_on_sprite_frame_changed)
	_apply_graphics_settings()
	Settings.changed.connect(_apply_graphics_settings)


func _physics_process(delta: float) -> void:
	weapons.tick(delta)
	_shove_cooldown_left = maxf(0.0, _shove_cooldown_left - delta)
	if state == State.DEAD:
		velocity = velocity.move_toward(Vector2.ZERO, stats.friction * delta)
		move_and_slide()
		return
	_update_state_timer(delta)
	_update_healing(delta)

	# get_vector() already limits length to 1.0, so diagonals are not faster.
	var input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if move_override != Vector2.INF:
		input = move_override.limit_length(1.0)
	_update_aim()
	update_stamina(delta, Input.is_action_pressed(&"run"), input != Vector2.ZERO)
	_update_run_noise(delta)
	_update_flashlight(delta)
	var weapon: WeaponData = weapons.current_weapon()
	if weapon != null and weapon.automatic and Input.is_action_pressed(&"attack"):
		try_attack()

	var speed: float = (stats.run_speed if is_running else stats.walk_speed) * _speed_multiplier()
	if input != Vector2.ZERO:
		velocity = velocity.move_toward(input * speed, stats.acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, stats.friction * delta)
	move_and_slide()
	_update_animation(input != Vector2.ZERO)
	_update_interactable()
	_update_search(delta, input != Vector2.ZERO)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.DEAD or ui_open:
		return
	if event.is_action_pressed(&"attack"):
		var weapon: WeaponData = weapons.current_weapon()
		if weapon != null and not weapon.automatic:
			try_attack()
	elif event.is_action_pressed(&"interact"):
		try_interact()
	elif event.is_action_pressed(&"reload"):
		try_reload()
	elif event.is_action_pressed(&"shove"):
		try_shove()
	elif event.is_action_pressed(&"flashlight"):
		toggle_flashlight()
	elif event.is_action_pressed(&"weapon_1"):
		try_switch(0)
	elif event.is_action_pressed(&"weapon_2"):
		try_switch(1)
	elif event.is_action_pressed(&"weapon_3"):
		try_switch(2)
	elif event.is_action_pressed(&"weapon_next"):
		try_cycle(1)
	elif event.is_action_pressed(&"weapon_prev"):
		try_cycle(-1)


# ---------------- actions (public: used by input and by tests) ----------------

func try_attack() -> bool:
	if state != State.NORMAL:
		return false
	cancel_search()
	if weapons.should_auto_reload():
		return try_reload()
	if not weapons.attack(global_position + ATTACK_ORIGIN_OFFSET, aim_direction):
		return false
	_set_state(State.ATTACKING, weapons.current_weapon().attack_duration)
	return true


func try_reload() -> bool:
	if state != State.NORMAL:
		return false
	cancel_search()
	if not weapons.start_reload():
		return false
	_set_state(State.RELOADING)
	return true


func try_shove() -> bool:
	if state != State.NORMAL and state != State.RELOADING:
		return false
	if _shove_cooldown_left > 0.0 or stamina < stats.shove_stamina_cost:
		return false
	cancel_search()
	weapons.cancel_reload()
	spend_stamina(stats.shove_stamina_cost)
	_shove_cooldown_left = stats.shove_cooldown
	_set_state(State.SHOVING, stats.shove_duration)
	var origin: Vector2 = global_position + ATTACK_ORIGIN_OFFSET
	var targets: Array[Hurtbox] = WeaponHolder.find_targets_in_cone(self, origin, aim_direction,
		stats.shove_range + WeaponHolder.TARGET_RADIUS, stats.shove_arc_degrees)
	for hb in targets:
		var push: Vector2 = origin.direction_to(hb.global_position) * stats.shove_knockback_speed
		hb.receive_hit(stats.shove_damage, self, push, stats.shove_stagger_time)
	AudioManager.play_at(preload("res://assets/audio/sfx/shove.wav"), global_position)
	NoiseSystem.emit_noise(global_position, stats.shove_noise_radius, self)
	if not targets.is_empty():
		AudioManager.play_at(preload("res://assets/audio/sfx/melee_hit.wav"), targets[0].global_position, -4.0)
		_shake_camera(2.0)
	# The shove animation plays; the sprite also lunges a little toward the aim.
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "position", aim_direction * 3.0, 0.08)
	tween.tween_property(sprite, "position", Vector2.ZERO, 0.17)
	return true


func try_switch(slot: int) -> bool:
	if state != State.NORMAL and state != State.RELOADING:
		return false
	if not weapons.switch_to(slot):
		return false
	cancel_search()
	_set_state(State.NORMAL)
	return true


func try_cycle(step: int) -> bool:
	if state != State.NORMAL and state != State.RELOADING:
		return false
	if not weapons.cycle(step):
		return false
	cancel_search()
	_set_state(State.NORMAL)
	return true


func try_interact() -> bool:
	if state != State.NORMAL or current_interactable == null or is_searching():
		return false
	current_interactable.interact(self)
	return true


# ---------------- searching & items (Phase 5) ----------------

func is_searching() -> bool:
	return searching_container != null


## 0..1 progress of the current search (for the HUD bar).
func search_progress() -> float:
	if not is_searching() or _search_total <= 0.0:
		return 0.0
	return 1.0 - _search_left / _search_total


## Starts searching a container. Returns false if the player can't search right now.
func start_search(container: LootContainer, duration: float) -> bool:
	if state != State.NORMAL or container == null:
		return false
	if duration <= 0.0:
		container.open_contents()
		open_loot(container)
		return true
	searching_container = container
	_search_total = duration
	_search_left = duration
	NoiseSystem.emit_noise(global_position, LootContainer.SEARCH_NOISE_RADIUS, self)
	AudioManager.play_at(preload("res://assets/audio/sfx/search.wav"), global_position, -4.0)
	search_started.emit(container, duration)
	return true


## Stops a search in progress; nothing is granted.
func cancel_search() -> void:
	if searching_container == null:
		return
	searching_container = null
	_search_left = 0.0
	search_cancelled.emit()


func open_loot(container: LootContainer) -> void:
	loot_opened.emit(container)


func _update_search(delta: float, is_moving: bool) -> void:
	if searching_container == null:
		return
	if is_moving or state != State.NORMAL or not is_instance_valid(searching_container):
		cancel_search()
		return
	_search_left -= delta
	if _search_left <= 0.0:
		var container: LootContainer = searching_container
		searching_container = null
		container.open_contents()
		open_loot(container)


## Uses one item from the bag (bandage, medicine). Returns false if it can't be used now.
func use_item(item_id: StringName) -> bool:
	var item: ItemData = ItemRegistry.get_item(item_id)
	if item == null or not item.is_usable() or is_dead() or inventory.count(item_id) <= 0:
		return false
	if health.current_health >= health.max_health:
		message.emit("Already at full health")
		return false
	inventory.remove_item(item_id, 1)
	if item.heal_duration > 0.0:
		_heal_left += item.heal_amount
		_heal_rate = maxf(_heal_rate, item.heal_amount / item.heal_duration)
	else:
		health.heal(item.heal_amount)
	AudioManager.play_at(preload("res://assets/audio/sfx/use_item.wav"), global_position, -4.0)
	return true


## Drops items on the floor as a pile (quest items can't be dropped). Returns how many were dropped.
func drop_item(item_id: StringName, quantity: int) -> int:
	var item: ItemData = ItemRegistry.get_item(item_id)
	if item == null or not item.can_drop():
		message.emit("Quest items can't be dropped")
		return 0
	var removed: int = inventory.remove_item(item_id, quantity)
	if removed > 0:
		GameState.create_pile(snap_to_navigation(global_position + aim_direction * 8.0),
			[{"id": item_id, "qty": removed}], false)
	return removed


## Closest walkable point (so piles/backpacks are never inside a wall). Unchanged if there's no navigation.
func snap_to_navigation(pos: Vector2) -> Vector2:
	var map: RID = get_world_2d().navigation_map
	if NavigationServer2D.map_get_regions(map).is_empty():
		return pos
	return NavigationServer2D.map_get_closest_point(map, pos)


## Save data (Phase 10). Equipment = weapons with their loaded rounds; the flashlight's battery is in GameState.
func to_save_dict() -> Dictionary:
	return {
		"x": global_position.x, "y": global_position.y,
		"dead": is_dead(),
		"health": health.current_health,
		"inventory": inventory.to_array(),
		"rounds_in_mag": weapons.rounds_in_mag.duplicate(),
		"weapon": weapons.current,
	}


## Restores saved player data. A player saved dead (death autosave) wakes up at `respawn_at`.
func apply_save_dict(d: Dictionary, respawn_at: Vector2) -> void:
	inventory.from_array(d.get("inventory", []))
	var mags: Array = d.get("rounds_in_mag", [])
	for i in mini(mags.size(), weapons.rounds_in_mag.size()):
		weapons.rounds_in_mag[i] = clampi(int(mags[i]), 0, weapons.slots[i].magazine_size)
	var slot: int = int(d.get("weapon", 0))
	if slot != weapons.current and slot >= 0 and slot < weapons.slots.size():
		weapons.switch_to(slot)
	if bool(d.get("dead", false)):
		respawn(respawn_at, stats.respawn_health)
	else:
		respawn(Vector2(float(d.get("x", respawn_at.x)), float(d.get("y", respawn_at.y))),
			clampf(float(d.get("health", stats.max_health)), 1.0, stats.max_health))
	weapons.emit_signal(&"ammo_changed", weapons.loaded_rounds(), weapons.reserve_for(weapons.current_weapon()))


## Back on your feet at the safehouse: given health, NORMAL state, full stamina, weapons as they were.
func respawn(at: Vector2, start_health: float) -> void:
	global_position = at
	velocity = Vector2.ZERO
	health.setup(stats.max_health, start_health)
	stamina = stats.max_stamina
	stamina_changed.emit(stamina, stats.max_stamina)
	_regen_delay_left = 0.0
	_heal_left = 0.0
	_shove_cooldown_left = 0.0
	is_running = false
	hurtbox.set_deferred("monitorable", true)
	sprite.rotation = 0.0
	sprite.modulate = Color.WHITE
	weapon_pivot.visible = true
	_set_state(State.NORMAL)
	sprite.play(&"idle_down")
	camera.reset_smoothing()
	respawned.emit()


func _update_healing(delta: float) -> void:
	if _heal_left <= 0.0:
		_heal_rate = 0.0
		return
	var amount: float = minf(_heal_left, _heal_rate * delta)
	_heal_left -= amount
	health.heal(amount)
	if health.current_health >= health.max_health:
		_heal_left = 0.0


## Picks the closest interactable in reach that the player is facing.
func _update_interactable() -> void:
	var best: Interactable = null
	var best_dist := INF
	for area in interactor.get_overlapping_areas():
		var it := area as Interactable
		if it == null or not it.is_visible_in_tree():
			continue
		var shape := it.get_child(0) as CollisionShape2D
		var center: Vector2 = shape.global_position if shape != null else it.global_position
		var to_it: Vector2 = center - global_position
		var dist: float = to_it.length()
		if dist > 10.0 and aim_direction.dot(to_it / dist) < INTERACT_FACING_DOT:
			continue
		if dist < best_dist:
			best = it
			best_dist = dist
	if best != current_interactable:
		current_interactable = best
		interactable_changed.emit(best)


func shove_ready() -> bool:
	return _shove_cooldown_left <= 0.0


# ---------------- stamina ----------------

## Stamina rules (GDD §5). Public so tests can drive it frame by frame.
func update_stamina(delta: float, wants_run: bool, is_moving: bool) -> void:
	var before: float = stamina
	var can_keep_running: bool = is_running and stamina > 0.0
	var can_start_running: bool = stamina >= stats.min_stamina_to_run
	is_running = wants_run and is_moving and state == State.NORMAL \
		and (can_keep_running or can_start_running)

	if is_running:
		stamina = maxf(0.0, stamina - stats.run_drain_per_second * delta)
		_regen_delay_left = stats.regen_delay
		if stamina <= 0.0:
			is_running = false
	elif _regen_delay_left > 0.0:
		_regen_delay_left = maxf(0.0, _regen_delay_left - delta)
	else:
		stamina = minf(stats.max_stamina, stamina + stats.regen_per_second * delta)

	if not is_equal_approx(before, stamina):
		stamina_changed.emit(stamina, stats.max_stamina)


## For actions that cost stamina (shove). Returns false if not enough.
func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	_regen_delay_left = stats.regen_delay
	stamina_changed.emit(stamina, stats.max_stamina)
	return true


func is_dead() -> bool:
	return state == State.DEAD


# ---------------- noise & flashlight (Phase 6) ----------------

## Running is audible (120 px every 0.4 s); walking is silent.
func _update_run_noise(delta: float) -> void:
	if not is_running:
		_run_noise_left = 0.0
		return
	_run_noise_left -= delta
	if _run_noise_left <= 0.0:
		_run_noise_left = stats.run_noise_interval
		NoiseSystem.emit_noise(global_position, stats.run_noise_radius, self)


## Seconds left in the flashlight's battery. A new run starts with a full battery.
func flashlight_charge() -> float:
	if GameState.flashlight_charge < 0.0:
		GameState.flashlight_charge = stats.flashlight_battery_seconds
	return GameState.flashlight_charge


## 0..1 charge of the battery in the flashlight.
func flashlight_charge_ratio() -> float:
	return clampf(flashlight_charge() / stats.flashlight_battery_seconds, 0.0, 1.0)


## F key. Returns the new on/off state.
## Phase 11: the "Flashlight shadows" setting (visual only).
func _apply_graphics_settings() -> void:
	flashlight.shadow_enabled = Settings.flashlight_shadows


func toggle_flashlight() -> bool:
	return set_flashlight(not flashlight_on)


## Turns the light on (needs charge or a spare battery) or off. Returns whether it is now on.
func set_flashlight(on: bool) -> bool:
	if on and flashlight_charge() <= 0.0 and not _swap_battery():
		message.emit("No batteries")
		on = false
	if on == flashlight_on:
		return flashlight_on
	flashlight_on = on
	flashlight.enabled = on
	_aim_flashlight()
	if is_inside_tree():
		AudioManager.play_at(preload("res://assets/audio/sfx/flashlight_click.wav"), global_position, -8.0)
	flashlight_changed.emit(flashlight_on, flashlight_charge_ratio())
	return flashlight_on


## Puts a battery from the bag into the flashlight. Returns false if there are none.
func _swap_battery() -> bool:
	if inventory.remove_item(&"battery", 1) == 0:
		return false
	GameState.flashlight_charge = stats.flashlight_battery_seconds
	message.emit("New battery in the flashlight")
	return true


func _update_flashlight(delta: float) -> void:
	if not flashlight_on:
		return
	_aim_flashlight()
	GameState.flashlight_charge = maxf(0.0, flashlight_charge() - delta)
	if GameState.flashlight_charge <= 0.0 and not _swap_battery():
		message.emit("Flashlight battery is dead")
		set_flashlight(false)
	else:
		flashlight_changed.emit(true, flashlight_charge_ratio())


func _aim_flashlight() -> void:
	flashlight.rotation = aim_direction.angle()


# ---------------- darkness ----------------

## Called by DarkZone areas. Counts zones so overlapping zones work.
func enter_darkness() -> void:
	_darkness_zones += 1
	_set_in_darkness(true)


func exit_darkness() -> void:
	_darkness_zones = maxi(0, _darkness_zones - 1)
	_set_in_darkness(_darkness_zones > 0)


func _set_in_darkness(value: bool) -> void:
	in_darkness = value
	# A faint light keeps the player's own silhouette readable; only inside darkness.
	adaptation_light.enabled = value


# ---------------- internals ----------------

func _set_state(new_state: State, duration: float = 0.0) -> void:
	state = new_state
	_state_left = duration
	state_changed.emit(new_state)


func _update_state_timer(delta: float) -> void:
	if state == State.ATTACKING or state == State.SHOVING or state == State.HURT:
		_state_left -= delta
		if _state_left <= 0.0:
			_set_state(State.NORMAL)


func _speed_multiplier() -> float:
	match state:
		State.ATTACKING:
			return weapons.current_weapon().move_speed_multiplier
		State.RELOADING:
			return stats.reload_move_multiplier
		State.SHOVING:
			return stats.shove_move_multiplier
		State.HURT:
			return stats.hurt_move_multiplier
	return 1.0


func _on_reload_finished() -> void:
	if state == State.RELOADING:
		_set_state(State.NORMAL)


func _on_weapon_changed(_slot: int, weapon: WeaponData) -> void:
	weapon_sprite.texture = weapon.icon if weapon != null else null


func _on_weapon_attacked(_origin: Vector2, weapon: WeaponData) -> void:
	if weapon.is_melee():
		# The weapon sweeps across the arc while the body plays the melee animation.
		var half: float = deg_to_rad(weapon.melee_arc_degrees) * 0.5
		_swing_offset = -half
		var tween: Tween = create_tween()
		tween.tween_property(self, "_swing_offset", half, weapon.hit_delay * 1.6)
		tween.tween_property(self, "_swing_offset", 0.0, 0.12)
	else:
		muzzle_light.enabled = true
		muzzle_flash.frame = _fx_rng.randi() % 2
		muzzle_flash.visible = true
		_shake_camera(1.5)
		get_tree().create_timer(0.05, false).timeout.connect(func() -> void:
			muzzle_light.enabled = false
			muzzle_flash.visible = false)


func _update_aim() -> void:
	if use_mouse_aim:
		var to_mouse: Vector2 = get_global_mouse_position() - global_position
		if to_mouse.length() > 4.0:
			aim_direction = to_mouse.normalized()
	weapon_pivot.rotation = aim_direction.angle() + _swing_offset
	weapon_sprite.flip_v = aim_direction.x < 0.0
	weapon_pivot.z_index = -1 if aim_direction.y < -0.3 else 1


func _update_animation(is_moving: bool) -> void:
	var anim: StringName = animation_for(is_moving)
	if sprite.animation != anim:
		sprite.play(anim)


## Cosmetic randomness (footstep choice, muzzle-flash frame) uses its own generator so it never changes
## the gameplay random sequence (tests seed the global one).
var _fx_rng := RandomNumberGenerator.new()

const STEPS: Array[AudioStream] = [preload("res://assets/audio/sfx/step_1.wav"), preload("res://assets/audio/sfx/step_2.wav"),
	preload("res://assets/audio/sfx/step_3.wav")]


## Footstep sounds on the walk/run frames where a foot lands (sound only; noise for zombies is separate).
func _on_sprite_frame_changed() -> void:
	var anim: String = String(sprite.animation)
	if (anim.begins_with("walk_") or anim.begins_with("run_")) and sprite.frame % 2 == 0:
		AudioManager.play_at(STEPS[_fx_rng.randi() % STEPS.size()], global_position, -12.0 if anim.begins_with("walk_") else -7.0, 0.1)


## Which animation fits the current state (visual only; the state machine never depends on it).
func animation_for(is_moving: bool) -> StringName:
	var base: String
	match state:
		State.DEAD: base = "death"
		State.HURT: base = "hurt"
		State.SHOVING: base = "shove"
		State.RELOADING: base = "reload"
		State.ATTACKING:
			var w: WeaponData = weapons.current_weapon()
			base = "melee" if w == null or w.is_melee() else "shoot"
		_:
			base = ("run" if is_running else "walk") if is_moving else "idle"
	return StringName(base + "_" + _direction_name(aim_direction))


static func _direction_name(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y >= 0.0 else "up"


func _on_damaged(amount: float, _source: Node) -> void:
	AudioManager.play_at(preload("res://assets/audio/sfx/player_hurt.wav"), global_position, -2.0)
	Fx.burst(get_parent(), global_position + Vector2(0, -9), Fx.BLOOD, 6, 45.0)
	cancel_search()
	var tween: Tween = create_tween()
	sprite.modulate = Color(1.0, 0.35, 0.35)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.12)
	_shake_camera(3.0)
	# Only heavy hits interrupt the player; light bites never stun-lock.
	if amount >= stats.heavy_hit_threshold and not health.is_dead:
		weapons.cancel_reload()
		weapons.cancel_pending_attack()
		_set_state(State.HURT, stats.hurt_duration)


func _on_died() -> void:
	cancel_search()
	set_flashlight(false)
	_heal_left = 0.0
	weapons.cancel_reload()
	weapons.cancel_pending_attack()
	_set_state(State.DEAD)
	is_running = false
	hurtbox.set_deferred("monitorable", false)
	weapon_pivot.visible = false
	sprite.play(animation_for(false))  # death animation (falls, then lies still)
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.8, 0.62, 0.6), 0.5)
	_drop_death_backpack()
	died.emit()


## Death rule (GDD): everything carried in the bag goes into a backpack at the death spot. Equipped
## weapons and the rounds loaded in them stay with the player. Quest items go in the backpack too.
func _drop_death_backpack() -> void:
	GameState.stats.deaths = int(GameState.stats.get("deaths", 0)) + 1
	var items: Array = inventory.take_all()
	var pile_id: StringName = &""
	if not items.is_empty():
		pile_id = GameState.create_pile(snap_to_navigation(global_position), items, true)
	backpack_dropped.emit(pile_id)


func _shake_camera(strength: float) -> void:
	var tween: Tween = create_tween()
	for i in 4:
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(camera, "offset", offset, 0.03)
	tween.tween_property(camera, "offset", Vector2.ZERO, 0.03)
