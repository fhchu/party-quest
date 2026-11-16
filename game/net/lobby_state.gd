extends RefCounted
## The lobby as clients see it: its phase, the last outcome and who sits where.
## The server sends it reliably whenever any of it changes. Positions and the
## run timer go in snapshots instead.
## [codeblock]
## phase u8, outcome u8, all_ready u8, you u8, seat count u8
## seat: id u8, participation u8, connection u8
## [/codeblock]

## TOWN: walking around and readying up. RUN: the timer runs. RESULT: the
## outcome shows for a moment, then town comes back.
enum Phase {
	TOWN,
	RUN,
	RESULT,
}

## NONE outside RESULT. Running out of time is LOST.
enum Outcome {
	NONE,
	WON,
	LOST,
}

## How it takes part: playing, ready or not, or watching. SPECTATING:
## joined mid-run, so no character until town.
enum Participation {
	NOT_READY,
	READY,
	SPECTATING,
}

## HERE: connected, whether or not input is coming. AWAY: tab hidden.
## DROPPED: disconnected, seat held.
enum Connection {
	HERE,
	AWAY,
	DROPPED,
}

# Sizes in bytes, field by field as above.
const HEADER_SIZE := 1 + 1 + 1 + 1 + 1
const SEAT_SIZE := 1 + 1 + 1

## How many values a u8 field holds.
const BYTE_VALUES := 0x100

var phase := Phase.TOWN
var outcome := Outcome.NONE
## Whether every seat is ready, so a run may start. The server decides.
var all_ready := false
## The receiver's own seat number; 0 if not set. It can change in town,
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


func to_bytes() -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u8(phase)
	out.put_u8(outcome)
	out.put_u8(int(all_ready))
	out.put_u8(you)
	out.put_u8(seats.size())
	for s in seats:
		out.put_u8(s.id)
		out.put_u8(s.participation)
		out.put_u8(s.connection)
	return out.data_array


## Fills this from [param bytes]. Returns false, changing nothing, for bytes
## that don't hold a whole lobby state.
func read(bytes: PackedByteArray) -> bool:
	if bytes.size() < HEADER_SIZE:
		return false
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var new_phase := buf.get_u8()
	var new_outcome := buf.get_u8()
	var new_all_ready := buf.get_u8()
	var new_you := buf.get_u8()
	var count := buf.get_u8()
	if (bytes.size() != HEADER_SIZE + count * SEAT_SIZE
			or new_phase >= Phase.size() or new_outcome >= Outcome.size()
			or new_all_ready > 1):
		return false
	var new_seats: Array[Seat] = []
	# One field per line: the reads must happen in layout order.
	for i in count:
		var s := Seat.new()
		s.id = buf.get_u8()
		var participation := buf.get_u8()
		var connection := buf.get_u8()
		if participation >= Participation.size() or connection >= Connection.size():
			return false
		s.participation = participation as Participation
		s.connection = connection as Connection
		new_seats.append(s)
	phase = new_phase as Phase
	outcome = new_outcome as Outcome
	all_ready = new_all_ready == 1
	you = new_you
	seats = new_seats
	return true


class Seat:
	## The seat number, from 1; also the player ID in snapshots.
	var id := 0
	var participation := Participation.NOT_READY
	var connection := Connection.HERE
