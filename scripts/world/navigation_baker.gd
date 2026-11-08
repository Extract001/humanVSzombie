class_name NavigationBaker
extends NavigationRegion2D
## Builds the walkable-area mesh for zombie pathfinding when the level loads (about 2 ms).
## It reads the collision of every node in the "nav_source" group (wall and prop tile layers),
## keeps `agent_radius` pixels away from them, and covers the rectangle `bounds`.
## Call rebake() after the level changes shape (e.g. a door opens, Phase 4).

@export var bounds: Rect2 = Rect2(16, 16, 928, 608)
@export var agent_radius: float = 6.0
@export var source_group: StringName = &"nav_source"

## Physics layer 7: bodies only the navigation bake sees (nothing collides with it).
const NAV_ONLY_LAYER: int = 64
## Navigation layer 2: window links. Zombies path through windows (layers 1+2); the default
## path queries (layer 1) go around them, through the doors.
const WINDOW_NAV_LAYER: int = 2


func _ready() -> void:
	add_to_group(&"navigation_bakers")
	# Deferred: bake after the whole level (doors, vehicles...) has finished loading.
	rebake.call_deferred()


func rebake() -> void:
	var poly := NavigationPolygon.new()
	poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	# Physics layer 1 (world) + layer 7 (nav-only blockers: the safehouse windows, Slice 1).
	poly.parsed_collision_mask = 1 | NAV_ONLY_LAYER
	poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	poly.source_geometry_group_name = source_group
	poly.agent_radius = agent_radius
	var r: Rect2 = bounds
	poly.add_outline(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)]))
	navigation_polygon = poly
	bake_navigation_polygon(false)
