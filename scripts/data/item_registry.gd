class_name ItemRegistry
extends Resource
## The list of every item in the game (data/items/item_registry.tres).
## Use ItemRegistry.get_item(&"bandage") anywhere.

const PATH: String = "res://data/items/item_registry.tres"
const ICONS: Texture2D = preload("res://assets/sprites/items.png")

@export var items: Array[ItemData] = []

static var _by_id: Dictionary = {}


static func get_item(id: StringName) -> ItemData:
	if _by_id.is_empty():
		var reg: ItemRegistry = load(PATH)
		for it in reg.items:
			_by_id[it.id] = it
	return _by_id.get(id, null)


static func all_items() -> Array:
	get_item(&"")
	return _by_id.values()


## A small texture showing the item's icon (for UI lists).
static func icon(id: StringName) -> Texture2D:
	var item: ItemData = get_item(id)
	var at := AtlasTexture.new()
	at.atlas = ICONS
	at.region = Rect2((item.icon_frame if item else 0) * 16, 0, 16, 16)
	return at


## Releases the cached items (called at exit so nothing is reported as leaked).
static func clear_cache() -> void:
	_by_id.clear()
