extends RefCounted
## Small rooms and conditions for tests to build worlds from.

const Room := preload("res://shared/data/room.gd")
const RoomDummy := preload("res://shared/data/room_dummy.gd")
const Condition := preload("res://shared/data/condition.gd")
const DummyKinds := preload("res://tests/dummy_kinds.gd")


static func condition(type: Condition.Type) -> Condition:
	var out := Condition.new()
	out.type = type
	return out


## Met once no enemy is left.
static func enemies_defeated() -> Condition:
	var out := condition(Condition.Type.DEFEAT_ALL)
	out.kind = DummyKinds.TURRET
	return out


static func clear_room(room: Room) -> Condition:
	var out := condition(Condition.Type.CLEAR_ROOM)
	out.room = room
	return out


static func time_up(sec: float) -> Condition:
	var out := condition(Condition.Type.TIME_UP)
	out.sec = sec
	return out


## A room with one enemy at [param offset] that clears it when defeated;
## with [param guarded] false, an empty room that starts cleared.
static func new_room(guarded: bool, offset := Vector2.ZERO) -> Room:
	var out := Room.new()
	if guarded:
		var spot := RoomDummy.new()
		spot.kind = DummyKinds.TURRET
		spot.offset = offset
		out.dummies = [spot]
		out.clear_when = [enemies_defeated()]
	return out
