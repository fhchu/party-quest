extends Resource
## Something the world checks each tick: to end a run (win or lose) or to
## clear a room. Only the field its type names is used.

const UnitType := preload("res://shared/data/unit_type.gd")

enum Type {
	## No unit of [member unit_type] is left in the room; with no unit type, no unit
	## at all.
	DEFEAT_ALL,
	## Every player is downed.
	PARTY_DOWNED,
	## [member sec] have passed since the world began.
	TIME_UP,
	## The room [member room] has been cleared.
	CLEAR_ROOM,
	## The party has entered the room. As a clear condition, the room is
	## cleared on the first step there.
	ENTERED,
	## A level has been chosen at the level select.
	LEVEL_SELECTED,
}

@export var type := Type.DEFEAT_ALL
## For DEFEAT_ALL; empty for every unit type.
@export var unit_type: UnitType
## For TIME_UP.
@export var sec := 0.0
## For CLEAR_ROOM: a room. Typed as Resource because room.gd refers to this
## script.
@export var room: Resource
