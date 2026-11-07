extends RefCounted
## The room as clients see it: its phase, the last outcome and who sits where.
## The server sends it reliably whenever any of it changes. Positions and the
## match timer go in snapshots instead.
## [codeblock]
## phase u8, outcome u8, you u8, seat count u8
## seat: id u8, readiness u8, presence u8
## [/codeblock]

## LOBBY: walking around and readying up. MATCH: the timer runs. RESULT: the
## outcome shows for a moment, then the lobby comes back.
enum Phase {
	LOBBY,
	MATCH,
	RESULT,
}

## NONE outside RESULT. Running out of time is LOST.
enum Outcome {
	NONE,
	WON,
	LOST,
}

## SPECTATING: joined mid-match, so no character until the lobby.
enum Readiness {
	NOT_READY,
	READY,
	SPECTATING,
}

## HERE: connected, whether or not input is coming. AWAY: tab hidden.
## DROPPED: disconnected, seat held.
enum Presence {
	HERE,
	AWAY,
	DROPPED,
}

# Sizes in bytes, field by field as above.
const HEADER_SIZE := 1 + 1 + 1 + 1
const SEAT_SIZE := 1 + 1 + 1

## How many values a u8 field holds.
const BYTE_VALUES := 0x100

var phase := Phase.LOBBY
var outcome := Outcome.NONE
## The receiver's own seat number; 0 if not set. It can change in the lobby,
## when an earlier seat is freed and everyone after it moves down.
var you := 0
## In seat order.
var seats: Array[Seat] = []


## Null if no seat has [param id].
func find_seat(id: int) -> Seat:
	for s in seats:
		if s.id == id:
			return s
	return null


## Whether every seat is ready, so a match may start. False with no seats.
## A drop clears ready, so a dropped seat holds up the start until its
## player is back or its hold frees it.
func all_ready() -> bool:
	return (not seats.is_empty()
			and seats.all(func(s: Seat) -> bool: return s.readiness == Readiness.READY))


func to_bytes() -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(phase)
	out.put_u8(outcome)
	out.put_u8(you)
	out.put_u8(seats.size())
	for s in seats:
		out.put_u8(s.id)
		out.put_u8(s.readiness)
		out.put_u8(s.presence)
	return out.data_array


## Fills this from [param bytes]. Returns false, changing nothing, for bytes
## that don't hold a whole room state.
func read(bytes: PackedByteArray) -> bool:
	if bytes.size() < HEADER_SIZE:
		return false
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var new_phase := buf.get_u8()
	var new_outcome := buf.get_u8()
	var new_you := buf.get_u8()
	var count := buf.get_u8()
	if (bytes.size() != HEADER_SIZE + count * SEAT_SIZE
			or new_phase >= Phase.size() or new_outcome >= Outcome.size()):
		return false
	var new_seats: Array[Seat] = []
	# One field per line: the reads must happen in layout order.
	for i in count:
		var s := Seat.new()
		s.id = buf.get_u8()
		var readiness := buf.get_u8()
		var presence := buf.get_u8()
		if readiness >= Readiness.size() or presence >= Presence.size():
			return false
		s.readiness = readiness as Readiness
		s.presence = presence as Presence
		new_seats.append(s)
	phase = new_phase as Phase
	outcome = new_outcome as Outcome
	you = new_you
	seats = new_seats
	return true


class Seat:
	## The seat number, 1 to MAX_PLAYERS; also the player ID in snapshots.
	var id := 0
	var readiness := Readiness.NOT_READY
	var presence := Presence.HERE
