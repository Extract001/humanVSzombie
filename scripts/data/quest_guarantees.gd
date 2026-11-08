class_name QuestGuarantees
extends Resource
## Items that are ALWAYS in a designated container on its first search, on top of the random roll
## (TECHNICAL_ARCHITECTURE §4.8b). Random loot can never remove them, so the objective chain
## can't be blocked by bad luck. Data file: data/objectives/quest_guarantees.tres

const PATH := "res://data/objectives/quest_guarantees.tres"

## container_id (String) -> { item_id (String) -> quantity (int) }
@export var guarantees: Dictionary = {}

static var _cached: QuestGuarantees


static func get_data() -> QuestGuarantees:
	if _cached == null:
		_cached = load(PATH)
	return _cached


## Guaranteed items for one container as {StringName item_id: int qty} (empty if none).
static func for_container(container_id: StringName) -> Dictionary:
	var entry: Dictionary = get_data().guarantees.get(String(container_id), {})
	var out: Dictionary = {}
	for id in entry:
		out[StringName(id)] = int(entry[id])
	return out


## Total guaranteed quantity of one item across all designated containers.
static func total(item_id: StringName) -> int:
	var sum := 0
	for cid in get_data().guarantees:
		sum += int(get_data().guarantees[cid].get(String(item_id), 0))
	return sum


static func clear_cache() -> void:
	_cached = null
