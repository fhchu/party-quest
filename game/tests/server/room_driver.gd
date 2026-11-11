extends RefCounted
## A Room on a test clock, with shortcuts for the steps every room test takes.

const Room := preload("res://server/room.gd")
const RoomState := preload("res://net/room_state.gd")
const Protocol := preload("res://net/protocol.gd")
const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")
const Town := preload("res://server/town.gd")
const Match := preload("res://server/match.gd")

## Milliseconds per tick on the test clock, rounded down.
@warning_ignore("integer_division")
const TICK_MSEC := 1000 / Protocol.TICK_RATE

## The test clock, in ms. Tests may move it forward between steps.
var now := 0
var room := Room.new(now)
var _next_peer := 100


## Joins as [param session] on a new peer. Null when the room is full.
func join(session: String) -> Room.Seat:
	_next_peer += 1
	return room.join(session, _next_peer)


func step(ticks := 1) -> void:
	for i in ticks:
		now += TICK_MSEC
		room.step(now)


## The room's town phase; fails the test outside one.
func town() -> Town:
	return room.phase as Town


## The room's match; fails the test outside one.
func running_match() -> Match:
	return room.phase as Match


func set_ready(seat: Room.Seat, ready: bool) -> bool:
	return town().set_ready(room, seat, ready)


func start_match() -> bool:
	return town().start_match(room, now)


func end_match(outcome: RoomState.Outcome) -> void:
	running_match().end_match(room, outcome, now)


## Seats [param sessions], readies them all and starts the match. Empty if
## it didn't start.
func start_with(sessions: Array[String]) -> Array[Room.Seat]:
	var seats: Array[Room.Seat] = []
	for s in sessions:
		seats.append(join(s))
	for seat in seats:
		set_ready(seat, true)
	if not start_match():
		seats.clear()
	return seats


## Puts [param seat]'s character just left of the first dummy of [param kind],
## facing it, swings once and steps until the swing is over. False if
## there's no such dummy.
func swing_at(seat: Room.Seat, kind: World.Kind) -> bool:
	var target: World.Dummy = null
	for dummy in room.world.dummies:
		if dummy.kind == kind:
			target = dummy
			break
	var p: World.Player = room.world.players.get(seat.player_id)
	if not target or not p:
		return false
	p.pos = target.pos - Vector2(Tuning.swing_radius / 2, 0)
	p.facing = Vector2.RIGHT
	room.input(seat, Vector2.ZERO, p.attack_count + 1, now)
	step(Tuning.swing_ticks + 1)
	return true


## Plays the result out, so town comes back.
func finish_result() -> void:
	step(Tuning.result_ticks)
