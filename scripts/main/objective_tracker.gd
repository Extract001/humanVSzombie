class_name ObjectiveTracker
extends Node
## Plays the objective chain (data/objectives/objective_chain.tres) in order.
##
## No objective has its own code: each one is a condition on GameState (stash, unlocks, loot taken)
## or on the player's bag. Whenever any of those change, evaluate() checks the current objective; if it
## is met it is completed exactly once (DELIVER_TO_STASH hands the items over) and the next one starts.
## Progress made early still counts: e.g. medical items taken from the pharmacy before "First aid"
## became active, or a gate cut before "Cut the lock" (GameState keeps that history).

signal objective_changed(objective: ObjectiveData)   ## the new current objective (null = chain finished)
signal objective_completed(objective: ObjectiveData)
signal progress_changed(objective: ObjectiveData)
signal chain_completed

## Quest item -> the objective that uses it up. Until that objective is complete the item must exist
## somewhere (bag, stash, a container, a pile or a backpack); see validate_quest_items().
const QUEST_ITEM_NEEDED_UNTIL: Dictionary = {&"bolt_cutters": &"cut_the_lock", &"radio_part": &"last_signal"}

var player: Player
var _evaluating: bool = false


func bind(p: Player) -> void:
	player = p
	player.inventory.contents_changed.connect(evaluate)
	GameState.stash_changed.connect(evaluate)
	GameState.unlocks_changed.connect(func(_id: StringName) -> void: evaluate())
	GameState.item_taken.connect(func(_c: StringName, _i: StringName, _q: int) -> void: evaluate())
	evaluate()


func chain() -> Array[ObjectiveData]:
	return ObjectiveChain.get_data().objectives


func is_completed(objective_id: StringName) -> bool:
	return GameState.objectives_completed.has(objective_id)


## The objective being worked on, or null when the whole chain is done.
func current() -> ObjectiveData:
	for o in chain():
		if not is_completed(o.id):
			return o
	return null


func is_chain_complete() -> bool:
	return current() == null


## Completes objectives while their conditions hold. Safe to call any time; never completes twice.
func evaluate() -> void:
	if _evaluating:
		return
	_evaluating = true
	var o: ObjectiveData = current()
	while o != null and is_met(o):
		_complete(o)
		o = current()
		objective_changed.emit(o)
		if o == null:
			chain_completed.emit()
	_evaluating = false
	progress_changed.emit(current())


func is_met(o: ObjectiveData) -> bool:
	match o.type:
		ObjectiveData.Type.DELIVER_TO_STASH:
			for id in o.items:
				if GameState.stash_count(StringName(id)) < int(o.items[id]):
					return false
			return true
		ObjectiveData.Type.LOOT_FROM:
			return looted_count(o) >= o.amount
		ObjectiveData.Type.UNLOCK:
			return GameState.has_unlock(o.unlock_id)
		ObjectiveData.Type.HAVE_ITEM:
			for id in o.items:
				if owned_count(StringName(id)) < int(o.items[id]):
					return false
			return true
	return false


## Bag + stash.
func owned_count(item_id: StringName) -> int:
	var carried: int = player.inventory.count(item_id) if player != null else 0
	return carried + GameState.stash_count(item_id)


func looted_count(o: ObjectiveData) -> int:
	var total := 0
	for cid in GameState.taken_log:
		if not String(cid).begins_with(o.container_prefix):
			continue
		for item_id in GameState.taken_log[cid]:
			if o.item_ids.has(StringName(item_id)):
				total += int(GameState.taken_log[cid][item_id])
	return total


## e.g. "Canned food 2/5 · Water 1/3"
func progress_text(o: ObjectiveData) -> String:
	if o == null:
		return ""
	var parts: Array[String] = []
	match o.type:
		ObjectiveData.Type.DELIVER_TO_STASH:
			for id in o.items:
				parts.append("%s %d/%d in stash" % [_name(id), mini(GameState.stash_count(StringName(id)), int(o.items[id])), int(o.items[id])])
		ObjectiveData.Type.LOOT_FROM:
			parts.append("found %d/%d" % [mini(looted_count(o), o.amount), o.amount])
		ObjectiveData.Type.HAVE_ITEM:
			for id in o.items:
				parts.append("%s %d/%d" % [_name(id), mini(owned_count(StringName(id)), int(o.items[id])), int(o.items[id])])
		ObjectiveData.Type.UNLOCK:
			pass
	return " · ".join(parts)


func _complete(o: ObjectiveData) -> void:
	if is_completed(o.id):
		return
	if o.type == ObjectiveData.Type.DELIVER_TO_STASH:
		for id in o.items:  # handed over: the supplies are used for the shelter
			GameState.stash_remove(StringName(id), int(o.items[id]))
	GameState.objectives_completed.append(o.id)
	objective_completed.emit(o)


## The radio desk: repairs the radio when "Last signal" is the current objective and the radio
## component is carried or in the stash. Returns a message for the player ("" = repaired).
func try_repair_radio() -> String:
	if GameState.has_unlock(&"radio_repaired"):
		return ""
	var o: ObjectiveData = current()
	if o == null or o.id != &"last_signal":
		return "The radio is dead. It needs a part - and you need supplies first."
	if player.inventory.remove_item(&"radio_part", 1) == 0 and GameState.stash_remove(&"radio_part", 1) == 0:
		return "You need the radio component."
	GameState.add_unlock(&"radio_repaired")
	return ""


## Safety net (TECHNICAL_ARCHITECTURE §4.8b): if a quest item that is still needed exists nowhere
## (bag, stash, containers, piles, backpacks), put it back in its designated container.
## The container's guarantee covers it if the container hasn't been searched yet.
## Returns the item ids that were restored. Called by game.gd at start (and by loading, Phase 10).
func validate_quest_items() -> Array[StringName]:
	var restored: Array[StringName] = []
	for item_id in QUEST_ITEM_NEEDED_UNTIL:
		if is_completed(QUEST_ITEM_NEEDED_UNTIL[item_id]):
			continue
		if item_id == &"bolt_cutters" and GameState.has_unlock(&"warehouse_gate"):
			continue
		if owned_count(item_id) + GameState.world_count(item_id) > 0:
			continue
		var home: StringName = _designated_container(item_id)
		if home == &"" or not GameState.is_rolled(home):
			continue  # not searched yet: its guarantee still provides the item
		GameState.put_into(home, item_id, 1)
		push_warning("Quest item %s was missing; put back in %s" % [item_id, home])
		restored.append(item_id)
	return restored


static func _designated_container(item_id: StringName) -> StringName:
	var g: Dictionary = QuestGuarantees.get_data().guarantees
	for cid in g:
		if g[cid].has(String(item_id)):
			return StringName(cid)
	return &""


static func _name(id: Variant) -> String:
	var item: ItemData = ItemRegistry.get_item(StringName(id))
	return item.display_name if item != null else String(id)
