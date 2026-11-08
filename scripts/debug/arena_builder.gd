class_name ArenaBuilder
extends RefCounted
## Builds the six Walker difficulty-test arenas (DEVELOPMENT_ROADMAP → "Walker difficulty testing").
## Used by the automated scenario runner (tests/scenarios/) and the playable debug scene
## (scenes/debug/arena_playground.tscn). Debug content only: excluded from exported builds.

const TILE: int = 16
const TILESET_PATH: String = "res://assets/tiles/test_tileset.tres"
const FLOOR := Vector2i(4, 0)     # interior concrete
const GRASS := Vector2i(3, 0)
const WALL := Vector2i(6, 0)
const WALKER_SCENE: String = "res://scenes/zombies/walker.tscn"

const NAMES: Array[String] = [
	"S1  Open yard, 1 Walker - walk away",
	"S2  Open yard, 3 Walkers from different sides",
	"S3  1-tile corridor, 2 Walkers ahead and 1 behind",
	"S4  Store room: searching a cabinet while 2 Walkers come in",
	"S5  Dark room, 5 Walkers, no flashlight",
	"S6  Pistol shot with 6 Walkers around (one behind a wall)",
]


## Returns { root: Node2D, player_spawn: Vector2, walkers: Array[Zombie], exit: Rect2,
##           bounds: Rect2, name: String }. `root` is NOT yet in the tree.
static func build(index: int) -> Dictionary:
	var root := Node2D.new()
	root.name = "Arena%d" % (index + 1)
	var ts: TileSet = load(TILESET_PATH)
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = ts
	ground.light_mask = 1 | 2
	ground.collision_enabled = false
	root.add_child(ground)
	var walls := TileMapLayer.new()
	walls.name = "Walls"
	walls.tile_set = ts
	walls.light_mask = 1
	walls.add_to_group(&"nav_source", true)
	root.add_child(walls)

	var size := Vector2i(40, 20)
	var spawn := Vector2i(10, 10)
	var walkers: Array = []  # [tile, facing]
	var exit := Rect2()
	var dark := Rect2i()
	match index:
		0:
			spawn = Vector2i(12, 10)
			walkers = [[Vector2i(8, 10), Vector2.RIGHT]]
			exit = _tiles(Rect2i(34, 1, 5, 18))
		1:
			spawn = Vector2i(20, 10)
			walkers = [[Vector2i(14, 10), Vector2.RIGHT], [Vector2i(26, 7), Vector2.LEFT],
				[Vector2i(20, 16), Vector2.UP]]
		2:
			size = Vector2i(40, 3)  # the outer walls make a single 1-tile-wide corridor
			spawn = Vector2i(6, 1)
			walkers = [[Vector2i(20, 1), Vector2.LEFT], [Vector2i(26, 1), Vector2.LEFT],
				[Vector2i(2, 1), Vector2.RIGHT]]
			exit = _tiles(Rect2i(36, 1, 3, 1))
		3:
			size = Vector2i(24, 20)
			_box(walls, Rect2i(6, 2, 12, 9), [Vector2i(11, 10), Vector2i(12, 10)])
			spawn = Vector2i(12, 4)  # at the cabinet by the back wall
			walkers = [[Vector2i(11, 13), Vector2.UP], [Vector2i(13, 14), Vector2.UP]]
			exit = _tiles(Rect2i(1, 15, 22, 4))
		4:
			size = Vector2i(28, 18)
			_box(walls, Rect2i(4, 2, 20, 14), [Vector2i(4, 8), Vector2i(4, 9)])
			dark = Rect2i(5, 3, 18, 12)
			spawn = Vector2i(6, 9)
			walkers = [[Vector2i(10, 5), Vector2.DOWN], [Vector2i(14, 12), Vector2.UP],
				[Vector2i(17, 7), Vector2.LEFT], [Vector2i(20, 11), Vector2.LEFT], [Vector2i(12, 9), Vector2.RIGHT]]
			exit = _tiles(Rect2i(19, 3, 4, 12))
		5:
			size = Vector2i(64, 40)
			spawn = Vector2i(32, 20)
			# a wall south of the player hides one Walker (480 px shot counts as 240 behind it)
			for x in range(26, 39):
				walls.set_cell(Vector2i(x, 26), 0, WALL)
			walkers = [[Vector2i(41, 20), Vector2.RIGHT], [Vector2i(32, 5), Vector2.UP],
				[Vector2i(13, 20), Vector2.LEFT], [Vector2i(52, 32), Vector2.DOWN],
				[Vector2i(32, 37), Vector2.DOWN], [Vector2i(62, 6), Vector2.RIGHT]]

	for y in size.y:
		for x in size.x:
			ground.set_cell(Vector2i(x, y), 0, FLOOR if index in [2, 3, 4] else GRASS)
	_box(walls, Rect2i(0, 0, size.x, size.y), [])

	var bounds := Rect2(TILE, TILE, (size.x - 2) * TILE, (size.y - 2) * TILE)
	var nav := NavigationRegion2D.new()
	nav.name = "Navigation"
	nav.set_script(load("res://scripts/world/navigation_baker.gd"))
	nav.set("bounds", bounds)
	root.add_child(nav)

	if dark.size != Vector2i.ZERO:
		var dz: Node2D = load("res://scenes/world/dark_zone.tscn").instantiate()
		dz.name = "DarkRoom"
		dz.position = Vector2(dark.position * TILE)
		dz.set("size", Vector2(dark.size * TILE))
		root.add_child(dz)

	var actors := Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	root.add_child(actors)
	var made: Array[Zombie] = []
	for w in walkers:
		var z: Zombie = load(WALKER_SCENE).instantiate()
		z.position = _center(w[0])
		z.initial_facing = w[1]
		z.wanders = false
		actors.add_child(z)
		made.append(z)

	return {"root": root, "player_spawn": _center(spawn), "walkers": made, "exit": exit,
		"bounds": Rect2(0, 0, size.x * TILE, size.y * TILE), "name": NAMES[index]}


static func _center(tile: Vector2i) -> Vector2:
	return Vector2(tile * TILE) + Vector2(TILE, TILE) * 0.5


static func _tiles(r: Rect2i) -> Rect2:
	return Rect2(Vector2(r.position * TILE), Vector2(r.size * TILE))


static func _box(layer: TileMapLayer, r: Rect2i, gaps: Array) -> void:
	for x in range(r.position.x, r.end.x):
		for y in [r.position.y, r.end.y - 1]:
			if not gaps.has(Vector2i(x, y)):
				layer.set_cell(Vector2i(x, y), 0, WALL)
	for y in range(r.position.y, r.end.y):
		for x in [r.position.x, r.end.x - 1]:
			if not gaps.has(Vector2i(x, y)):
				layer.set_cell(Vector2i(x, y), 0, WALL)
