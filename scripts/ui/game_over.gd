extends CanvasLayer
## Death screen (GDD §12): time survived, zombies killed, what was left in the backpack.
## "Respawn at safehouse" continues the same run (the backpack stays where you fell);
## "New game" (RetryButton) clears the run and reloads the scene; "Main menu" goes back to the menu.

signal retry_requested
signal respawn_requested
signal main_menu_requested

@onready var time_label: Label = %TimeLabel
@onready var kills_label: Label = %KillsLabel
@onready var backpack_label: Label = %BackpackLabel
@onready var respawn_button: Button = %RespawnButton
@onready var retry_button: Button = %RetryButton
@onready var main_menu_button: Button = %MainMenuButton
## Batch 2: playtest rating and the daily-run ending.
var rating: RatingRow
var _daily_over: bool = false
var _title: Label


func _ready() -> void:
	visible = false
	for b in [retry_button, respawn_button, main_menu_button]:
		b.pressed.connect(func() -> void: AudioManager.play_ui())
	retry_button.pressed.connect(_on_retry_pressed)
	respawn_button.pressed.connect(_on_respawn_pressed)
	main_menu_button.pressed.connect(func() -> void: main_menu_requested.emit())
	_title = $Root/Box.get_child(0) as Label
	rating = RatingRow.new()
	$Root/Box.add_child(rating)
	$Root/Box.move_child(rating, respawn_button.get_index())
	$Root/Box.offset_top = -115.0
	$Root/Box.offset_bottom = 115.0


## items_lost = how many items went into the backpack, kinds_lost = how many different items.
func show_screen(seconds_survived: float, kills: int = 0, backpack_dropped: bool = false, items_lost: int = 0,
		kinds_lost: int = 0) -> void:
	var total: int = int(seconds_survived)
	time_label.text = "Time survived: %d:%02d" % [total / 60, total % 60]
	kills_label.text = "Zombies defeated: %d" % kills
	backpack_label.text = ("Left in your backpack: %d kind%s of item (%d in total).\nGo back for it." % [
		kinds_lost, "" if kinds_lost == 1 else "s", items_lost]) if backpack_dropped else "You weren't carrying anything."
	_daily_over = false
	_title.text = "YOU DIED"
	respawn_button.visible = true
	retry_button.text = "New game"
	rating.refresh()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	respawn_button.grab_focus()  # Enter / Space also press the button


## Batch 2: the daily challenge is one life. Shows the final score and today's best.
func show_daily(score: int, best_today: int, new_best: bool, nights: int) -> void:
	_daily_over = true
	_title.text = "DAILY RUN OVER"
	time_label.text = "%s  -  %s" % [GameState.daily_date, DailyChallenge.title(GameState.modifier)]
	kills_label.text = "Score %d   Nights survived %d" % [score, nights]
	backpack_label.text = "NEW BEST TODAY!" if new_best else "Today's best: %d" % best_today
	respawn_button.visible = false
	retry_button.text = "Try again"
	rating.refresh()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	retry_button.grab_focus()


func _on_respawn_pressed() -> void:
	visible = false
	respawn_requested.emit()


func _on_retry_pressed() -> void:
	retry_requested.emit()
	if _daily_over:
		DailyChallenge.begin(GameState.daily_date)
	else:
		GameState.new_game()
		SaveSystem.fresh_start = true   # replaces the save at once and gives the starting gear
	get_tree().reload_current_scene()
