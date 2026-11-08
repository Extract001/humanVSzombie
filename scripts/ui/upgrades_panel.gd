class_name UpgradesPanel
extends CanvasLayer
## Safehouse Workbench: craft permanent survivor perks using scavenged Scrap metal.

signal opened
signal closed

var player: Player
var _box: VBoxContainer
var _scrap_label: Label
var _items_box: VBoxContainer
var _opened_frame: int = -1

const UPGRADES: Array[Dictionary] = [
	{
		"id": &"ext_mag",
		"name": "Extended Magazine",
		"desc": "Pistol holds 12 rounds (was 8).",
		"cost": 4,
	},
	{
		"id": &"cardio",
		"name": "Cardio Training",
		"desc": "+30 Max Stamina (130) and 25% faster stamina recovery.",
		"cost": 3,
	},
	{
		"id": &"thick_skin",
		"name": "Reinforced Jacket",
		"desc": "+30 Max Health (130 HP) and 20% reduced bite damage.",
		"cost": 5,
	},
	{
		"id": &"spikes",
		"name": "Spiked Planks",
		"desc": "Window barricades reflect 15 damage back to attackers.",
		"cost": 4,
	},
	{
		"id": &"tactical_light",
		"name": "LED Mod",
		"desc": "Flashlight battery drains 50% slower (2x battery life).",
		"cost": 2,
	},
]


func _ready() -> void:
	layer = 12
	visible = false
	_box = UiKit.centered_panel(self, Vector2(190, 115))
	_box.add_child(UiKit.title("WORKBENCH UPGRADES"))
	_scrap_label = UiKit.label("Scrap: 0", 10, Color(0.95, 0.75, 0.35))
	_box.add_child(_scrap_label)
	_box.add_child(UiKit.label("Spend scrap to reinforce yourself and the safehouse:", 8, UiKit.TEXT.darkened(0.2)))

	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override(&"separation", 4)
	_box.add_child(_items_box)

	var close_btn: Button = UiKit.button("Close", close)
	_box.add_child(close_btn)


func bind(p: Player) -> void:
	player = p
	player.died.connect(close)


func open() -> void:
	_opened_frame = Engine.get_process_frames()
	refresh()
	visible = true
	if player != null:
		player.ui_open = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.ui_open = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func refresh() -> void:
	var scrap: int = player.inventory.count(&"scrap") if player != null else 0
	_scrap_label.text = "Available Scrap: %d" % scrap

	for child in _items_box.get_children():
		child.queue_free()

	for u in UPGRADES:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title_col := Color(0.95, 0.88, 0.55) if GameState.has_upgrade(u.id) else UiKit.TEXT
		var title_lbl: Label = UiKit.label(u.name, 10, title_col)
		var desc_lbl: Label = UiKit.label(u.desc, 8, UiKit.TEXT.darkened(0.25))
		info.add_child(title_lbl)
		info.add_child(desc_lbl)
		row.add_child(info)

		if GameState.has_upgrade(u.id):
			var owned := UiKit.label("[OWNED ✓]", 10, Color(0.4, 0.9, 0.4))
			row.add_child(owned)
		else:
			var cost: int = int(u.cost)
			var btn: Button = UiKit.button("Craft (%d)" % cost, func() -> void: _craft(u))
			btn.disabled = scrap < cost
			row.add_child(btn)

		_items_box.add_child(row)


func _craft(u: Dictionary) -> void:
	var cost: int = int(u.cost)
	if player == null or player.inventory.count(&"scrap") < cost:
		return
	player.inventory.remove_item(&"scrap", cost)
	GameState.add_upgrade(u.id)
	AudioManager.play_at(preload("res://assets/audio/sfx/barricade_build.wav"), player.global_position, 0.0)
	player.message.emit("Crafted: " + String(u.name))
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()
