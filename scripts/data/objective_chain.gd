class_name ObjectiveChain
extends Resource
## The objectives in the order they are played. data/objectives/objective_chain.tres

const PATH := "res://data/objectives/objective_chain.tres"

@export var objectives: Array[ObjectiveData] = []

static var _cached: ObjectiveChain


static func get_data() -> ObjectiveChain:
	if _cached == null:
		_cached = load(PATH)
	return _cached


static func clear_cache() -> void:
	_cached = null
