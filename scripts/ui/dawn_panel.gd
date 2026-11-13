extends CanvasLayer
## Slice 1: the morning summary after a survived night (and the evacuation after night 10).
## Slice 2: then pick 1 of 3 perk cards (click, or keys 1/2/3); Continue appears after the pick
## (or straight away when every perk is maxed). Pauses the game while open.

signal opened
signal closed

var player: Player
var _title: Label
var _text: Label
var _button: Button
var _opened_frame: int = -1
var _cards_box: HBoxContainer
var _pick_label: Label
var _offer: Array[PerkData] = []
## Picks this run of the panel (tests read it).
var picked: StringName = &""


func _ready() -> void:
	layer = 13
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box: VBoxContainer = UiKit.centered_panel(self, Vector2(170, 80))
	_title = UiKit.title("DAWN")
	_title.add_theme_color_override(&"font_color", UiKit.OBJECTIVE)
	box.add_child(_title)
	_text = UiKit.label("", 10)
	_text.name = "Summary"
	_text.custom_minimum_size = Vector2(320, 0)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)
	_pick_label = UiKit.label("CHOOSE ONE  (1 / 2 / 3)", 10, Color(1, 0.88, 0.45))
	_pick_label.name = "PickLabel"
	box.add_child(_pick_label)
	_cards_box = HBoxContainer.new()
	_cards_box.name = "Cards"
	_cards_box.add_theme_constant_override(&"separation", 6)
	box.add_child(_cards_box)
	_button = UiKit.button("Continue", close)
	_button.name = "Continue"
	box.add_child(_button)


func bind(p: Player) -> void:
	player = p


func show_summary(s: Dictionary) -> void:
	var lines: PackedStringArray = []
	if s.get("evac", false):
		_title.text = "RESCUED"
		lines.append("At first light the convoy rolls in over the rail bridge.")
		lines.append("You survived %d nights in Ashford Lane." % int(s.night))
		lines.append("")
		_button.text = "Keep surviving"
	else:
		_title.text = "DAWN - NIGHT %d SURVIVED" % int(s.night)
		_button.text = "Continue"
	lines.append("The horde: %d   Killed tonight: %d   Left at dawn: %d" % [int(s.horde), int(s.killed), int(s.left)])
	lines.append("Boards broken: %d   Yesterday's Heat: %d" % [int(s.boards_lost), roundi(float(s.heat))])
	if s.has("score"):
		lines.append("Night bonus +%d   SCORE %d   %s" % [int(s.night_points), int(s.score),
			"NEW BEST!" if s.get("new_best", false) else "Best %d" % int(s.get("best", 0))])
	if int(s.get("restocked", 0)) > 0:
		lines.append("Fresh supplies turned up in %d places around town." % int(s.restocked))
	if not s.get("evac", false):
		lines.append("Day %d begins. Game saved." % GameState.day)
	_text.text = "\n".join(lines)
	_build_cards()
	_opened_frame = Engine.get_process_frames()
	visible = true
	if player != null:
		player.ui_open = true
	get_tree().paused = true
	if _offer.is_empty():
		_focus.call_deferred(_button)
	else:
		_focus.call_deferred(_cards_box.get_child(0))
	opened.emit()


func _build_cards() -> void:
	picked = &""
	for c in _cards_box.get_children():
		_cards_box.remove_child(c)
		c.queue_free()
	_offer = Perks.offer(3)
	for i in _offer.size():
		var p: PerkData = _offer[i]
		var have: int = Perks.stacks(p.id)
		var b := Button.new()
		b.name = "Card%d" % (i + 1)
		b.text = "%d  %s%s\n%s" % [i + 1, p.title.to_upper(), "" if have == 0 else " " + "I".repeat(have + 1),
			_wrap(p.card_text(), 24)]
		b.custom_minimum_size = Vector2(150, 54)
		b.add_theme_font_size_override(&"font_size", 10)
		b.pressed.connect(choose.bind(i))
		_cards_box.add_child(b)
	_cards_box.visible = not _offer.is_empty()
	_pick_label.visible = not _offer.is_empty()
	_button.visible = _offer.is_empty()


## Takes card `index` (0-2): adds the perk and shows Continue.
func choose(index: int) -> void:
	if index < 0 or index >= _offer.size() or picked != &"":
		return
	picked = _offer[index].id
	GameState.add_perk(picked)
	AudioManager.play_ui(preload("res://assets/audio/sfx/streak.wav"), -4.0)
	_pick_label.text = "%s - %s" % [_offer[index].title.to_upper(), _offer[index].card_text()]
	_cards_box.visible = false
	_button.visible = true
	_focus.call_deferred(_button)


func _focus(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()


## Tests and bots: take the first card (if any) and continue.
func pick_first_and_close() -> void:
	if _cards_box.visible and picked == &"":
		choose(0)
	close()


static func _wrap(text: String, width: int) -> String:
	var out: PackedStringArray = []
	var line := ""
	for word in text.split(" "):
		if line.length() + word.length() + 1 > width and line != "":
			out.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	out.append(line)
	return "\n".join(out)


func close() -> void:
	if not visible or (_cards_box.visible and picked == &""):
		return   # pick a card first
	visible = false
	get_tree().paused = false
	if player != null:
		player.ui_open = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if _cards_box.visible and event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_3:
			choose(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		if _cards_box.visible:
			return   # Enter on a focused card presses it (the Button handles that)
		close()
		get_viewport().set_input_as_handled()
