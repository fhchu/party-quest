extends RefCounted
## The lobby as clients see it: its phase, the last outcome, who sits where
## and what each seat owns.
## The server sends it reliably whenever any of it changes. Positions and the
## run timer go in snapshots instead.
## [codeblock]
## phase u8, outcome u8, all_ready u8, you u8, level_select_open u8,
## cursor u8, seat count u8
## seat: id u8, participation u8, connection u8,
##       slot count u8, slot item u8 × slot count,
##       inventory count u8, (item u8, quantity u32) × inventory count
## [/codeblock]
## An item is its number in shared/data/items.tres.

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

## How it participates: playing, ready or not, or watching. SPECTATING:
## joined mid-run, so no character until town.
enum Participation {
	NOT_READY,
	READY,
	SPECTATING,
}

## HERE: connected, whether or not input is coming or the tab is shown.
## DROPPED: disconnected, seat held.
enum Connection {
	HERE,
	DROPPED,
}

# Sizes in bytes, field by field as above.
const HEADER_SIZE := 1 + 1 + 1 + 1 + 1 + 1 + 1
## A seat up to its slot items.
const SEAT_START_SIZE := 1 + 1 + 1 + 1
const SLOT_SIZE := 1
const INVENTORY_COUNT_SIZE := 1
const INVENTORY_ENTRY_SIZE := 1 + 4

## How many values a u8 field holds.
const BYTE_VALUES := 0x100
## In [member Seat.slot_items], a slot with no item in it. The highest u8,
## so no item's number can be it.
const NO_ITEM := BYTE_VALUES - 1

var phase := Phase.TOWN
var outcome := Outcome.NONE
## Whether every seat is ready, so a run may start. The server decides.
var all_ready := false
## The receiver's own seat number; 0 if not set. It can change in town,
## when an earlier seat is freed and everyone after it moves down.
var you := 0
## Whether town shows the level select.
var level_select_open := false
## The level the level select's cursor points at, from 0.
var cursor := 0
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
	out.put_u8(int(level_select_open))
	out.put_u8(cursor)
	out.put_u8(seats.size())
	for s in seats:
		out.put_u8(s.id)
		out.put_u8(s.participation)
		out.put_u8(s.connection)
		out.put_u8(s.slot_items.size())
		for item in s.slot_items:
			out.put_u8(item)
		out.put_u8(s.inventory.size())
		for item in s.inventory:
			out.put_u8(item)
			out.put_u32(s.inventory[item])
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
	var new_level_select_open := buf.get_u8()
	var new_cursor := buf.get_u8()
	var count := buf.get_u8()
	if (new_phase >= Phase.size() or new_outcome >= Outcome.size() or new_all_ready > 1
			or new_level_select_open > 1):
		return false
	var new_seats: Array[Seat] = []
	for i in count:
		var s := _read_seat(buf)
		if not s:
			return false
		new_seats.append(s)
	if buf.get_available_bytes() != 0:
		return false
	phase = new_phase as Phase
	outcome = new_outcome as Outcome
	all_ready = new_all_ready == 1
	you = new_you
	level_select_open = new_level_select_open == 1
	cursor = new_cursor
	seats = new_seats
	return true


## The next seat in [param buf], or null if what's there isn't a whole,
## valid seat.
static func _read_seat(buf: StreamPeerBuffer) -> Seat:
	if buf.get_available_bytes() < SEAT_START_SIZE:
		return null
	# One field per line: the reads must happen in layout order.
	var s := Seat.new()
	s.id = buf.get_u8()
	var participation := buf.get_u8()
	var connection := buf.get_u8()
	if participation >= Participation.size() or connection >= Connection.size():
		return null
	s.participation = participation as Participation
	s.connection = connection as Connection
	var slot_count := buf.get_u8()
	if buf.get_available_bytes() < slot_count * SLOT_SIZE + INVENTORY_COUNT_SIZE:
		return null
	for i in slot_count:
		s.slot_items.append(buf.get_u8())
	var inventory_count := buf.get_u8()
	if buf.get_available_bytes() < inventory_count * INVENTORY_ENTRY_SIZE:
		return null
	for i in inventory_count:
		var item := buf.get_u8()
		s.inventory[item] = buf.get_u32()
	return s


class Seat:
	## The seat number, from 1; also the player ID in snapshots.
	var id := 0
	var participation := Participation.NOT_READY
	var connection := Connection.HERE
	## Its holder's items, each by number, to how many they own.
	var inventory: Dictionary[int, int] = {}
	## The item in each of its holder's slots, or [constant NO_ITEM]: the
	## first is used by the use_item_1 action, the second by use_item_2.
	var slot_items := PackedInt32Array()
