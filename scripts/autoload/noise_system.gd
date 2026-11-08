extends Node
## NoiseSystem (autoload): every loud action calls NoiseSystem.emit_noise(position, radius, source).
## Zombies in the "noise_listeners" group within range hear it and come to investigate.
##
## Rules (GDD §8, TECHNICAL_ARCHITECTURE §4.5):
## - A listener hears a noise if it is within radius × its hearing multiplier.
## - A wall between the noise and the listener halves the radius (one raycast per listener in range).
## - Runs only when a noise happens (never every frame); distance checks use squared lengths.

signal noise_emitted(world_position: Vector2, radius: float, source: Node)

const WORLD_MASK: int = 1
const WALL_DAMPING: float = 0.5


## Returns how many listeners heard it (useful for tests and debugging).
func emit_noise(world_position: Vector2, radius: float, source: Node = null) -> int:
	noise_emitted.emit(world_position, radius, source)
	if radius <= 0.0:
		return 0
	var space: PhysicsDirectSpaceState2D = _space_for(source)
	var heard: int = 0
	for listener in get_tree().get_nodes_in_group(&"noise_listeners"):
		if listener == source or not (listener is Node2D) or not listener.has_method(&"hear_noise"):
			continue
		var multiplier: float = listener.get_hearing_multiplier() if listener.has_method(&"get_hearing_multiplier") else 1.0
		var reach: float = radius * multiplier
		var to_listener: Vector2 = (listener as Node2D).global_position - world_position
		var dist_sq: float = to_listener.length_squared()
		if dist_sq > reach * reach:
			continue
		if space != null and _wall_between(space, world_position, (listener as Node2D).global_position):
			reach *= WALL_DAMPING
			if dist_sq > reach * reach:
				continue
		listener.hear_noise(world_position, radius, source)
		heard += 1
	return heard


func _wall_between(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK)
	return not space.intersect_ray(query).is_empty()


func _space_for(source: Node) -> PhysicsDirectSpaceState2D:
	if source is CanvasItem and (source as CanvasItem).is_inside_tree():
		return (source as CanvasItem).get_world_2d().direct_space_state
	var vp: Viewport = get_viewport()
	return vp.world_2d.direct_space_state if vp != null and vp.world_2d != null else null
