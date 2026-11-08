extends CanvasLayer
## Safehouse stash (unlimited storage, never touched by death). Bag on the left, stash on the right.
## Store / Store all move bag -> stash; Take / Take all move stash -> bag (what doesn't fit stays).

signal opened
signal closed

var player: Player
var _bag: ItemList
var _stash: ItemList
var _capacity: Label
var _status: Label
var _opened_frame: int = -1


func _ready() -> void:
	layer = 12
	visible = false
	var box: VBoxContainer = UiKit.centered_panel(self, Vector2(200, 105))
	box.add_child(UiKit.title("STASH"))
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)
	var left := VBoxContainer.new()
	cols.add_child(left)
	_capacity = UiKit.label("Bag", 8)
	left.add_child(_capacity)
	_bag = UiKit.item_list(Vector2(190, 120))
	_bag.name = "Bag"
	_bag.item_activated.connect(func(_i: int) -> void: store_selected())
	left.add_child(_bag)
	var right := VBoxContainer.new()
	cols.add_child(right)
	right.add_child(UiKit.label("Stash (unlimited, safe if you die)", 8))
	_stash = UiKit.item_list(Vector2(190, 120))
	_stash.name = "Stash"
	_stash.item_activated.connect(func(_i: int) -> void: take_selected())
	right.add_child(_stash)
	_status = UiKit.label("", 8, Color(0.9, 0.55, 0.3))
	box.add_child(_status)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(UiKit.button("Store", store_selected))
	row.add_child(UiKit.button("Store all", store_all))
	row.add_child(UiKit.button("Take", take_selected))
	row.add_child(UiKit.button("Take all", take_all))
	row.add_child(UiKit.button("Close", close))
	GameState.stash_changed.connect(func() -> void:
		if visible:
			refresh())


func bind(p: Player) -> void:
	player = p
	player.inventory.contents_changed.connect(func() -> void:
		if visible:
			refresh())
	player.died.connect(close)


func open() -> void:
	_opened_frame = Engine.get_process_frames()
	_status.text = ""
	visible = true
	player.ui_open = true
	refresh()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.ui_open = false
	closed.emit()


func refresh() -> void:
	_fill(_bag, _bag_entries())
	var stash_entries: Array = []
	var ids: Array = GameState.stash.keys()
	ids.sort()
	for id in ids:
		stash_entries.append({"id": id, "qty": GameState.stash_count(id)})
	_fill(_stash, stash_entries)
	_capacity.text = "Bag %d / %d slots" % [player.inventory.used_slots(), player.inventory.capacity_slots]


func _bag_entries() -> Array:
	var merged: Dictionary = {}
	var order: Array = []
	for s in player.inventory.slots:
		if not merged.has(s.id):
			order.append(s.id)
		merged[s.id] = int(merged.get(s.id, 0)) + int(s.qty)
	return order.map(func(id: StringName) -> Dictionary: return {"id": id, "qty": merged[id]})


static func _fill(list: ItemList, entries: Array) -> void:
	var keep: int = list.get_selected_items()[0] if list.is_anything_selected() else 0
	list.clear()
	for e in entries:
		var item: ItemData = ItemRegistry.get_item(e.id)
		var idx: int = list.add_item("%s  x%d" % [item.display_name if item else String(e.id), e.qty], ItemRegistry.icon(e.id))
		list.set_item_metadata(idx, e.id)
	if list.item_count > 0:
		list.select(mini(keep, list.item_count - 1))


static func _selected(list: ItemList) -> StringName:
	if not list.is_anything_selected():
		return &""
	return list.get_item_metadata(list.get_selected_items()[0])


func store_selected() -> void:
	var id: StringName = _selected(_bag)
	if id != &"":
		GameState.store_in_stash(player.inventory, id, player.inventory.count(id))


func store_all() -> void:
	for e in _bag_entries():
		GameState.store_in_stash(player.inventory, e.id, e.qty)


func take_selected() -> void:
	var id: StringName = _selected(_stash)
	if id == &"":
		return
	var want: int = GameState.stash_count(id)
	_report(GameState.take_from_stash(player.inventory, id, want), want)


func take_all() -> void:
	var want := 0
	var moved := 0
	for id in GameState.stash.keys():
		var n: int = GameState.stash_count(id)
		want += n
		moved += GameState.take_from_stash(player.inventory, id, n)
	_report(moved, want)


func _report(moved: int, wanted: int) -> void:
	_status.text = "Bag full - the rest stays in the stash." if moved < wanted else ""


func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"inventory") or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible and player != null and player.is_dead():
		close()
