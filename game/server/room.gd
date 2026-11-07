extends RefCounted
## One room's rules about people: who holds which seat, seat holds, and
## which phase the room is in. Each phase's own rules live in its object
## (see [code]room_phase.gd[/code]).
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
const RoomState := preload("res://net/room_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const RoomPhase := preload("res://server/room_phase.gd")
const Lobby := preload("res://server/lobby.gd")

## A [code]lobby.gd[/code], [code]match.gd[/code] or [code]result.gd[/code].
## Changed only by [method change_phase].
var phase: RoomPhase = Lobby.new()
## Replaced by a fresh one when a phase calls [method replace_world].
var world: World
## Which world this is, counting up from 0 and wrapping at a byte, so
## clients can tell a fresh world's snapshots from the last one's.
var world_number := 0

## By session ID, which survives reconnects.
var _seats: Dictionary[String, Seat] = {}
## Whether clients' copies of [method state] are out of date, or a newcomer
## has none yet.
var _room_state_unsent := true
## The last time anyone held a seat, or when the room was made.
var _last_seated_msec := 0


func _init(now_msec: int) -> void:
	_last_seated_msec = now_msec
	world = World.new(World.Layout.LOBBY)


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
## they hold one, else in the lowest free seat. A newcomer is a player in
## the lobby and a spectator otherwise. Returns null when every seat is
## taken. The caller handles a seat that's still connected elsewhere.
func join(session_id: String, peer_id: int) -> Seat:
	var seat: Seat = _seats.get(session_id)
	if not seat:
		if _seats.size() >= Protocol.MAX_PLAYERS:
			return null
		seat = Seat.new()
		seat.player_id = _free_seat_number()
		seat.standing = phase.newcomer_standing()
		if seat.standing != RoomState.Standing.SPECTATING:
			world.add_player(seat.player_id)
		_seats[session_id] = seat
	seat.peer_id = peer_id
	seat.state = State.SILENT
	world.set_connected(seat.player_id, true)
	_room_state_unsent = true
	return seat


## A disconnected player can't be ready, so a drop clears it.
func drop(seat: Seat, now_msec: int) -> void:
	seat.state = State.DROPPED
	seat.peer_id = 0
	seat.since_msec = now_msec
	if seat.standing == RoomState.Standing.READY:
		seat.standing = RoomState.Standing.NOT_READY
	world.set_connected(seat.player_id, false)
	_room_state_unsent = true


func input(seat: Seat, move: Vector2, attack_count: int, now_msec: int) -> void:
	if seat.state != State.SILENT and seat.state != State.ACTIVE:
		return
	seat.state = State.ACTIVE
	seat.since_msec = now_msec
	phase.on_input(self, seat, move, attack_count)


## An away player stays connected and just stands still.
func set_away(seat: Seat, away: bool) -> void:
	if seat.state == State.DROPPED or away == (seat.state == State.AWAY):
		return
	if away:
		seat.state = State.AWAY
		world.set_input(seat.player_id, Vector2.ZERO, 0)
	else:
		seat.state = State.SILENT
	_room_state_unsent = true


## One tick: input silence, the world, then the phase, which hears what
## the world's swings touched first.
func step(now_msec: int) -> void:
	# Before the phase can free seats, so the empty wait starts when the last
	# one is freed.
	if not _seats.is_empty():
		_last_seated_msec = now_msec
	for seat: Seat in _seats.values():
		_step_seat(seat, now_msec)

	world.step()
	for contact in world.swing_contacts:
		# A contact that changes the phase sends the rest to the new phase.
		phase.on_swing_contact(self, contact, now_msec)
	phase.step(self, now_msec)


## Whether nobody has held a seat for [constant Protocol.EMPTY_EXIT_SEC].
func is_abandoned(now_msec: int) -> bool:
	return (_seats.is_empty()
			and now_msec - _last_seated_msec > Protocol.EMPTY_EXIT_SEC * 1000)


## Whether clients need [method state] sent: it changed, or someone joined.
func is_room_state_unsent() -> bool:
	return _room_state_unsent


## Called once every connected seat has been sent its [method state].
func mark_room_state_sent() -> void:
	_room_state_unsent = false


## For phases, after they change something [method state] reports.
func mark_room_state_unsent() -> void:
	_room_state_unsent = true


## [param you] is the seat it's for, so its holder learns their number.
func state(you: Seat = null) -> RoomState:
	var out := RoomState.new()
	phase.fill_state(out)
	out.you = you.player_id if you else 0
	var sorted := seats()
	sorted.sort_custom(func(a: Seat, b: Seat) -> bool: return a.player_id < b.player_id)
	for seat in sorted:
		var s := RoomState.Seat.new()
		s.id = seat.player_id
		s.standing = seat.standing
		match seat.state:
			State.AWAY:
				s.presence = RoomState.Presence.AWAY
			State.DROPPED:
				s.presence = RoomState.Presence.DROPPED
		out.seats.append(s)
	return out


func snapshot() -> Snapshot:
	var snap := world.snapshot()
	snap.world_number = world_number
	phase.fill_snapshot(snap)
	return snap


func change_phase(next: RoomPhase, now_msec: int) -> void:
	phase = next
	phase.enter(self, now_msec)
	_room_state_unsent = true


## Null if no seat has [param player_id].
func seat_of_player(player_id: int) -> Seat:
	for seat: Seat in _seats.values():
		if seat.player_id == player_id:
			return seat
	return null


## Frees [param seat] for someone else; the seats after it move down.
func free_seat(seat: Seat) -> void:
	_seats.erase(_seats.find_key(seat))
	world.remove_player(seat.player_id)
	_close_gaps()
	_room_state_unsent = true


## A fresh world with a character for every seat that isn't spectating. The
## old world, with its dummies, is dropped.
func replace_world(layout: World.Layout) -> void:
	var fresh := World.new(layout)
	# Clients drop snapshots whose tick goes backwards.
	fresh.tick = world.tick
	world_number = (world_number + 1) % RoomState.BYTE_VALUES
	for seat: Seat in _seats.values():
		if seat.standing == RoomState.Standing.SPECTATING:
			continue
		fresh.add_player(seat.player_id)
		fresh.set_connected(seat.player_id, seat.state != State.DROPPED)
		# The client keeps counting presses across worlds; without this the
		# press that hit START would swing again in the match.
		var old: World.Player = world.players.get(seat.player_id)
		if old:
			fresh.discard_attacks(seat.player_id, old.attack_count)
	world = fresh


func _step_seat(seat: Seat, now_msec: int) -> void:
	# The client went quiet without disconnecting.
	if (seat.state == State.ACTIVE
			and now_msec - seat.since_msec > Protocol.INPUT_SILENCE_SEC * 1000):
		seat.state = State.SILENT
		world.set_input(seat.player_id, Vector2.ZERO, 0)


## Moves everyone after a freed seat down one (2 to 1, 3 to 2 ...), so the
## lobby's seats are always 1 to n. Only the lobby frees seats.
## PLACEHOLDER (design): characters keep their place; color and the next
## spawn spot follow the new number.
func _close_gaps() -> void:
	var sorted := seats()
	sorted.sort_custom(func(a: Seat, b: Seat) -> bool: return a.player_id < b.player_id)
	# In ascending order each new number is already free: it was the freed
	# seat's, or the one just moved down from it.
	for i in sorted.size():
		var seat := sorted[i]
		var number := i + 1
		if seat.player_id != number:
			world.renumber_player(seat.player_id, number)
			seat.player_id = number


## The lowest seat number nobody holds. Seats are numbered 1 to n with no
## gaps (see [method _close_gaps]), so it's the next one up; a held seat
## keeps its number, so a reconnecting player finds theirs waiting.
func _free_seat_number() -> int:
	var taken := _seats.values().map(func(s: Seat) -> int: return s.player_id)
	var n := 1
	while n in taken:
		n += 1
	return n


## Outlives its connection, so a reconnect gets the same seat back.
class Seat:
	## Also the seat number, 1 to MAX_PLAYERS. A player's color and spawn spot
	## go with it, like a controller port. Lowered when an earlier lobby seat
	## is freed.
	var player_id: int
	## 0 while DROPPED: no Godot peer has ID 0.
	var peer_id := 0
	var state := State.SILENT
	## ACTIVE: the last input. DROPPED: the drop, or the lobby's return.
	var since_msec := 0
	## A drop clears READY. A seat that joins mid-match spectates, with no
	## character, until the lobby.
	var standing := RoomState.Standing.NOT_READY
