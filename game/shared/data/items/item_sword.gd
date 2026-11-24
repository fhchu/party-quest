extends "res://shared/data/items/equip_item.gd"
## A sword's swing, in px and seconds: an arc in front of the player.

## How long the arc is active. The player is rooted meanwhile.
@export var swing_active_sec := 0.0
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


## [member swing_arc_deg] in radians.
func swing_arc() -> float:
	return deg_to_rad(swing_arc_deg)
