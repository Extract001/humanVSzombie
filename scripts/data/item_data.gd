class_name ItemData
extends Resource
## One kind of item (GDD §10). Each item is a .tres in data/items/, listed in item_registry.tres.

enum Category { FOOD, WATER, MEDICAL, AMMO, MATERIAL, QUEST }

@export var id: StringName = &"item"
@export var display_name: String = "Item"
@export_multiline var description: String = ""
@export var category: Category = Category.MATERIAL
## How many fit in one inventory slot.
@export var max_stack: int = 1
## Frame in assets/sprites/items.png (16 x 16 icons).
@export var icon_frame: int = 0

@export_group("Use")
## Health restored when used (0 = not usable).
@export var heal_amount: float = 0.0
## Seconds over which the healing is applied (0 = instantly).
@export var heal_duration: float = 0.0

@export_group("Rules")
## Quest items can't be dropped or used up, so objectives can never become impossible.
@export var is_quest_item: bool = false


func is_usable() -> bool:
	return heal_amount > 0.0


func can_drop() -> bool:
	return not is_quest_item
