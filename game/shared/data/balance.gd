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
## Centered on the player's position, unturned: what walls stop and what
## damage touches.
@export var player_hurtbox: Shape2D
## A player's health at the start of each world, and the most a heal gives
## back.
@export var player_max_health := 0
## After a player takes damage or an invulnerable heal, how long no damage
## can hurt them.
@export var player_invulnerable_sec := 0.0

@export_group("Rooms")
## Whether a room becoming cleared heals every player, downed ones
## included.
@export var clear_heal := false
## The health that heal gives each player.
@export var clear_heal_amount := 0
## Whether that heal also makes every player invulnerable.
@export var clear_heal_invulnerable := false

@export_group("Swing")
## How long a swing's arc is active. The player is rooted meanwhile.
@export var swing_active_sec := 0.0
## From the end of the arc to the next possible swing.
@export var swing_cooldown_sec := 0.0
## Whether a player stays rooted through the cooldown too.
@export var swing_root_during_cooldown := false
## From the player's center to where the swing starts, along their facing,
## in px.
@export var swing_offset := 0.0
## From where the swing starts to the end of its reach, in px.
@export var swing_radius := 0.0
## Width of the arc, centered on facing; up to a whole turn.
@export var swing_arc_deg := 0.0
## The arc sweeps from the player's left to their right in this many equal
## slices, each active for an equal share of the swing.
@export var swing_slices := 1
## A press this close to idle is remembered and fires when idle.
@export var swing_buffer_sec := 0.0
## Health a swing deals to a damageable dummy.
@export var swing_damage := 0

@export_group("Dummies")
## A dummy's target is the nearest living player, with distances rounded
## down to a multiple of this, in px, so near ties don't flip it back and
## forth.
@export var target_distance_step := 0.0
## A walking dummy steers away from any other whose edge is closer than
## this to its own, in px.
@export var personal_space := 0.0

@export_group("Run")
## How long a run's result shows over its frozen world.
@export var result_sec := 0.0


func arena() -> Rect2:
	return Rect2(Vector2.ZERO, arena_size)


## [member swing_arc_deg] in radians.
func swing_arc() -> float:
	return deg_to_rad(swing_arc_deg)
