class_name LootTableRegistry
extends Resource
## Maps a container_type (e.g. &"grocery_shelf") to its LootTable. data/loot_tables/registry.tres

const PATH: String = "res://data/loot_tables/registry.tres"

@export var types: Array[StringName] = []
@export var tables: Array[LootTable] = []

static var _cache: Dictionary = {}


static func get_table(type: StringName) -> LootTable:
	if _cache.is_empty():
		var reg: LootTableRegistry = load(PATH)
		for i in reg.types.size():
			_cache[reg.types[i]] = reg.tables[i]
	return _cache.get(type, null)


static func clear_cache() -> void:
	_cache.clear()
