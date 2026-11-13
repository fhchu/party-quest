extends Resource
## Something the world checks each tick: to end a run (win or lose) or to
## clear a room. Only the field its type names is used.

const DummyKind := preload("res://shared/data/dummy_kind.gd")

enum Type {
	## No dummy of [member kind] is left in the room.
	DEFEAT_ALL,
	## Every player is downed.
	PARTY_DOWNED,
	## [member sec] have passed since the world began.
	TIME_UP,
	## The room [member room] (a map) has been cleared.
	CLEAR_ROOM,
}

@export var type := Type.DEFEAT_ALL
## For DEFEAT_ALL.
@export var kind: DummyKind
## For TIME_UP.
@export var sec := 0.0
## For CLEAR_ROOM: a map. Typed as Resource because map.gd refers to this
## script.
@export var room: Resource
