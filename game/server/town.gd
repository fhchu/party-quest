extends "res://server/room_phase.gd"
## Walking around and readying up by hitting the READY dummy. Hitting START
## starts the match once everyone is ready. Only town frees a dropped
## player's seat.

const Match := preload("res://server/match.gd")


func fill_state(out: RoomState) -> void:
	out.phase = RoomState.Phase.TOWN


func enter(room: Room, now_msec: int) -> void:
	for seat in room.seats():
		# PLACEHOLDER (design): ready resets when town comes back.
		seat.readiness = RoomState.Readiness.NOT_READY
	room.replace_world(World.Layout.TOWN)


## A match holds a dropped seat for its player's return; town lets it go
## at once, and frees the seats a match held as soon as it comes back.
func step(room: Room, _now_msec: int) -> void:
	for seat in room.seats():
		if seat.state == Room.State.DROPPED:
			room.free_seat(seat)


func on_swing_contact(room: Room, contact: World.SwingContact, now_msec: int) -> void:
	var seat := room.seat_of_player(contact.attacker_id)
	if not seat:
		return
	match contact.on_hit:
		World.OnHit.TOGGLE_READY:
			set_ready(room, seat, seat.readiness != RoomState.Readiness.READY)
		World.OnHit.START_MATCH:
			start_match(room, now_msec)


func newcomer_readiness() -> RoomState.Readiness:
	return RoomState.Readiness.NOT_READY


## Returns whether anything changed.
func set_ready(room: Room, seat: Room.Seat, ready: bool) -> bool:
	var readiness := RoomState.Readiness.READY if ready else RoomState.Readiness.NOT_READY
	if seat.readiness == readiness:
		return false
	seat.readiness = readiness
	room.mark_room_state_unsent()
	return true


## Starts the match if [method RoomState.all_ready]. Returns whether it did.
func start_match(room: Room, now_msec: int) -> bool:
	if not room.state().all_ready():
		return false
	room.change_phase(Match.new(), now_msec)
	return true
