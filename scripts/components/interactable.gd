class_name Interactable
extends Area2D
## "You can press E on this." Doors, loot containers, the stash, the bed, the radio...
## The player's Interactor finds the nearest Interactable in front of them and shows its prompt.
## Lives on physics layer 5 ("interactables"); it never collides with anything.

signal interacted(by: Node)

const LAYER: int = 16  # physics layer 5

## Text shown on the HUD, e.g. "Open door". The owner can supply a live text with prompt_provider.
@export var prompt: String = "Interact"

var prompt_provider: Callable


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


func get_prompt() -> String:
	return prompt_provider.call() if prompt_provider.is_valid() else prompt


func interact(by: Node) -> void:
	interacted.emit(by)
