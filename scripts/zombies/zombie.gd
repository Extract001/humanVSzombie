class_name Zombie
extends CharacterBody2D
## One zombie scene for every type: behaviour numbers come from `data` (ZombieData).
##
## States: IDLE → WANDER (short strolls near home)
##         any calm state → INVESTIGATE (heard a noise) → SEARCH (looks around) → IDLE
##         sees the player → CHASE (groans: nearby zombies investigate) → ATTACK (telegraphed bite)
##         loses the player → SEARCH at the last known position → IDLE
##         hit / shoved → STUNNED → CHASE or SEARCH;  0 health → DEAD
## Decisions run on a staggered think tick (0.2 s; 1 s when far from the player and calm).
## Movement runs every physics frame: straight at a visible target, otherwise along a navigation path.

signal died
signal state_changed(new_state: State)
signal door_banged(door: Door)
## Slice 1: hit a safehouse barricade.
signal barricade_hit(barricade: Barricade)

enum State { IDLE, WANDER, INVESTIGATE, SEARCH, CHASE, ATTACK, STUNNED, DEAD }

const WORLD_COLLISION_MASK: int = 1  # physics layer 1 "world" blocks sight
const GRUNT_COOLDOWN: float = 3.0
const ARRIVE_DISTANCE: float = 6.0
const REPATH_MOVE_THRESHOLD: float = 16.0
const DOOR_BANG_INTERVAL: float = 1.5
## Gives up investigating a noise it can't reach (e.g. behind a closed door) after this long.
const INVESTIGATE_TIMEOUT: float = 12.0

@export var data: ZombieData
## Direction the zombie looks while idle (it can't see behind itself).
@export var initial_facing: Vector2 = Vector2.DOWN
## Off = the zombie never wanders on its own (used by tests and scripted set-ups).
@export var wanders: bool = true

var state: State = State.IDLE
var facing: Vector2 = Vector2.DOWN
var target: Player = null
var last_known_position: Vector2 = Vector2.ZERO
var target_visible: bool = false
var home_position: Vector2 = Vector2.ZERO
var is_dormant: bool = false

var _think_timer: float = 0.0
var _windup_left: float = 0.0
var _time_since_bite: float = 999.0
var _search_left: float = 0.0
var _look_timer: float = 0.0
var _idle_left: float = 0.0
var _wander_left: float = 0.0
var _move_goal: Vector2 = Vector2.ZERO
var _repath_left: float = 0.0
var _stun_left: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _knockback_decel: float = 0.0
var _grunt_cooldown: float = 0.0
var _investigate_left: float = 0.0
var _door_bang_left: float = 0.0
## Slice 1 (night siege): a horde Walker heads for this point (inside the safehouse, through a
## window) whenever it has nothing better to do. Vector2.INF = a normal town Walker.
var siege_goal: Vector2 = Vector2.INF
var _barricade_hit_left: float = 0.0
## Crossing a window link (navigation layer 2): head straight for the far side, don't re-path
## halfway (the window gap itself isn't on the walkable mesh).
var _link_exit: Vector2 = Vector2.INF
var _link_left: float = 0.0
const SIEGE: SiegeData = preload("res://data/siege/siege_data.tres")
## A siege walk across the map can take a minute or more.
const SIEGE_WALK_TIMEOUT: float = 120.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var eyes: Sprite2D = $Eyes
@onready var health: HealthComponent = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var nav_agent: NavigationAgent2D = $NavAgent


func _ready() -> void:
	if data == null:
		data = ZombieData.new()
	add_to_group(&"zombies")
	add_to_group(&"noise_listeners")
	facing = initial_facing.normalized() if initial_facing != Vector2.ZERO else Vector2.DOWN
	home_position = global_position
	health.setup(data.max_health)
	health.died.connect(_on_died)
	nav_agent.navigation_layers = 1 | NavigationBaker.WINDOW_NAV_LAYER  # Slice 1: may path through windows
	nav_agent.link_reached.connect(_on_link_reached)
	# Random start offsets so many zombies don't all think (or wander) on the same frame.
	_think_timer = randf() * data.think_interval
	_idle_left = randf_range(data.idle_time_min, data.idle_time_max)
	_update_visuals(false)
	sprite.frame_changed.connect(_on_sprite_frame_changed)


## Shuffling feet, only for zombies close to the player (and not too many at once).
static var _last_shuffle_ms: int = 0
const SHUFFLE_RANGE: float = 220.0

func _on_sprite_frame_changed() -> void:
	if sprite.frame % 2 != 0 or not String(sprite.animation).begins_with("walk_"):
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_shuffle_ms < 180:
		return
	var p: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
	if p == null or p.global_position.distance_squared_to(global_position) > SHUFFLE_RANGE * SHUFFLE_RANGE:
		return
	_last_shuffle_ms = now
	AudioManager.play_at(preload("res://assets/audio/sfx/zombie_shuffle.wav"), global_position, -14.0, 0.15)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_time_since_bite += delta
	_grunt_cooldown = maxf(0.0, _grunt_cooldown - delta)
	_repath_left -= delta
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer += data.dormant_think_interval if is_dormant else data.think_interval
		think()

	match state:
		State.IDLE:
			_process_idle(delta)
		State.WANDER:
			_process_wander(delta)
		State.INVESTIGATE:
			_process_investigate()
		State.SEARCH:
			_process_search(delta)
		State.CHASE:
			_process_chase()
		State.ATTACK:
			_process_attack(delta)
		State.STUNNED:
			_process_stunned(delta)

	move_and_slide()
	_check_blocked_by_door(delta)
	_check_blocked_by_barricade(delta)
	_update_visuals(velocity.length() > 1.0)


# ---------------- perception ----------------

## One AI decision. Public so tests can call it directly.
func think() -> void:
	if state == State.DEAD or state == State.ATTACK or state == State.STUNNED:
		return
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group(&"player") as Player
	if target == null or target.is_dead():
		target_visible = false
		is_dormant = false
		if state == State.CHASE:
			_enter_search(last_known_position)
		return

	var calm: bool = state == State.IDLE or state == State.WANDER
	var far: bool = global_position.distance_squared_to(target.global_position) \
		> data.dormant_distance * data.dormant_distance
	is_dormant = calm and far and not is_besieging()
	if is_dormant:
		target_visible = false
		return

	target_visible = can_see(target)
	if target_visible:
		last_known_position = target.global_position
		if state != State.CHASE:
			_on_spotted_player()
	elif state == State.CHASE:
		_enter_search(last_known_position)


## Sight check, cheapest test first: distance → close sense → view cone → wall raycast.
func can_see(other: Node2D) -> bool:
	var to_other: Vector2 = other.global_position - global_position
	var dist_sq: float = to_other.length_squared()
	var sight: float = data.sight_range * sight_multiplier_for(other)
	if dist_sq > sight * sight:
		return false
	var close: bool = dist_sq <= data.proximity_sense * data.proximity_sense
	if not close:
		var half_cone: float = deg_to_rad(data.sight_cone_degrees) * 0.5
		if absf(facing.angle_to(to_other)) > half_cone:
			return false
	return _has_line_of_sight(other.global_position)


## Darkness hides the player (×0.5); a lit flashlight in the dark gives them away (×1.5).
## No pixel sampling: just "is the player in a dark area, and is the light on?"
func sight_multiplier_for(other: Node2D) -> float:
	var p := other as Player
	if p == null or not p.in_darkness:
		return 1.0
	return data.flashlight_sight_multiplier if p.flashlight_on else data.dark_sight_multiplier


func _has_line_of_sight(point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, point, WORLD_COLLISION_MASK)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Called by NoiseSystem when a noise reaches this zombie.
func hear_noise(noise_position: Vector2, _radius: float, _source: Node) -> void:
	if state == State.DEAD or state == State.ATTACK or state == State.STUNNED:
		return
	if state == State.CHASE and target_visible:
		return  # busy with a visible player
	is_dormant = false
	_move_goal = noise_position
	_investigate_left = INVESTIGATE_TIMEOUT
	_repath_left = 0.0
	facing = global_position.direction_to(noise_position) if noise_position != global_position else facing
	_set_state(State.INVESTIGATE)


func get_hearing_multiplier() -> float:
	return data.hearing_multiplier


func _on_spotted_player() -> void:
	if (state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE \
			or state == State.SEARCH) and _grunt_cooldown <= 0.0:
		_grunt_cooldown = GRUNT_COOLDOWN
		AudioManager.play_at(preload("res://assets/audio/sfx/zombie_grunt.wav"), global_position, -4.0)
		# Group behaviour: the groan is a noise. Nearby zombies come to investigate (not chase).
		NoiseSystem.emit_noise(global_position, data.alert_groan_radius, self)
	_repath_left = 0.0
	_set_state(State.CHASE)


# ---------------- state processing ----------------

func _process_idle(delta: float) -> void:
	velocity = Vector2.ZERO
	if is_besieging():
		_start_siege_walk()
		return
	if not wanders or is_dormant:
		return
	_idle_left -= delta
	if _idle_left <= 0.0:
		_start_wander()


func is_besieging() -> bool:
	return siege_goal != Vector2.INF


## Slice 1: horde Walkers march on the safehouse (an "investigate" with a long patience).
func _start_siege_walk() -> void:
	if global_position.distance_to(siege_goal) <= ARRIVE_DISTANCE * 2.0:
		_enter_search(siege_goal)
		return
	_move_goal = siege_goal
	_investigate_left = SIEGE_WALK_TIMEOUT
	_repath_left = 0.0
	_set_state(State.INVESTIGATE)


func _start_wander() -> void:
	var angle: float = randf() * TAU
	var candidate: Vector2 = home_position + Vector2.RIGHT.rotated(angle) * randf_range(16.0, data.wander_radius)
	var map: RID = get_world_2d().navigation_map
	if not NavigationServer2D.map_get_regions(map).is_empty():
		var on_mesh: Vector2 = NavigationServer2D.map_get_closest_point(map, candidate)
		if on_mesh.distance_to(candidate) < data.wander_radius:
			candidate = on_mesh
	_move_goal = candidate
	_wander_left = data.wander_timeout
	_repath_left = 0.0
	_set_state(State.WANDER)


func _process_wander(delta: float) -> void:
	_wander_left -= delta
	if _wander_left <= 0.0 or _navigate(_move_goal, data.wander_speed):
		_enter_idle()


func _process_investigate() -> void:
	_investigate_left -= get_physics_process_delta_time()
	if _navigate(_move_goal, data.investigate_speed) or _investigate_left <= 0.0:
		_enter_search(global_position if _investigate_left <= 0.0 else _move_goal)


func _enter_search(spot: Vector2) -> void:
	_move_goal = spot
	_search_left = data.search_duration
	_look_timer = data.search_look_interval
	_repath_left = 0.0
	_set_state(State.SEARCH)


func _process_search(delta: float) -> void:
	# The timer always runs, so a zombie that can't reach the spot still gives up.
	_search_left -= delta
	if _search_left <= 0.0:
		_enter_idle()
		return
	if global_position.distance_to(_move_goal) > ARRIVE_DISTANCE:
		_navigate(_move_goal, data.investigate_speed)
	else:
		velocity = Vector2.ZERO
		# Look around: sweep the view cone in new directions.
		_look_timer -= delta
		if _look_timer <= 0.0:
			_look_timer = data.search_look_interval
			facing = facing.rotated(randf_range(PI * 0.5, PI) * (1.0 if randf() < 0.5 else -1.0))


func _enter_idle() -> void:
	velocity = Vector2.ZERO
	home_position = global_position  # hordes drift toward where noises were
	_idle_left = randf_range(data.idle_time_min, data.idle_time_max)
	_set_state(State.IDLE)


func _process_chase() -> void:
	if target == null or not is_instance_valid(target):
		_enter_search(last_known_position)
		return
	var goal: Vector2 = target.global_position if target_visible else last_known_position
	if target_visible and global_position.distance_to(goal) <= data.attack_range and _attack_ready():
		_start_attack()
		return
	if target_visible:
		_move_direct(goal, data.chase_speed)  # clear line of sight: go straight at the player
	elif _navigate(goal, data.chase_speed):
		_enter_search(goal)


func _process_attack(delta: float) -> void:
	velocity = Vector2.ZERO
	_windup_left -= delta
	if _windup_left > 0.0:
		return
	# Bite lands only if the player is still in reach (they can step out of the wind-up).
	if target != null and not target.is_dead() \
			and global_position.distance_to(target.global_position) <= data.attack_range + data.lunge_tolerance:
		target.hurtbox.receive_hit(data.bite_damage, self)
	_time_since_bite = 0.0
	sprite.modulate = Color.WHITE
	_set_state(State.CHASE)


func _attack_ready() -> bool:
	# Wind-up + recovery together never allow bites closer than attack_cooldown.
	return _time_since_bite >= data.attack_cooldown - data.attack_windup


func _start_attack() -> void:
	_windup_left = data.attack_windup
	facing = global_position.direction_to(target.global_position)
	sprite.modulate = Color(1.0, 0.75, 0.75)  # telegraph: reddish tint during the wind-up animation
	_set_state(State.ATTACK)


## Called by our Hurtbox after damage was applied (bullets, bat, shove).
## knockback: push velocity. stun_time: extra stun (shove stagger, heavy melee stun).
func on_hit(_amount: float, knockback: Vector2, stun_time: float, source: Node) -> void:
	if state == State.DEAD:
		return
	var resist: float = clampf(data.shove_resistance, 0.0, 1.0)
	_knockback = knockback * (1.0 - resist)
	_knockback_decel = _knockback.length() / data.knockback_time if data.knockback_time > 0.0 else 0.0
	# Any hit interrupts a bite wind-up. Very resistant zombies (Brute) aren't staggered.
	var stun: float = data.hit_stun_time
	if resist < 0.5:
		stun = maxf(stun, stun_time)
	_stun_left = stun
	is_dormant = false
	sprite.modulate = Color(2.2, 2.2, 2.2)  # white hit flash
	Fx.burst(get_parent(), global_position + Vector2(0, -9), Fx.BLOOD, 8, 55.0, knockback.normalized())
	# Being hurt reveals the attacker: turn on them once the stun ends.
	if source is Node2D:
		last_known_position = (source as Node2D).global_position
		facing = global_position.direction_to(last_known_position)
	_set_state(State.STUNNED)


func _process_stunned(delta: float) -> void:
	velocity = _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, _knockback_decel * delta)
	sprite.modulate = sprite.modulate.lerp(Color.WHITE, minf(1.0, delta * 12.0))
	_stun_left -= delta
	if _stun_left <= 0.0:
		sprite.modulate = Color.WHITE
		_repath_left = 0.0
		if target_visible:
			_set_state(State.CHASE)
		else:
			_enter_search(last_known_position)
		think()


func is_staggered() -> bool:
	return state == State.STUNNED


# ---------------- movement ----------------

## Moves toward `goal` along the navigation mesh. Returns true when arrived.
## Falls back to a straight line when there is no navigation map (e.g. small test scenes).
func _navigate(goal: Vector2, speed: float) -> bool:
	if global_position.distance_to(goal) <= ARRIVE_DISTANCE:
		velocity = Vector2.ZERO
		_link_exit = Vector2.INF
		return true
	if _link_exit != Vector2.INF:
		_link_left -= get_physics_process_delta_time()
		if global_position.distance_to(_link_exit) < 3.0 or _link_left <= 0.0:
			_link_exit = Vector2.INF   # through (or gave up pushing on intact boards): path again
			_repath_left = 0.0
		else:
			_move_direct(_link_exit, speed)
			return false
	if _repath_left <= 0.0 or nav_agent.target_position.distance_to(goal) > REPATH_MOVE_THRESHOLD:
		nav_agent.target_position = goal
		_repath_left = data.repath_interval
	var next: Vector2 = nav_agent.get_next_path_position()
	if nav_agent.is_navigation_finished() or next.distance_to(global_position) < 0.5:
		next = goal  # no usable path: head straight for it
	_move_direct(next, speed)
	return false


func _move_direct(goal: Vector2, speed: float) -> void:
	var dir: Vector2 = global_position.direction_to(goal)
	velocity = dir * speed
	if dir != Vector2.ZERO:
		facing = dir


## Slice 1: pushing against a boarded window: hit the boards (every zombie_barricade_interval).
## Uses the slide collisions, so it works even when the push stops the zombie dead.
func _check_blocked_by_barricade(delta: float) -> void:
	_barricade_hit_left = maxf(0.0, _barricade_hit_left - delta)
	if _barricade_hit_left > 0.0 or state == State.STUNNED or state == State.ATTACK:
		return
	for i in get_slide_collision_count():
		var b := get_slide_collision(i).get_collider() as Barricade
		if b != null and not b.is_broken():
			_barricade_hit_left = SIEGE.zombie_barricade_interval
			facing = global_position.direction_to(b.center())
			b.take_hit(SIEGE.zombie_barricade_damage)
			barricade_hit.emit(b)
			return


func _on_link_reached(details: Dictionary) -> void:
	_link_exit = details.get("link_exit_position", Vector2.INF)
	_link_left = 4.0


## Pushing against a closed door: bang on it every 1.5 s (a warning for the player).
## In the MVP Walkers can't break doors; the Brute will (later).
func _check_blocked_by_door(delta: float) -> void:
	_door_bang_left = maxf(0.0, _door_bang_left - delta)
	if velocity == Vector2.ZERO or _door_bang_left > 0.0:
		return
	for i in get_slide_collision_count():
		var door := get_slide_collision(i).get_collider() as Door
		if door != null and not door.is_open:
			_door_bang_left = DOOR_BANG_INTERVAL
			AudioManager.play_at(preload("res://assets/audio/sfx/door_bang.wav"), global_position, -2.0)
			door_banged.emit(door)
			return


func _set_state(new_state: State) -> void:
	_link_exit = Vector2.INF
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)


func _on_died() -> void:
	_set_state(State.DEAD)
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	hurtbox.set_deferred("collision_layer", 0)
	remove_from_group(&"zombies")
	remove_from_group(&"noise_listeners")
	eyes.visible = false
	sprite.play(StringName("death_" + Player._direction_name(facing)))
	# Corpses stay at the normal draw layer: a negative z_index would hide them under the ground tiles.
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.62, 0.6, 0.56), 0.5)
	AudioManager.play_at(preload("res://assets/audio/sfx/zombie_death.wav"), global_position, -3.0)
	died.emit()


func _update_visuals(is_moving: bool) -> void:
	var dir_name: String = Player._direction_name(facing)
	var base: String = "attack" if state == State.ATTACK else ("hurt" if state == State.STUNNED else ("walk" if is_moving else "idle"))
	var anim := StringName(base + "_" + dir_name)
	if sprite.animation != anim:
		sprite.play(anim)
	# Eyes are unshaded, so they stay readable in the dark. Hidden when facing away.
	eyes.frame = ["down", "left", "right", "up"].find(dir_name)
	eyes.visible = dir_name != "up"
