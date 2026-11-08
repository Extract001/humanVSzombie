class_name LootTable
extends Resource
## What a type of container can hold (data/loot_tables/*.tres). Rolled ONCE per container,
## the first time it is searched; the result is remembered (no re-rolling, no duplication).

## Chance (0–1) that the container is empty apart from guaranteed items.
@export_range(0.0, 1.0) var empty_chance: float = 0.2
@export var rolls_min: int = 1
@export var rolls_max: int = 2
## Parallel arrays: item id, relative weight, min and max quantity per roll.
@export var item_ids: Array[StringName] = []
@export var weights: Array[float] = []
@export var min_qty: Array[int] = []
@export var max_qty: Array[int] = []


## Returns Array of {"id": StringName, "qty": int}, merged by item.
func roll(rng: RandomNumberGenerator) -> Array:
	var out: Dictionary = {}
	if item_ids.is_empty() or rng.randf() < empty_chance:
		return []
	var total := 0.0
	for w in weights:
		total += w
	for r in rng.randi_range(rolls_min, rolls_max):
		var pick: float = rng.randf() * total
		for i in item_ids.size():
			pick -= weights[i]
			if pick <= 0.0:
				var q: int = rng.randi_range(min_qty[i], max_qty[i])
				out[item_ids[i]] = int(out.get(item_ids[i], 0)) + q
				break
	var list: Array = []
	for id in out:
		list.append({"id": id, "qty": out[id]})
	return list
