extends RefCounted
## Small maps and conditions for tests to build worlds from.

const Map := preload("res://shared/data/map.gd")
const MapDummy := preload("res://shared/data/map_dummy.gd")
const Condition := preload("res://shared/data/condition.gd")
const DummyKinds := preload("res://tests/dummy_kinds.gd")


static func condition(type: Condition.Type) -> Condition:
	var out := Condition.new()
	out.type = type
	return out


## Met once no enemy is left.
static func enemies_defeated() -> Condition:
	var out := condition(Condition.Type.DEFEAT_ALL)
	out.kind = DummyKinds.ENEMY
	return out


static func clear_room(room: Map) -> Condition:
	var out := condition(Condition.Type.CLEAR_ROOM)
	out.room = room
	return out


static func time_up(sec: float) -> Condition:
	var out := condition(Condition.Type.TIME_UP)
	out.sec = sec
	return out


## A map with one enemy at [param offset] that clears it when defeated;
## with [param guarded] false, an empty map that starts cleared.
static func map(guarded: bool, offset := Vector2.ZERO) -> Map:
	var out := Map.new()
	if guarded:
		var spot := MapDummy.new()
		spot.kind = DummyKinds.ENEMY
		spot.offset = offset
		out.dummies = [spot]
		out.clear_when = [enemies_defeated()]
	return out
