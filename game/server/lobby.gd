extends "res://server/room_phase.gd"
## Walking around and readying up by hitting the READY dummy. Hitting START
## starts the match once everyone is ready. Only the lobby frees a dropped
## player's seat.

const Match := preload("res://server/match.gd")
const Protocol := preload("res://net/protocol.gd")


func fill_state(out: RoomState) -> void:
	out.phase = RoomState.Phase.LOBBY


func enter(room: Room, now_msec: int) -> void:
	for seat in room.seats():
		# PLACEHOLDER (design): ready resets when the lobby comes back.
		seat.standing = RoomState.Standing.NOT_READY
		# A seat held through the match gets the lobby's hold from now.
		if seat.state == Room.State.DROPPED:
			seat.since_msec = now_msec
	room.replace_world(World.Layout.LOBBY)


func step(room: Room, now_msec: int) -> void:
	for seat in room.seats():
		if (seat.state == Room.State.DROPPED
				and now_msec - seat.since_msec > Protocol.LOBBY_SEAT_HOLD_SEC * 1000):
			room.free_seat(seat)


func on_swing_contact(room: Room, contact: World.SwingContact, now_msec: int) -> void:
	var seat := room.seat_of_player(contact.attacker_id)
	if not seat:
		return
	match contact.dummy_kind:
		World.Kind.READY:
			set_ready(room, seat, seat.standing != RoomState.Standing.READY)
		World.Kind.START:
			start_match(room, now_msec)


func newcomer_standing() -> RoomState.Standing:
	return RoomState.Standing.NOT_READY


## Returns whether anything changed.
func set_ready(room: Room, seat: Room.Seat, ready: bool) -> bool:
	var standing := RoomState.Standing.READY if ready else RoomState.Standing.NOT_READY
	if seat.standing == standing:
		return false
	seat.standing = standing
	room.mark_room_state_unsent()
	return true


## Starts the match if [method RoomState.all_ready]. Returns whether it did.
func start_match(room: Room, now_msec: int) -> bool:
	if not room.state().all_ready():
		return false
	room.change_phase(Match.new(), now_msec)
	return true
