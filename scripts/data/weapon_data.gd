class_name WeaponData
extends Resource
## One weapon type. Adding a weapon = a new .tres in data/weapons/ (no code changes).
## Values come from GDD §6.

enum Kind { MELEE, HITSCAN }

@export var id: StringName = &"weapon"
@export var display_name: String = "Weapon"
@export var kind: Kind = Kind.MELEE
@export var icon: Texture2D

@export_group("Attack")
@export var damage: float = 25.0
## Minimum seconds between two attacks (pistol: 1 / 3 shots per second).
@export var cooldown: float = 0.6
## How long the player is committed (ATTACKING state) after attacking.
@export var attack_duration: float = 0.35
## Hold the button to keep attacking. Off = one attack per click (semi-automatic).
@export var automatic: bool = false
@export var range_px: float = 28.0
@export var knockback: float = 120.0
## Player movement while attacking, as a fraction of normal speed.
@export_range(0.0, 1.0) var move_speed_multiplier: float = 0.5
## Noise made by an attack. Used by the noise system from Phase 3.
@export var noise_radius: float = 90.0

@export_group("Melee")
@export var melee_arc_degrees: float = 100.0
## Delay between starting the swing and the hit landing.
@export var hit_delay: float = 0.12
## Chance of a long stun on hit (metal pipe), and how long it lasts.
@export_range(0.0, 1.0) var heavy_stun_chance: float = 0.0
@export var heavy_stun_time: float = 0.8

@export_group("Firearm")
@export var magazine_size: int = 0
@export var reload_time: float = 1.2
## Total width of the random spread cone, in degrees.
@export var spread_degrees: float = 4.0
@export var pellets: int = 1
@export var ammo_item_id: StringName = &""

@export_group("Sound")
## Firearms: gunshot. Melee: swing whoosh.
@export var attack_sound: AudioStream
@export var hit_sound: AudioStream


func is_melee() -> bool:
	return kind == Kind.MELEE


func uses_ammo() -> bool:
	return kind == Kind.HITSCAN and magazine_size > 0
