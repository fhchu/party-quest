extends RefCounted
## A room as the data lays it out, made by WorldLoader for one run. The
## world builds a room's state from it the first time the party enters.
## Doors name rooms by number, so plans never point at each other and are
## freed with their run.

const Goal := preload("res://sim/goal.gd")
const WallPlan := preload("res://sim/wall_plan.gd")

## Where the first player starts when a world starts in this room, in arena
## px.
var spawn := Vector2.ZERO
## Which way the party faces then.
var spawn_facing := Direction.Cardinal.SOUTH
var spots: Array[Spot] = []
## The room is cleared once any of these is met; with none, it starts
## cleared.
var clear_goals: Array[Goal] = []
var doors: Array[DoorPlan] = []


## One unit the room places.
class Spot:
	## Its unit type's number.
	var unit_type := 0
	## From the arena's center, in px.
	var offset := Vector2.ZERO
	## What a swing touching it asks the lobby to do; empty for nothing.
	var on_hit := ""


## One way out of the room.
class DoorPlan:
	## [member leads_to] for a door that opens the level select instead of
	## leading to a room.
	const LEVEL_SELECT := -1

	## The wall it's in.
	var wall: WallPlan
	## The room it leads to: its number in its run's rooms, or
	## [constant LEVEL_SELECT].
	var leads_to := 0
	## The wall the party comes in by, in the room it leads to.
	var arrive_by: WallPlan

	## Whether going through it opens the level select instead of moving the
	## party.
	func opens_level_select() -> bool:
		return leads_to == LEVEL_SELECT
