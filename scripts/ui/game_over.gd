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


func _ready() -> void:
	visible = false
	for b in [retry_button, respawn_button, main_menu_button]:
		b.pressed.connect(func() -> void: AudioManager.play_ui())
	retry_button.pressed.connect(_on_retry_pressed)
	respawn_button.pressed.connect(_on_respawn_pressed)
	main_menu_button.pressed.connect(func() -> void: main_menu_requested.emit())


## items_lost = how many items went into the backpack, kinds_lost = how many different items.
func show_screen(seconds_survived: float, kills: int = 0, backpack_dropped: bool = false, items_lost: int = 0,
		kinds_lost: int = 0) -> void:
	var total: int = int(seconds_survived)
	time_label.text = "Time survived: %d:%02d" % [total / 60, total % 60]
	kills_label.text = "Zombies defeated: %d" % kills
	backpack_label.text = ("Left in your backpack: %d kind%s of item (%d in total).\nGo back for it." % [
		kinds_lost, "" if kinds_lost == 1 else "s", items_lost]) if backpack_dropped else "You weren't carrying anything."
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	respawn_button.grab_focus()  # Enter / Space also press the button


func _on_respawn_pressed() -> void:
	visible = false
	respawn_requested.emit()


func _on_retry_pressed() -> void:
	retry_requested.emit()
	GameState.new_game()
	get_tree().reload_current_scene()
