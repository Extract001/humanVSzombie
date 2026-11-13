@tool
class_name LootContainer
extends Node2D
## A searchable container (shelf, cabinet, toolbox, locker, car trunk) or an item pile / death backpack.
##
## First use: the player searches for `search_time` seconds (makes a little noise; moving, attacking,
## shoving or being hit cancels it, and nothing is granted). When the search completes, GameState rolls the
## loot table ONCE (seeded) and adds the guaranteed items; the result is remembered, so reopening never
## re-rolls or duplicates anything. Piles and backpacks open instantly.

enum Look { SHELF_GOODS, MEDICAL_CABINET, TOOLBOX, STORAGE_BOX, LOCKER, KITCHEN_CUPBOARD, HIDDEN, BACKPACK, PILE }

## Search duration per container type (seconds); types not listed use DEFAULT_SEARCH_TIME.
const SEARCH_TIMES: Dictionary = {
	&"grocery_shelf": 0.5, &"kitchen": 0.5, &"medical_shelf": 0.5, &"medical_counter": 0.6,
	&"medical_cabinet": 0.7, &"locker": 0.7, &"storage_box": 0.7, &"toolbox": 0.7,
	&"vehicle_trunk": 1.2,
}
const DEFAULT_SEARCH_TIME: float = 1.0
## Rummaging is audible to zombies close by.
const SEARCH_NOISE_RADIUS: float = 60.0
const FRAMES: int = 8  # sheet: 6 container looks + backpack + pile

## Unique name used by saves and quest guarantees. Must not repeat anywhere in the map.
@export var container_id: StringName = &""
## Which loot table it uses, e.g. grocery_shelf, medical_cabinet, vehicle_trunk.
@export var container_type: StringName = &"storage_box"
@export var look: Look = Look.STORAGE_BOX:
	set(v):
		look = v
		_rebuild()
@export var display_name: String = "Storage box"
## Extra items always added on the first search (designated quest containers get theirs
## from data/objectives/quest_guarantees.tres in addition to this).
@export var guaranteed_items: Dictionary = {}
## Seconds to search; negative = use the type's default (SEARCH_TIMES).
@export var search_time: float = -1.0
## Piles/backpacks: open instantly, disappear when emptied.
@export var is_pile: bool = false

var _sprite: Sprite2D
var _interact: Interactable


func _ready() -> void:
	_sprite = $Sprite
	_interact = $Interact
	_rebuild()
	if Engine.is_editor_hint():
		return
	add_to_group(&"loot_containers")
	_interact.prompt_provider = get_prompt
	_interact.interacted.connect(_on_interacted)
	GameState.container_changed.connect(_on_container_changed)
	_update_empty_look()


func get_search_time() -> float:
	if is_pile:
		return 0.0
	var t: float = search_time if search_time >= 0.0 else float(SEARCH_TIMES.get(container_type, DEFAULT_SEARCH_TIME))
	return t * Perks.search_time_mult()   # Slice 2: Scavenger


func all_guaranteed_items() -> Dictionary:
	var out: Dictionary = QuestGuarantees.for_container(container_id)
	for id in guaranteed_items:
		out[StringName(id)] = int(out.get(StringName(id), 0)) + int(guaranteed_items[id])
	return out


func is_searched() -> bool:
	return is_pile or GameState.is_rolled(container_id)


func contents() -> Array:
	return GameState.get_contents(container_id)


func get_prompt() -> String:
	if is_pile:
		return "Open " + display_name.to_lower()
	if not is_searched():
		return "Search " + display_name.to_lower()
	return display_name + (" (empty)" if contents().is_empty() else " - open")


## Called when a search finishes (or straight away for piles / already-searched containers).
## Rolls once, then returns the remembered contents.
func open_contents() -> Array:
	if not is_pile:
		GameState.roll_container(container_id, container_type, all_guaranteed_items())
	return contents()


func _on_interacted(by: Node) -> void:
	var player := by as Player
	if player == null:
		return
	if is_searched():
		open_contents()
		player.open_loot(self)
	else:
		player.start_search(self, get_search_time())


func _on_container_changed(id: StringName) -> void:
	if id == container_id:
		_update_empty_look()


func _update_empty_look() -> void:
	if _sprite == null or is_pile:
		return
	# Searched-and-empty containers look slightly darker so the player can skip them.
	var empty: bool = GameState.is_rolled(container_id) and contents().is_empty()
	_sprite.self_modulate = Color(0.6, 0.6, 0.6) if empty else Color.WHITE


func _rebuild() -> void:
	if _sprite == null:
		return
	_sprite.visible = look != Look.HIDDEN
	_sprite.hframes = FRAMES
	_sprite.frame = clampi(int(look) - (1 if look > Look.HIDDEN else 0), 0, FRAMES - 1)
	_sprite.light_mask = 1 | 2
