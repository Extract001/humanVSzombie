@tool
class_name Door
extends StaticBody2D
## A door or gate across a doorway. The node's position is the top-left of the doorway.
##
## Closed: blocks the player, zombies, bullets, sight and light (physics layer 1 "world").
## Open: nothing blocks. Opening/closing makes a small noise (40 px).
## Locked: can't be opened ("needs bolt cutters"); unlock() opens the way (Phase 7).
## Navigation: normal doors are NOT part of the navigation mesh, so zombie paths go through
## doorways. A closed door stops them physically and they bang on it.
## A locked gate with blocks_navigation = true IS part of the mesh (zombies don't path through it).

signal opened
signal closed

const TILE: int = 16
const THICKNESS: float = 4.0
const NOISE_RADIUS: float = 40.0

@export var width_tiles: int = 1:
	set(v):
		width_tiles = maxi(1, v)
		_rebuild()
@export var vertical: bool = false:
	set(v):
		vertical = v
		_rebuild()
@export var is_open: bool = false:
	set(v):
		is_open = v
		_apply_state()
@export var locked: bool = false
@export var locked_message: String = "It's locked."
## Gate style (metal, grey) instead of a wooden door.
@export var is_gate: bool = false:
	set(v):
		is_gate = v
		_rebuild()
## Locked gates are cut out of the navigation mesh until unlocked.
@export var blocks_navigation: bool = false
## Phase 7: carrying this item opens the lock (the item is used up), e.g. bolt cutters on the chain.
@export var unlock_item: StringName = &""
## Remembered in GameState.unlocks so the lock stays open (also after death / loading).
@export var unlock_id: StringName = &""

## Forcing a lock is loud (GDD §8: 260 px).
const FORCE_NOISE_RADIUS: float = 260.0

var _shape: CollisionShape2D
var _closed_visual: Polygon2D
var _open_visual: Polygon2D
var _occluder: LightOccluder2D
var _interact: Interactable


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_shape = $Shape
	_closed_visual = $Closed
	_open_visual = $Open
	_occluder = $Occluder
	_interact = $Interact
	_rebuild()
	if not Engine.is_editor_hint():
		_interact.prompt_provider = get_prompt
		_interact.interacted.connect(toggle)


func _enter_tree() -> void:
	# Groups are joined before any _ready(), so the navigation bake (deferred) sees locked gates.
	if not Engine.is_editor_hint():
		add_to_group(&"doors")
		if locked and unlock_id != &"" and GameState.has_unlock(unlock_id):
			# Already cut in this run: open, and not part of the navigation obstacles.
			locked = false
			blocks_navigation = false
			is_open = true
			remove_from_group(&"nav_source")  # the map scene saves locked gates in this group
		if blocks_navigation:
			add_to_group(&"nav_source")


func span() -> Vector2:
	var length: float = width_tiles * TILE
	return Vector2(TILE, length) if vertical else Vector2(length, TILE)


func get_prompt() -> String:
	if locked:
		if unlock_item != &"" and _player_has(unlock_item):
			return "Cut the chain (%s)" % ItemRegistry.get_item(unlock_item).display_name.to_lower()
		return "Locked " + ("gate" if is_gate else "door")
	return ("Close " if is_open else "Open ") + ("gate" if is_gate else "door")


## Opens or closes. Returns false if locked or something is standing in the doorway.
func toggle(by: Node = null) -> bool:
	if locked and unlock_item != &"" and by is Player and (by as Player).inventory.count(unlock_item) > 0:
		force_open(by)
		return true
	if locked:
		AudioManager.play_at(preload("res://assets/audio/sfx/door_locked.wav"), global_position + span() * 0.5)
		get_tree().call_group(&"hud", &"show_toast", locked_message)
		return false
	if is_open and _doorway_occupied():
		get_tree().call_group(&"hud", &"show_toast", "Something is in the way.")
		return false
	is_open = not is_open
	AudioManager.play_at(preload("res://assets/audio/sfx/door_open.wav") if is_open
		else preload("res://assets/audio/sfx/door_close.wav"), global_position + span() * 0.5, -3.0)
	NoiseSystem.emit_noise(global_position + span() * 0.5, NOISE_RADIUS, by)
	if is_open:
		opened.emit()
	else:
		closed.emit()
	return true


## Opens a lock with the unlock item: uses it up, makes a loud noise, opens the gate and records it.
func force_open(by: Player) -> void:
	by.inventory.remove_item(unlock_item, 1)
	unlock()
	if unlock_id != &"":
		GameState.add_unlock(unlock_id)
	is_open = true
	AudioManager.play_at(preload("res://assets/audio/sfx/chain_cut.wav"), global_position + span() * 0.5)
	NoiseSystem.emit_noise(global_position + span() * 0.5, FORCE_NOISE_RADIUS, by)
	get_tree().call_group(&"hud", &"show_toast", "You cut the chain. The gate swings open.")
	opened.emit()


func _player_has(item_id: StringName) -> bool:
	var p: Player = get_tree().get_first_node_in_group(&"player") as Player if is_inside_tree() else null
	return p != null and p.inventory.count(item_id) > 0


func unlock() -> void:
	locked = false
	if blocks_navigation:
		blocks_navigation = false
		remove_from_group(&"nav_source")
		for baker in get_tree().get_nodes_in_group(&"navigation_bakers"):
			baker.rebake()


func _doorway_occupied() -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	var box := RectangleShape2D.new()
	box.size = span() - Vector2(2, 2)
	params.shape = box
	params.transform = Transform2D(0.0, global_position + span() * 0.5)
	params.collision_mask = 2 | 4  # player and zombie bodies
	return not get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


func _rebuild() -> void:
	if _shape == null:
		return
	var s: Vector2 = span()
	var c: Vector2 = s * 0.5
	var bar: Vector2 = Vector2(THICKNESS, s.y) if vertical else Vector2(s.x, THICKNESS)
	var rect := RectangleShape2D.new()
	rect.size = s
	_shape.shape = rect
	_shape.position = c
	_closed_visual.polygon = _rect_points(c - bar * 0.5, bar)
	_closed_visual.color = Color(0.45, 0.47, 0.5) if is_gate else Color(0.42, 0.29, 0.18)
	# Open: the door swings against the frame (a short bar along one side).
	var swing: Vector2 = Vector2(s.x, THICKNESS) if vertical else Vector2(THICKNESS, s.y)
	_open_visual.polygon = _rect_points(Vector2.ZERO, swing)
	_open_visual.color = _closed_visual.color.darkened(0.25)
	var occ := OccluderPolygon2D.new()
	occ.polygon = _rect_points(c - bar * 0.5, bar)
	_occluder.occluder = occ
	var area_shape := _interact.get_node("Shape") as CollisionShape2D
	var reach := RectangleShape2D.new()
	reach.size = s + (Vector2(28, 0) if vertical else Vector2(0, 28))
	area_shape.shape = reach
	area_shape.position = c
	_apply_state()


func _apply_state() -> void:
	if _shape == null:
		return
	_shape.set_deferred("disabled", is_open)
	_closed_visual.visible = not is_open
	_open_visual.visible = is_open
	_occluder.visible = not is_open


static func _rect_points(pos: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y)])
