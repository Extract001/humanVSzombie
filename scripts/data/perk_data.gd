class_name PerkData
extends Resource
## One perk card (Slice 2). Picked at dawn, 1 of 3. Each pick adds a stack (up to max_stacks).
## `amount` is per stack; what it changes depends on `id` (see Perks).

@export var id: StringName = &""
@export var title: String = ""
## Shown on the card. Use {v} for the per-stack value as a percentage or number (see value_text).
@export_multiline var description: String = ""
@export var amount: float = 0.0
@export var max_stacks: int = 2
## True: the card shows amount as a percentage ("+30%").
@export var percent: bool = true


func value_text() -> String:
	return ("%d%%" % roundi(absf(amount) * 100.0)) if percent else str(roundi(absf(amount)))


func card_text() -> String:
	return description.replace("{v}", value_text())
