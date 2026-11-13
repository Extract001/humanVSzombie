class_name Inventory
extends Node
## The player's bag: `capacity_slots` slots; each slot holds one item type up to its max_stack.
## Reserve ammo lives here (weapons only hold what is loaded in their magazines).
## Quantities never go negative; anything that doesn't fit is reported back, never lost.
##
## Public API (also used by weapons since Phase 2): count(), add_item(), remove_item().

signal item_changed(item_id: StringName, quantity: int)
## Any change at all (for UI refresh).
signal contents_changed

@export var capacity_slots: int = 12
## Starting contents, e.g. {&"ammo_pistol": 16, &"bandage": 2}. Added at _ready.
@export var starting_items: Dictionary = {}

## Each slot: {"id": StringName, "qty": int}
var slots: Array[Dictionary] = []


func _ready() -> void:
	for id in starting_items:
		add_item(StringName(id), int(starting_items[id]))


func count(item_id: StringName) -> int:
	var total := 0
	for s in slots:
		if s.id == item_id:
			total += int(s.qty)
	return total


func used_slots() -> int:
	return slots.size()


static func stack_size(item_id: StringName) -> int:
	var item: ItemData = ItemRegistry.get_item(item_id)
	return item.max_stack if item != null else 99


## How many of item_id would fit right now.
func space_for(item_id: StringName) -> int:
	var per_stack: int = stack_size(item_id)
	var room := 0
	for s in slots:
		if s.id == item_id:
			room += per_stack - int(s.qty)
	room += (capacity_slots - slots.size()) * per_stack
	var item: ItemData = ItemRegistry.get_item(item_id)
	if item != null and item.weapon != null:
		return 99   # weapons skip the bag (Slice 2)
	return room


## Adds as much as fits. Returns how many did NOT fit (0 = everything was added).
func add_item(item_id: StringName, quantity: int) -> int:
	if quantity <= 0 or item_id == &"":
		return 0
	var left: int = quantity
	var per_stack: int = stack_size(item_id)
	var item: ItemData = ItemRegistry.get_item(item_id)
	if item != null and item.weapon != null:
		# Slice 2: weapons never need bag space (the player moves them to a weapon slot at once).
		slots.append({"id": item_id, "qty": quantity})
		_changed(item_id)
		return 0
	for s in slots:  # top up existing stacks first
		if left == 0:
			break
		if s.id == item_id and s.qty < per_stack:
			var put: int = mini(left, per_stack - int(s.qty))
			s.qty += put
			left -= put
	while left > 0 and slots.size() < capacity_slots:
		var put: int = mini(left, per_stack)
		slots.append({"id": item_id, "qty": put})
		left -= put
	if left != quantity:
		_changed(item_id)
	return left


## Removes up to `quantity`. Returns how many were actually removed (never goes negative).
func remove_item(item_id: StringName, quantity: int) -> int:
	if quantity <= 0:
		return 0
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):  # take from the last stacks first
		if removed == quantity:
			break
		if slots[i].id != item_id:
			continue
		var take: int = mini(quantity - removed, int(slots[i].qty))
		slots[i].qty -= take
		removed += take
		if slots[i].qty == 0:
			slots.remove_at(i)
	if removed > 0:
		_changed(item_id)
	return removed


## Empties the bag and returns everything as [{"id", "qty"}] (merged by item). Used on death.
func take_all() -> Array:
	var merged: Dictionary = {}
	for s in slots:
		merged[s.id] = int(merged.get(s.id, 0)) + int(s.qty)
	var ids: Array = merged.keys()
	slots.clear()
	for id in ids:
		_changed(id)
	var out: Array = []
	for id in ids:
		out.append({"id": id, "qty": merged[id]})
	return out


## Save data: the slots in order, e.g. [{"id": "ammo_pistol", "qty": 16}, ...].
func to_array() -> Array:
	return slots.map(func(s: Dictionary) -> Dictionary: return {"id": String(s.id), "qty": int(s.qty)})


## Replaces the contents with saved slots (stack sizes and capacity still apply).
func from_array(saved: Array) -> void:
	var ids: Array = slots.map(func(s: Dictionary) -> StringName: return s.id)
	slots.clear()
	for e in saved:
		add_item(StringName(e.get("id", "")), int(e.get("qty", 0)))
	for id in ids:
		_changed(id)
	contents_changed.emit()


func _changed(item_id: StringName) -> void:
	item_changed.emit(item_id, count(item_id))
	contents_changed.emit()
