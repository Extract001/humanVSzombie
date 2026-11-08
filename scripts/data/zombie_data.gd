class_name ZombieData
extends Resource
## Tunable numbers for one zombie type (Walker, Runner, Brute...).
## Edit the .tres files in data/zombies/. Values come from GDD §7.

@export var id: StringName = &"walker"
@export var display_name: String = "Walker"

@export_group("Health")
@export var max_health: float = 60.0

@export_group("Speed (pixels per second)")
@export var wander_speed: float = 25.0
@export var investigate_speed: float = 35.0
@export var chase_speed: float = 45.0

@export_group("Attack")
@export var bite_damage: float = 12.0
## Centre-to-centre distance at which the zombie starts its bite.
@export var attack_range: float = 18.0
## Extra distance the bite still connects at when the wind-up ends (the lunge).
@export var lunge_tolerance: float = 6.0
## Visible telegraph before the bite lands.
@export var attack_windup: float = 0.4
## Minimum time between two bites.
@export var attack_cooldown: float = 1.2

@export_group("Senses")
@export var sight_range: float = 160.0
@export var sight_cone_degrees: float = 110.0
## Notices the player this close in any direction (bumping into it from behind).
@export var proximity_sense: float = 24.0
@export var search_duration: float = 6.0
## Sight range multiplier when the player is in a dark area with the flashlight off (GDD §7: ×0.5)...
@export var dark_sight_multiplier: float = 0.5
## ...and with the flashlight on in a dark area (GDD §8: the light gives you away, ×1.5).
@export var flashlight_sight_multiplier: float = 1.5
## Seconds between AI decisions. Movement still updates every physics frame.
@export var think_interval: float = 0.2

@export_group("Hearing & group alert")
## Multiplies every noise radius this zombie hears (1 = normal).
@export var hearing_multiplier: float = 1.0
## Radius of the groan made when it first spots the player. Nearby zombies come to investigate.
@export var alert_groan_radius: float = 140.0

@export_group("Wandering")
@export var wander_radius: float = 80.0
@export var idle_time_min: float = 2.0
@export var idle_time_max: float = 5.0
## Gives up on a wander target it can't reach after this long.
@export var wander_timeout: float = 6.0
## While searching, turns to look in a new direction this often.
@export var search_look_interval: float = 1.0

@export_group("Performance")
## Farther than this from the player (and not busy), the zombie thinks less often and doesn't wander.
@export var dormant_distance: float = 700.0
@export var dormant_think_interval: float = 1.0
## Minimum seconds between path recalculations while chasing.
@export var repath_interval: float = 0.25

@export_group("Hit reactions")
## Short stun on every hit (also interrupts a bite wind-up).
@export var hit_stun_time: float = 0.15
## Knockback slows to zero over this time.
@export var knockback_time: float = 0.25
## 0 = fully pushed by hits and shoves, 1 = immovable. 0.5+ also ignores shove stagger (Brute).
@export_range(0.0, 1.0) var shove_resistance: float = 0.0
