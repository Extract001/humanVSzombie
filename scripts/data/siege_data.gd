class_name SiegeData
extends Resource
## Day/night cycle and night siege numbers (Slice 1 of the "night siege" design, GDD §16).
## Edit data/siege/siege_data.tres. Times are real seconds.

@export_group("Cycle")
## Daylight: scavenge. The clock runs 06:00 → 18:00 during this time.
@export var day_length: float = 300.0
## Dusk: get home and board up. 18:00 → 20:00. The horde starts moving at the end.
@export var dusk_length: float = 45.0
## Night: the siege. 20:00 → 05:00. Survive until dawn.
@export var night_length: float = 150.0
## The ending (evacuation) needs the radio repaired and this many nights survived.
@export var nights_to_win: int = 10

@export_group("Horde")
## Walkers per night = base + per_night × night number + heat × per_heat (then capped).
@export var horde_base: int = 4
@export var horde_per_night: float = 1.5
@export var horde_per_heat: float = 0.75
## Never more than this many Walkers awake at once (performance target: 40 on screen-adjacent areas).
@export var max_zombies_total: int = 40
## Horde Walkers arrive during this share of the night (0.6 = the first 60%).
@export var arrival_share: float = 0.6

@export_group("Heat (the town listens)")
## Only loud noises raise Heat: a noise of at least this radius (px)...
@export var heat_min_radius: float = 200.0
## ...adds radius / this. A pistol shot (480 px) = +1 Heat (= 0.75 more Walkers tonight), cutting a lock (260 px) = +0.5.
@export var heat_radius_per_point: float = 480.0

@export_group("Barricades")
@export var max_planks: int = 3
@export var plank_health: float = 30.0
## A plank costs this many scrap and takes this long to nail up.
@export var plank_cost: int = 1
@export var plank_build_time: float = 1.2
## Hammering is a noise (inside your own house, mostly muffled by the walls).
@export var plank_noise_radius: float = 70.0
## Damage a Walker does to a barricade per hit (one hit every attack_interval).
@export var zombie_barricade_damage: float = 10.0
@export var zombie_barricade_interval: float = 1.5
## Planks each window starts a new game with.
@export var start_planks: int = 2

@export_group("Dawn")
## Emptied town containers that get new loot each morning (never quest containers).
@export var restock_per_dawn: int = 5

@export_group("Night look")
@export var dusk_tint: Color = Color(0.95, 0.72, 0.6)
@export var night_tint: Color = Color(0.3, 0.33, 0.5)
