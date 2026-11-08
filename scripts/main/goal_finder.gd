class_name GoalFinder
extends RefCounted
## Fun pass: "where do I go now?" for the HUD goal arrow.
## Returns {"pos": Vector2, "label": String} or {} when there's nothing to point at.
## Priority: dusk/night outside → HOME. Dusk/night inside → a window that needs boards (if you
## have scrap). Otherwise the current objective: the container that still holds what you need,
## the stash when you carry enough, the gate when you have the cutters, the radio at the end.

static func find(game: Node) -> Dictionary:
	var player: Player = game.player
	if player == null or player.is_dead():
		return {}
	var map: Node = game.get_node("World/Map")
	var inside: bool = game.is_in_safehouse()
	if GameState.phase != GameState.Phase.DAY:
		if not inside:
			var door: Node2D = map.get_node_or_null("SafehouseDoor")
			return {"pos": door.global_position + Vector2(8, 8) if door != null else game.respawn_point(), "label": "HOME"}
		if player.inventory.count(&"scrap") > 0:
			var worst: Barricade = null
			for b in game.get_tree().get_nodes_in_group(&"barricades"):
				var w := b as Barricade
				if w.planks() < Barricade.SIEGE.max_planks and (worst == null or w.health() < worst.health()):
					worst = w
			if worst != null:
				return {"pos": worst.center(), "label": "BOARD UP"}
		return {}
	var o: ObjectiveData = game.objectives.current()
	if o == null:
		return {}
	match o.type:
		ObjectiveData.Type.DELIVER_TO_STASH:
			var missing: Array = []
			var carrying_all := true
			for id in o.items:
				var need: int = int(o.items[id]) - GameState.stash_count(id)
				if need > 0 and player.inventory.count(id) < need:
					carrying_all = false
					missing.append(StringName(id))
			if carrying_all:
				return _node_goal(map.get_node_or_null("Stash"), "STASH")
			return _nearest_container_with(game, missing, "", "SEARCH")
		ObjectiveData.Type.LOOT_FROM:
			return _nearest_container_with(game, o.item_ids, o.container_prefix, "SEARCH")
		ObjectiveData.Type.HAVE_ITEM:
			var want: Array = []
			for id in o.items:
				want.append(StringName(id))
			return _nearest_container_with(game, want, "", "SEARCH")
		ObjectiveData.Type.UNLOCK:
			if o.unlock_id == &"radio_repaired":
				return _node_goal(map.get_node_or_null("RadioDesk"), "RADIO")
			for d in game.get_tree().get_nodes_in_group(&"doors"):
				var door := d as Door
				if door.unlock_id != o.unlock_id:
					continue
				if door.unlock_item == &"" or player.inventory.count(door.unlock_item) > 0:
					return {"pos": door.global_position + door.span() * 0.5, "label": "CUT"}
				return _nearest_container_with(game, [door.unlock_item], "", "SEARCH")
	return {}


static func _node_goal(n: Node, label: String) -> Dictionary:
	return {"pos": (n as Node2D).global_position, "label": label} if n is Node2D else {}


## Nearest container that still has (or, unsearched, is guaranteed to have) one of `item_ids`.
## With a prefix (e.g. "pharmacy_") any unsearched container of that place counts too.
static func _nearest_container_with(game: Node, item_ids: Array, prefix: String, label: String) -> Dictionary:
	var player: Player = game.player
	var best: LootContainer = null
	var best_d := INF
	for c in game.get_tree().get_nodes_in_group(&"loot_containers"):
		var lc := c as LootContainer
		if lc == null or lc.is_pile:
			continue
		if prefix != "" and not String(lc.container_id).begins_with(prefix):
			continue
		var useful := false
		if GameState.is_rolled(lc.container_id):
			for e in GameState.get_contents(lc.container_id):
				if item_ids.has(e.id):
					useful = true
		else:
			var g: Dictionary = QuestGuarantees.for_container(lc.container_id)
			for id in item_ids:
				if g.has(id):
					useful = true
			if prefix != "":
				useful = true
		if not useful:
			continue
		var d: float = lc.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = lc
	if best == null:
		return {}
	return {"pos": best.global_position, "label": label}
