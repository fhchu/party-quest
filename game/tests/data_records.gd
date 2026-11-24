extends RefCounted
## Small room plans and goals for tests to build worlds from.

const DummyKinds := preload("res://tests/dummy_kinds.gd")
const Goal := preload("res://sim/goal.gd")
const RoomPlan := preload("res://sim/room_plan.gd")
const RunPlan := preload("res://sim/run_plan.gd")


static func goal(type: Goal.Type) -> Goal:
	var out := Goal.new()
	out.type = type
	return out


## Met once no enemy is left.
static func enemies_defeated() -> Goal:
	var out := goal(Goal.Type.DEFEAT_ALL)
	out.kind = DummyKinds.turret_kind
	return out


static func clear_room(room: RoomPlan) -> Goal:
	var out := goal(Goal.Type.CLEAR_ROOM)
	out.room = room
	return out


static func time_up(sec: float) -> Goal:
	var out := goal(Goal.Type.TIME_UP)
	out.ticks = GameTime.ticks(sec)
	return out


## A room with one enemy at [param offset] that clears it when defeated;
## with [param guarded] false, an empty room that starts cleared.
static func new_room(guarded: bool, offset := Vector2.ZERO) -> RoomPlan:
	var out := RoomPlan.new()
	if guarded:
		var spot := RoomPlan.Spot.new()
		spot.kind = DummyKinds.turret_kind
		spot.offset = offset
		out.spots = [spot]
		out.clear_goals = [enemies_defeated()]
	return out


static func run(start: RoomPlan, win: Array[Goal] = [], lose: Array[Goal] = []) -> RunPlan:
	var out := RunPlan.new()
	out.start = start
	if start:
		out.rooms = [start]
	out.win = win
	out.lose = lose
	return out
