extends Resource
## Something the world checks each tick: to end a run (win or lose) or to
## clear a room. Only the field its type names is used.

const DummyKind := preload("res://shared/data/dummy_kind.gd")

enum Type {
	## No dummy of [member kind] is left in the room; with no kind, no dummy
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
}

@export var type := Type.DEFEAT_ALL
## For DEFEAT_ALL; empty for every kind.
@export var kind: DummyKind
## For TIME_UP.
@export var sec := 0.0
## For CLEAR_ROOM: a room. Typed as Resource because room.gd refers to this
## script.
@export var room: Resource
