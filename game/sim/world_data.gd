extends RefCounted
## The gameplay values every world plays by, loaded once from shared/ through
## WorldLoader. Nothing changes them while the game runs; a test swaps in its
## own with [member World.data].

const WorldLoader := preload("res://sim/world_loader.gd")

## The arena, from its top-left corner, in px.
var arena := WorldLoader.arena
## The side of one square tile, in px: how finely dummies find their way.
var tile_size := WorldLoader.tile_size
## Inside the walls, in px.
var floor_area := WorldLoader.floor_area
## The four walls every room has.
var walls := WorldLoader.walls
## Centered on the player's position; used for walls and for being hit.
var player_hurtbox := WorldLoader.player_hurtbox
## A player's health at the start of each world.
var player_max_health := WorldLoader.player_max_health
## How far a player walks each tick, in px.
var walk_step := WorldLoader.walk_step
## How long a swing's arc is active. The player is rooted meanwhile.
var swing_ticks := WorldLoader.swing_ticks
## A press this close to idle is remembered and fires when idle.
var swing_buffer_ticks := WorldLoader.swing_buffer_ticks
## After a player takes damage or an invulnerable heal, how long no damage
## can hurt them.
var invulnerable_duration_ticks := WorldLoader.invulnerable_duration_ticks
# PLACEHOLDER (design): the clear heal's values.
## Whether a room becoming cleared heals every player, downed ones included.
var clear_heal := true
## The health that heal gives each player.
var clear_heal_amount := 1
## Whether that heal also makes every player invulnerable.
var clear_heal_invulnerable := true
## From the player's center to where the swing starts, in px.
var swing_offset := WorldLoader.swing_offset
## From where the swing starts to the end of its reach, in px.
var swing_radius := WorldLoader.swing_radius
## Width of the arc in radians, centered on facing.
var swing_arc := WorldLoader.swing_arc
var swing_slices := WorldLoader.swing_slices
## The swing's active slice, pointing along +x, as convex pieces.
var swing_pieces := WorldLoader.swing_pieces(swing_radius, swing_arc, swing_slices)
## How far the active slice is turned from the facing, on each tick of the
## swing from its first.
var swing_turns := WorldLoader.swing_turns(swing_arc, swing_slices, swing_ticks)
## How long a run's result shows over its frozen world.
var result_ticks := WorldLoader.result_ticks
## How far a swing pushes what it hits, in px, and over how long.
var knockback_px := WorldLoader.knockback_px
var knockback_ticks := WorldLoader.knockback_ticks
# PLACEHOLDER (design): the swing's damage and the dummies' distances.
## Health a swing deals to a damageable dummy.
var swing_damage := 1
## Dummies pick the nearest living player by distance rounded down to
## this, in px, so near ties don't flip it back and forth.
var target_distance_step := 16.0
## A walking dummy steers away from any other whose edge is closer than
## this to its own, in px.
var personal_space := 8.0
