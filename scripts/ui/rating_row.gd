class_name RatingRow
extends VBoxContainer
## Batch 2 — playtest: "How fun was that? 1-5". Only shown in playtest mode; the answer goes to the
## session log (SessionLog.rate). After a click it says thanks and the buttons go away.

signal rated(stars: int)

var _label: Label
var _row: HBoxContainer


func _ready() -> void:
	name = "RatingRow"
	alignment = BoxContainer.ALIGNMENT_CENTER
	_label = UiKit.label("Playtest: how fun was it so far?", 10, Color(0.62, 0.86, 0.9))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_row)
	var words := ["boring", "meh", "ok", "fun", "great"]
	for i in 5:
		var b: Button = UiKit.button(str(i + 1), rate.bind(i + 1))
		b.name = "Star%d" % (i + 1)
		b.tooltip_text = words[i]
		b.custom_minimum_size = Vector2(22, 16)
		b.add_theme_font_size_override(&"font_size", 10)
		_row.add_child(b)
	refresh()


## Shows the row again (a new death / pause) if playtest mode is on.
func refresh() -> void:
	visible = Settings.playtest_mode and not GameState.records_disabled
	if _row != null:
		_row.visible = true
		_label.text = "Playtest: how fun was it so far? (1 = boring, 5 = great)"


func rate(stars: int) -> void:
	get_tree().call_group(&"session_log", &"rate", stars)
	_label.text = "Thanks! (%d/5 saved in your playtest log)" % stars
	_row.visible = false
	rated.emit(stars)
