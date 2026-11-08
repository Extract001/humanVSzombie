class_name ObjectiveData
extends Resource
## One step of the objective chain (GDD §11). Data only: the ObjectiveTracker decides when it's done
## by looking at GameState, so no objective needs its own code.

enum Type {
	DELIVER_TO_STASH,  ## `items` must be in the stash; they are handed over (removed) on completion
	LOOT_FROM,         ## take `amount` of any of `item_ids` from containers whose id starts with `container_prefix`
	UNLOCK,            ## GameState.unlocks contains `unlock_id` (e.g. the warehouse gate was cut)
	HAVE_ITEM,         ## `items` are carried or in the stash
}

@export var id: StringName = &"objective"
@export var title: String = "Objective"
@export_multiline var description: String = ""
@export var type: Type = Type.DELIVER_TO_STASH
## DELIVER_TO_STASH / HAVE_ITEM: {item_id: quantity}
@export var items: Dictionary = {}
## LOOT_FROM
@export var item_ids: Array[StringName] = []
@export var amount: int = 1
@export var container_prefix: String = ""
## UNLOCK
@export var unlock_id: StringName = &""
## Short hint shown under the title on the board, e.g. "Pickup truck on the main street".
@export var hint: String = ""
