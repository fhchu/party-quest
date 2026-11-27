extends RefCounted
## Something the world checks each tick: to end a run (win or lose) or to
## clear a room. WorldLoader makes one from each condition in the data,
## its seconds in ticks. Only the field its type names is used.

## The sim's copy of the data's condition types; WorldLoader.GOAL_TYPES
## maps one to the other.
enum Type {
	## No unit of [member unit_type] is left in the room.
	DEFEAT_ALL,
	## Every player is downed.
	PARTY_DOWNED,
	## [member ticks] have passed since the world began.
	TIME_UP,
	## The room [member room] has been cleared.
	CLEAR_ROOM,
	## The party has entered the room. As a clear goal, the room is cleared
	## on the first step there.
	ENTERED,
	## A level has been chosen at the level select.
	LEVEL_SELECTED,
}

## For [constant DEFEAT_ALL] with every unit type.
const EVERY_UNIT := -1

var type := Type.DEFEAT_ALL
## For DEFEAT_ALL: a unit type's number, or [constant EVERY_UNIT].
var unit_type := EVERY_UNIT
## For TIME_UP.
var ticks := 0
## For CLEAR_ROOM: a room plan. Typed as RefCounted because room_plan.gd
## refers to this script.
var room: RefCounted
