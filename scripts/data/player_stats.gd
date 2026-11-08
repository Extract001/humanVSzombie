class_name PlayerStats
extends Resource
## All tunable player numbers. Edit data/player/player_stats.tres in the Inspector,
## not this script. Values come from GDD §5.

@export_group("Health")
@export var max_health: float = 100.0
@export var respawn_health: float = 75.0

@export_group("Movement (pixels per second)")
@export var walk_speed: float = 80.0
@export var run_speed: float = 140.0
@export var acceleration: float = 900.0
@export var friction: float = 1200.0

@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var run_drain_per_second: float = 20.0
@export var regen_per_second: float = 15.0
## Seconds without running (or shoving) before stamina starts to refill.
@export var regen_delay: float = 1.0
## Running can only START at or above this much stamina.
@export var min_stamina_to_run: float = 10.0

@export_group("Quick shove (GDD §5)")
@export var shove_stamina_cost: float = 15.0
@export var shove_cooldown: float = 1.0
@export var shove_range: float = 36.0
@export var shove_arc_degrees: float = 120.0
## Initial push speed; it slows to zero over shove_knockback_time (≈ 25 px of travel).
@export var shove_knockback_speed: float = 220.0
@export var shove_knockback_time: float = 0.25
## Zombies can't attack for this long after being shoved.
@export var shove_stagger_time: float = 0.6
@export var shove_damage: float = 2.0
@export var shove_noise_radius: float = 50.0
## The player's own shove animation time (SHOVING state).
@export var shove_duration: float = 0.25

@export_group("Noise & light (GDD §8)")
## Running makes noise this often (walking makes none).
@export var run_noise_radius: float = 120.0
@export var run_noise_interval: float = 0.4
## One battery lasts this long with the flashlight on (GDD: about 3 minutes).
@export var flashlight_battery_seconds: float = 180.0

@export_group("Combat states")
## A single hit at least this strong makes the player flinch (HURT). Walker bites (12) don't.
@export var heavy_hit_threshold: float = 25.0
@export var hurt_duration: float = 0.3
@export_range(0.0, 1.0) var reload_move_multiplier: float = 0.6
@export_range(0.0, 1.0) var shove_move_multiplier: float = 0.4
@export_range(0.0, 1.0) var hurt_move_multiplier: float = 0.3
