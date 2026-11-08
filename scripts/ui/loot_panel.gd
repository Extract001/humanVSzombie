extends CanvasLayer
## Loot transfer panel: shows what's in an open container/pile and moves items into the bag.
## Take (selected stack), Take all, Close. Whatever doesn't fit stays in the container.
## Walking away (or dying, or getting hit hard) closes it. The game keeps running while it's open.

signal opened
signal closed

const CLOSE_DISTANCE: float = 40.0

var player: Player
var container: LootContainer

var _list: ItemList
var _title: Label
var _bag: Label
var _status: Label
var _take: Button
var _take_all: Button
var _opened_frame: int = -1


func _ready() -> void:
	layer = 12
	visible = false
	_build()
	GameState.container_changed.connect(func(id: StringName) -> void:
		if visible and container != null and is_instance_valid(container) and id == container.container_id:
			refresh())


func bind(p: Player) -> void:
	player = p
	player.loot_opened.connect(open)
	player.inventory.contents_changed.connect(func() -> void:
		if visible:
			refresh())
	player.died.connect(close)


func open(c: LootContainer) -> void:
	container = c
	_opened_frame = Engine.get_process_frames()
	_status.text = ""
	visible = true
	player.ui_open = true
	refresh()
	if _list.item_count > 0:
		_list.select(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_take_all.grab_focus()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	container = null
	if player != null:
		player.ui_open = false
	closed.emit()


func refresh() -> void:
	if container == null or not is_instance_valid(container):
		close()
		return
	_title.text = container.display_name.to_upper()
	var keep: int = _list.get_selected_items()[0] if _list.is_anything_selected() else 0
	_list.clear()
	for e in container.contents():
		var item: ItemData = ItemRegistry.get_item(e.id)
		var label: String = (item.display_name if item else String(e.id)) + "  x%d" % int(e.qty)
		if item != null and item.is_quest_item:
			label += "  (quest)"
		var idx: int = _list.add_item(label, ItemRegistry.icon(e.id))
		_list.set_item_metadata(idx, e.id)
	if _list.item_count == 0:
		_list.add_item("(empty)")
		_list.set_item_disabled(0, true)
		_list.set_item_selectable(0, false)
	elif keep < _list.item_count:
		_list.select(keep)
	var inv: Inventory = player.inventory
	_bag.text = "Bag %d / %d slots" % [inv.used_slots(), inv.capacity_slots]
	var has_items: bool = not container.contents().is_empty()
	_take.disabled = not has_items
	_take_all.disabled = not has_items


func take_selected() -> void:
	if not _list.is_anything_selected():
		return
	var id: Variant = _list.get_item_metadata(_list.get_selected_items()[0])
	if id == null:
		return
	var qty := 0
	for e in container.contents():
		if e.id == id:
			qty += int(e.qty)
	var moved: int = GameState.take_from(container.container_id, id, qty, player.inventory)
	_after_take(moved, qty)


func take_all() -> void:
	if container == null:
		return
	var before := 0
	for e in container.contents():
		before += int(e.qty)
	GameState.take_all(container.container_id, player.inventory)
	var after := 0
	for e in GameState.get_contents(container.container_id):
		after += int(e.qty)
	_after_take(before - after, before)


func _after_take(moved: int, wanted: int) -> void:
	if moved > 0:
		AudioManager.play_at(preload("res://assets/audio/sfx/pickup.wav"), player.global_position, -6.0)
	_status.text = "Bag full - the rest stays here." if moved < wanted else ""
	if container != null and is_instance_valid(container) and container.is_pile and container.contents().is_empty():
		close()  # the pile node goes away when emptied
	else:
		refresh()


func _process(_delta: float) -> void:
	if not visible:
		return
	if container == null or not is_instance_valid(container) or player.is_dead() \
			or player.global_position.distance_to(container.global_position) > CLOSE_DISTANCE:
		close()


## _input (not _unhandled_input): Tab is also the GUI's focus key, so a focused button would eat it.
func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed(&"interact"):
		take_all()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"inventory"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -200
	panel.offset_right = -12
	panel.offset_top = -90
	panel.offset_bottom = 90
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	panel.add_child(box)
	_title = _label("CONTAINER", 10, Color(0.95, 0.88, 0.6))
	box.add_child(_title)
	_list = ItemList.new()
	_list.name = "Items"
	_list.custom_minimum_size = Vector2(176, 100)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(16, 16)
	_list.item_activated.connect(func(_i: int) -> void: take_selected())
	box.add_child(_list)
	_bag = _label("Bag 0 / 12 slots", 8)
	box.add_child(_bag)
	_status = _label("", 8, Color(0.9, 0.55, 0.3))
	box.add_child(_status)
	var row := HBoxContainer.new()
	box.add_child(row)
	_take = _button("Take", take_selected)
	row.add_child(_take)
	_take_all = _button("Take all [E]", take_all)
	row.add_child(_take_all)
	row.add_child(_button("Close", close))


static func _label(text: String, size: int, color: Color = Color(0.88, 0.85, 0.76)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 10 if size <= 10 else 20)  # pixel font 1x / 2x
	l.add_theme_color_override(&"font_color", color)
	return l


static func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void: AudioManager.play_ui())
	b.pressed.connect(action)
	return b
