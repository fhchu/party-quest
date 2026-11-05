extends RefCounted
## One room's rules about people: who holds which seat, and how long a
## dropped player's seat waits for them.
##
## No networking: server.gd maps connections onto seats and calls in. Every
## time-dependent call takes the current time, so tests run on their own
## clock.

## Connection state, per seat. SILENT: connected, no input yet or lately.
## AWAY: tab hidden, so input is ignored and no snapshots are sent.
## DROPPED: disconnected, seat held.
enum State {
	SILENT,
	ACTIVE,
	AWAY,
	DROPPED,
}

const World := preload("res://sim/world.gd")
const Protocol := preload("res://net/protocol.gd")

var world: World

## By session ID, which survives reconnects.
var _seats: Dictionary[String, Seat] = {}


func _init(load_dummies := false) -> void:
	world = World.new(1, load_dummies, World.Layout.LOBBY)


## Null if no seat has [param session_id].
func seat_of_session(session_id: String) -> Seat:
	return _seats.get(session_id)


## Null if [param peer_id] holds no seat. A DROPPED seat has no peer.
func seat_of_peer(peer_id: int) -> Seat:
	# At most MAX_PLAYERS seats: a search is simpler than a second index to
	# keep in sync.
	for seat: Seat in _seats.values():
		if seat.peer_id == peer_id:
			return seat
	return null


func seats() -> Array[Seat]:
	var out: Array[Seat] = []
	out.assign(_seats.values())
	return out


## Seats [param peer_id] as [param session_id]: back in their own seat if
## they hold one, else in the lowest free seat. Returns null when every seat
## is taken. The caller handles a seat that's still connected elsewhere.
func join(session_id: String, peer_id: int) -> Seat:
	var seat: Seat = _seats.get(session_id)
	if not seat:
		if _seats.size() >= Protocol.MAX_PLAYERS:
			return null
		seat = Seat.new()
		seat.player_id = _free_seat_number()
		world.add_player(seat.player_id)
		_seats[session_id] = seat
	seat.peer_id = peer_id
	seat.state = State.SILENT
	world.set_connected(seat.player_id, true)
	return seat


func drop(seat: Seat, now_msec: int) -> void:
	seat.state = State.DROPPED
	seat.peer_id = 0
	seat.since_msec = now_msec
	world.set_connected(seat.player_id, false)


func input(seat: Seat, move: Vector2, attack_count: int, now_msec: int) -> void:
	if seat.state != State.SILENT and seat.state != State.ACTIVE:
		return
	seat.state = State.ACTIVE
	seat.since_msec = now_msec
	# Longer than 1 would move faster than the player's speed.
	world.set_input(seat.player_id, move.limit_length(1.0), attack_count)


## An away player stays connected and just stands still.
func set_away(seat: Seat, away: bool) -> void:
	if seat.state == State.DROPPED or away == (seat.state == State.AWAY):
		return
	if away:
		seat.state = State.AWAY
		world.set_input(seat.player_id, Vector2.ZERO, 0)
	else:
		seat.state = State.SILENT


## One tick: input silence, seat holds, then the world.
func step(now_msec: int) -> void:
	for session_id: String in _seats.keys():
		_step_seat(session_id, now_msec)
	world.step()


func _step_seat(session_id: String, now_msec: int) -> void:
	var seat := _seats[session_id]
	var since := now_msec - seat.since_msec
	match seat.state:
		State.ACTIVE:
			# The client went quiet without disconnecting.
			if since > Protocol.INPUT_SILENCE_SEC * 1000:
				seat.state = State.SILENT
				world.set_input(seat.player_id, Vector2.ZERO, 0)
		State.DROPPED:
			if since > Protocol.RECONNECT_GRACE_SEC * 1000:
				_seats.erase(session_id)
				world.remove_player(seat.player_id)


## The lowest seat number nobody holds. A seat is freed only when its player
## is removed, so a reconnecting player always finds theirs waiting.
func _free_seat_number() -> int:
	var taken := _seats.values().map(func(s: Seat) -> int: return s.player_id)
	var n := 1
	while n in taken:
		n += 1
	return n


## Outlives its connection, so a reconnect gets the same seat back.
class Seat:
	## Also the seat number, 1 to MAX_PLAYERS. A player's color and spawn spot
	## go with it, like a controller port.
	var player_id: int
	## 0 while DROPPED: no Godot peer has ID 0.
	var peer_id := 0
	var state := State.SILENT
	## ACTIVE: the last input. DROPPED: the drop.
	var since_msec := 0
