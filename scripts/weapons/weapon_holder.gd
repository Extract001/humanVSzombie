class_name WeaponHolder
extends Node
## Owns the player's weapon slots and each slot's loaded rounds.
##
## Ammo rules (TECHNICAL_ARCHITECTURE §4.4):
## - Reserve ammo lives ONLY in the Inventory. Each slot keeps its own `rounds_in_mag`.
## - Reload is atomic: rounds move from reserve to magazine only when the reload completes.
##   Cancelling (shove, switching, heavy hit) moves nothing.
## - Switching never moves ammo.
## Time advances in tick(), called by the player every physics frame (tests can call it directly).

signal weapon_changed(slot: int, weapon: WeaponData)
signal ammo_changed(rounds_in_mag: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished
signal reload_cancelled
## Emitted for every attack. The noise system (Phase 3) listens to this.
signal attacked(origin: Vector2, weapon: WeaponData)
signal dry_fired
## Slice 2: a new weapon was picked up (shotgun, fire axe).
signal weapon_added(slot: int, weapon: WeaponData)

const WORLD_MASK: int = 1        # physics layer 1: walls and solid props
const HURTBOX_MASK: int = 8      # physics layer 4: hurtboxes of zombies
const TARGET_RADIUS: float = 6.0 # rough body size added to melee reach
const SWITCH_TIME: float = 0.2

@export var starting_weapons: Array[WeaponData] = []
## Rounds loaded at the start for each starting weapon (missing = full magazine).
@export var starting_rounds: Array[int] = []

var slots: Array[WeaponData] = []
var rounds_in_mag: Array[int] = []
var current: int = 0
var is_reloading: bool = false
var inventory: Inventory
var body: Node2D

var _cooldown_left: float = 0.0
var _reload_left: float = 0.0
var _reload_total: float = 0.0
var _pending_melee_left: float = -1.0
var _pending_origin: Vector2
var _pending_dir: Vector2
var _rng := RandomNumberGenerator.new()


func setup(owner_body: Node2D, owner_inventory: Inventory) -> void:
	body = owner_body
	inventory = owner_inventory
	slots.clear()
	rounds_in_mag.clear()
	for i in starting_weapons.size():
		var w: WeaponData = starting_weapons[i]
		slots.append(w)
		var loaded: int = starting_rounds[i] if i < starting_rounds.size() else w.magazine_size
		rounds_in_mag.append(clampi(loaded, 0, w.magazine_size))
	inventory.item_changed.connect(func(_id: StringName, _q: int) -> void: _emit_ammo())
	current = 0
	weapon_changed.emit(current, current_weapon())
	_emit_ammo()


func has_weapon(id: StringName) -> bool:
	for w in slots:
		if w.id == id:
			return true
	return false


## Adds a weapon to the next slot, fully loaded. Returns false if you already have it.
func add_weapon(w: WeaponData, loaded: int = -1) -> bool:
	if w == null or has_weapon(w.id):
		return false
	slots.append(w)
	rounds_in_mag.append(w.magazine_size if loaded < 0 else clampi(loaded, 0, w.magazine_size))
	weapon_added.emit(slots.size() - 1, w)
	return true


func current_weapon() -> WeaponData:
	return slots[current] if current < slots.size() else null


func reserve_for(weapon: WeaponData) -> int:
	if weapon == null or not weapon.uses_ammo():
		return 0
	return inventory.count(weapon.ammo_item_id)


func loaded_rounds() -> int:
	return rounds_in_mag[current] if current < rounds_in_mag.size() else 0


func cooldown_ready() -> bool:
	return _cooldown_left <= 0.0


## Can the current weapon attack right now?
func can_attack() -> bool:
	var w: WeaponData = current_weapon()
	if w == null or not cooldown_ready() or is_reloading or _pending_melee_left >= 0.0:
		return false
	return w.is_melee() or loaded_rounds() > 0


## True when a firearm is empty but there is reserve ammo to reload with.
func should_auto_reload() -> bool:
	var w: WeaponData = current_weapon()
	return w != null and w.uses_ammo() and loaded_rounds() == 0 and reserve_for(w) > 0


## Performs one attack. Returns false if it wasn't possible.
func attack(origin: Vector2, direction: Vector2) -> bool:
	var w: WeaponData = current_weapon()
	if not can_attack():
		if w != null and w.uses_ammo() and loaded_rounds() == 0 and cooldown_ready():
			_cooldown_left = w.cooldown
			dry_fired.emit()
		return false
	_cooldown_left = w.cooldown
	direction = direction.normalized() if direction != Vector2.ZERO else Vector2.DOWN
	AudioManager.play_at(w.attack_sound, origin, 0.0 if w.uses_ammo() else -6.0)
	attacked.emit(origin, w)
	if w.is_melee():
		_pending_melee_left = w.hit_delay
		_pending_origin = origin
		_pending_dir = direction
		if w.hit_delay <= 0.0:
			_resolve_melee()
	else:
		rounds_in_mag[current] -= 1
		_emit_ammo()
		for i in maxi(1, w.pellets):
			var spread: float = deg_to_rad(_rng.randf_range(-w.spread_degrees, w.spread_degrees) * 0.5)
			_fire_ray(origin, direction.rotated(spread), w)
	return true


## Starts reloading the current firearm. Returns false if not possible.
func start_reload() -> bool:
	var w: WeaponData = current_weapon()
	if w == null or not w.uses_ammo() or is_reloading:
		return false
	if loaded_rounds() >= w.magazine_size or reserve_for(w) <= 0:
		return false
	is_reloading = true
	_reload_total = w.reload_time * Perks.reload_time_mult()   # Slice 2: Steady Hands
	_reload_left = _reload_total
	reload_started.emit(_reload_total)
	return true


func cancel_reload() -> void:
	if is_reloading:
		is_reloading = false
		_reload_left = 0.0
		reload_cancelled.emit()


## Cancels a melee swing whose hit hasn't landed yet (e.g. the player got heavily hit).
func cancel_pending_attack() -> void:
	_pending_melee_left = -1.0


## Switches to a slot. Returns false if it's invalid or already selected.
func switch_to(slot: int) -> bool:
	if slot < 0 or slot >= slots.size() or slot == current:
		return false
	cancel_reload()
	cancel_pending_attack()
	current = slot
	_cooldown_left = maxf(_cooldown_left, SWITCH_TIME)
	weapon_changed.emit(current, current_weapon())
	_emit_ammo()
	return true


func cycle(step: int) -> bool:
	if slots.size() < 2:
		return false
	return switch_to(posmod(current + step, slots.size()))


func reload_progress() -> float:
	var w: WeaponData = current_weapon()
	if not is_reloading or w == null or _reload_total <= 0.0:
		return 0.0
	return 1.0 - _reload_left / _reload_total


func tick(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _pending_melee_left >= 0.0:
		_pending_melee_left -= delta
		if _pending_melee_left < 0.0:
			_resolve_melee()
	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_complete_reload()


func _complete_reload() -> void:
	var w: WeaponData = current_weapon()
	is_reloading = false
	var needed: int = w.magazine_size - loaded_rounds()
	var taken: int = inventory.remove_item(w.ammo_item_id, needed)
	rounds_in_mag[current] += taken
	AudioManager.play_at(preload("res://assets/audio/sfx/reload.wav"), body.global_position, -4.0)
	_emit_ammo()
	reload_finished.emit()


func _fire_ray(origin: Vector2, direction: Vector2, w: WeaponData) -> void:
	var end: Vector2 = origin + direction * w.range_px
	var query := PhysicsRayQueryParameters2D.create(origin, end, WORLD_MASK | HURTBOX_MASK)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	if body is CollisionObject2D:
		query.exclude = [(body as CollisionObject2D).get_rid()]
	var hit: Dictionary = body.get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit["position"]
		var collider: Object = hit["collider"]
		if collider is Hurtbox:
			(collider as Hurtbox).receive_hit(w.damage * Perks.gun_damage_mult(), body, direction * w.knockback, 0.0)
			AudioManager.play_at(w.hit_sound, end, -3.0)
		else:
			Fx.burst(body.get_parent(), end - direction * 2.0, Fx.DUST, 6, 40.0, -direction, 0.3)
			Fx.burst(body.get_parent(), end - direction * 2.0, Fx.SPARK, 3, 60.0, -direction, 0.12)
	_spawn_tracer(origin, end)


func _resolve_melee() -> void:
	_pending_melee_left = -1.0
	var w: WeaponData = current_weapon()
	if w == null or not w.is_melee():
		return
	var targets: Array[Hurtbox] = find_targets_in_cone(body, _pending_origin, _pending_dir,
		w.range_px + TARGET_RADIUS, w.melee_arc_degrees)
	for hb in targets:
		var stun: float = w.heavy_stun_time if _rng.randf() < w.heavy_stun_chance else 0.0
		var push: Vector2 = _pending_origin.direction_to(hb.global_position) * w.knockback
		hb.receive_hit(w.damage * Perks.melee_damage_mult(), body, push, stun)
	if not targets.is_empty():
		AudioManager.play_at(w.hit_sound, targets[0].global_position)


## Living zombie hurtboxes within `reach` of origin, inside the cone, not behind walls.
## Shared by melee weapons and the shove.
static func find_targets_in_cone(from_body: Node2D, origin: Vector2, direction: Vector2,
		reach: float, arc_degrees: float) -> Array[Hurtbox]:
	var found: Array[Hurtbox] = []
	var space: PhysicsDirectSpaceState2D = from_body.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = reach
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.transform = Transform2D(0.0, origin)
	params.collision_mask = HURTBOX_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var half_arc: float = deg_to_rad(arc_degrees) * 0.5
	for result in space.intersect_shape(params, 32):
		var hb := result["collider"] as Hurtbox
		if hb == null or hb.health == null or hb.health.is_dead or found.has(hb):
			continue
		var to_target: Vector2 = hb.global_position - origin
		if to_target.length() > reach:
			continue
		if to_target.length() > 2.0 and absf(direction.angle_to(to_target)) > half_arc:
			continue
		var ray := PhysicsRayQueryParameters2D.create(origin, hb.global_position, WORLD_MASK)
		if not space.intersect_ray(ray).is_empty():
			continue  # a wall is in the way
		found.append(hb)
	return found


func _spawn_tracer(from: Vector2, to: Vector2) -> void:
	var parent: Node = body.get_parent()
	if parent == null:
		return
	var line := Line2D.new()
	line.width = 1.0
	line.default_color = Color(1.0, 0.92, 0.6, 0.9)
	line.points = PackedVector2Array([from, to])
	line.z_index = 5
	line.top_level = true  # points are in world coordinates
	parent.add_child(line)
	var tween: Tween = line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.08)
	tween.tween_callback(line.queue_free)


func _emit_ammo() -> void:
	ammo_changed.emit(loaded_rounds(), reserve_for(current_weapon()))
