extends RefCounted
## Small room plans and goals for tests to build worlds from.

const DummyKinds := preload("res://tests/dummy_kinds.gd")
const Goal := preload("res://sim/goal.gd")
const RoomPlan := preload("res://sim/room_plan.gd")
const RunPlan := preload("res://sim/run_plan.gd")
const Levels := preload("res://shared/data/levels.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")
const Room := preload("res://shared/data/room.gd")
const RoomDummy := preload("res://shared/data/room_dummy.gd")

## Between the turrets [method levels] places, in px.
const TURRET_SPACING := 40.0


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


## Levels whose runs each start in a room of turrets, as many as
## [param turret_counts] says, so a test can tell which level started.
static func levels(turret_counts: Array[int]) -> Levels:
	var out := Levels.new()
	for count in turret_counts:
		var room := Room.new()
		for i in count:
			var dummy := RoomDummy.new()
			dummy.kind = DummyKinds.TURRET
			dummy.offset = Vector2(i * TURRET_SPACING, 0)
			room.dummies.append(dummy)
		var setup := RunSetup.new()
		setup.start = room
		out.runs.append(setup)
	return out
