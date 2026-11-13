extends Resource
## Gameplay values that hold everywhere, in px and seconds: the classes that
## use a value copy it when they load, converting durations to ticks.
## Values that stop being global move to the resource they belong to.
##
## Every value is PLACEHOLDER (design).

## The arena from its top-left corner at (0, 0). At most the viewport's size
## (project.godot): the whole arena is always on screen, so there's no camera.
@export var arena_size := Vector2.ZERO
## The side of one square tile, in px. The arena is a whole number of tiles
## each way, and its walls are one tile thick.
@export var tile_size := 0.0
## How wide a door's gap in its wall is, in px: a whole number of tiles.
@export var door_width := 0.0

@export_group("Player")
## In px/s.
@export var player_speed := 0.0
## Centered on the player's position; used for walls and for being hit.
@export var player_hurtbox := Vector2.ZERO
## A player's health at the start of each world.
@export var player_max_health := 0
## After a player takes damage, how long no damage can hurt them.
@export var player_invulnerable_sec := 0.0

@export_group("Swing")
## How long a swing's arc is active. The player is rooted meanwhile.
@export var swing_active_sec := 0.0
## From the end of the arc to the next possible swing.
@export var swing_cooldown_sec := 0.0
## Whether a player stays rooted through the cooldown too.
@export var swing_root_during_cooldown := false
## In px.
@export var swing_radius := 0.0
## Width of the arc, centered on facing.
@export var swing_arc_deg := 0.0
## A press this close to idle is remembered and fires when idle.
@export var swing_buffer_sec := 0.0
## How far a hit pushes its target, in px, and over how long; 0 moves it at
## once.
@export var knockback_px := 0.0
@export var knockback_sec := 0.0
## Health a swing deals to a damageable dummy.
@export var swing_damage := 0

@export_group("Dummies")
## Every dummy's.
@export var dummy_hurtbox := Vector2.ZERO

@export_group("Run")
## How long a run's result shows over its frozen world.
@export var result_sec := 0.0


func arena() -> Rect2:
	return Rect2(Vector2.ZERO, arena_size)


## [member swing_arc_deg] in radians.
func swing_arc() -> float:
	return deg_to_rad(swing_arc_deg)
