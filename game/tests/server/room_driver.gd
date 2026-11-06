extends RefCounted
## A Room on a test clock, with shortcuts for the steps every room test takes.

const Room := preload("res://server/room.gd")
const Protocol := preload("res://net/protocol.gd")

## Milliseconds per tick on the test clock, rounded down.
@warning_ignore("integer_division")
const TICK_MSEC := 1000 / Protocol.TICK_RATE

## The test clock, in ms. Tests may move it forward between steps.
var now := 0
var room := Room.new()
var _next_peer := 100


## Joins as [param session] on a new peer. Null when the room is full.
func join(session: String) -> Room.Seat:
	_next_peer += 1
	return room.join(session, _next_peer)


func step(ticks := 1) -> void:
	for i in ticks:
		now += TICK_MSEC
		room.step(now)
