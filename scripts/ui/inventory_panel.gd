extends CanvasLayer
## Inventory panel (Tab or I): the 12 bag slots, item description, Use and Drop.
## Quest items can't be used up or dropped. The game keeps running while it's open.

signal opened
signal closed

var player: Player

var _grid: ItemList
var _name: Label
var _desc: Label
var _capacity: Label
var _use: Button
var _drop: Button


func _ready() -> void:
	layer = 12
	visible = false
	_build()


func bind(p: Player) -> void:
	player = p
	player.inventory.contents_changed.connect(func() -> void:
		if visible:
			refresh())
	player.died.connect(close)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if player == null or player.is_dead():
		return
	visible = true
	player.ui_open = true
	refresh()
	if _grid.item_count > 0:
		_grid.select(0)
		_on_selected(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.ui_open = false
	closed.emit()


func refresh() -> void:
	var keep: int = _grid.get_selected_items()[0] if _grid.is_anything_selected() else 0
	_grid.clear()
	for s in player.inventory.slots:
		var idx: int = _grid.add_item("x%d" % int(s.qty), ItemRegistry.icon(s.id))
		_grid.set_item_metadata(idx, s.id)
		var item: ItemData = ItemRegistry.get_item(s.id)
		_grid.set_item_tooltip(idx, item.display_name if item else String(s.id))
	for i in player.inventory.capacity_slots - player.inventory.slots.size():
		var idx: int = _grid.add_item("")
		_grid.set_item_selectable(idx, false)
	_capacity.text = "%d / %d slots" % [player.inventory.used_slots(), player.inventory.capacity_slots]
	if keep < player.inventory.slots.size():
		_grid.select(keep)
		_on_selected(keep)
	else:
		_show_item(&"")


func selected_item() -> StringName:
	if not _grid.is_anything_selected():
		return &""
	var id: Variant = _grid.get_item_metadata(_grid.get_selected_items()[0])
	return id if id != null else &""


func use_selected() -> void:
	var id: StringName = selected_item()
	if id != &"":
		player.use_item(id)


## Drops the whole selected stack.
func drop_selected() -> void:
	if not _grid.is_anything_selected():
		return
	var idx: int = _grid.get_selected_items()[0]
	if idx >= player.inventory.slots.size():
		return
	var slot: Dictionary = player.inventory.slots[idx]
	player.drop_item(slot.id, int(slot.qty))


func _on_selected(idx: int) -> void:
	var id: Variant = _grid.get_item_metadata(idx)
	_show_item(id if id != null else &"")


func _show_item(id: StringName) -> void:
	var item: ItemData = ItemRegistry.get_item(id) if id != &"" else null
	_name.text = item.display_name.to_upper() if item else ""
	_desc.text = item.description if item else ""
	_use.disabled = item == null or not item.is_usable()
	_drop.disabled = item == null or not item.can_drop()


## _input (not _unhandled_input): Tab is also the GUI's focus key, so a focused button would eat it.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -150
	panel.offset_right = 150
	panel.offset_top = -95
	panel.offset_bottom = 95
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label("INVENTORY", 10, Color(0.95, 0.88, 0.6))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_capacity = _label("0 / 12 slots", 8)
	head.add_child(_capacity)
	_grid = ItemList.new()
	_grid.name = "Slots"
	_grid.max_columns = 6
	_grid.same_column_width = true
	_grid.fixed_column_width = 40
	_grid.icon_mode = ItemList.ICON_MODE_TOP
	_grid.fixed_icon_size = Vector2i(16, 16)
	_grid.custom_minimum_size = Vector2(284, 84)
	_grid.item_selected.connect(_on_selected)
	_grid.item_activated.connect(func(_i: int) -> void: use_selected())
	box.add_child(_grid)
	_name = _label("", 9, Color(0.95, 0.92, 0.8))
	box.add_child(_name)
	_desc = _label("", 8)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(284, 22)
	box.add_child(_desc)
	var row := HBoxContainer.new()
	box.add_child(row)
	_use = _button("Use", use_selected)
	row.add_child(_use)
	_drop = _button("Drop", drop_selected)
	row.add_child(_drop)
	row.add_child(_button("Close [Tab]", close))


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
