extends RefCounted
## One room's rules about people: who holds which seat, ready, spectators,
## the match timer, seat holds and the phases LOBBY, MATCH and RESULT.
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
const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")
const RoomState := preload("res://net/room_state.gd")
const Snapshot := preload("res://net/snapshot.gd")

var phase := RoomState.Phase.LOBBY
## Of the match just played; NONE outside RESULT.
var outcome := RoomState.Outcome.NONE
## Replaced by a fresh one at each phase change, so everyone starts at their
## spawn spot.
var world: World
## Counts down during a match; 0 outside one.
var match_ticks_left := 0
## Which world this is, counting up from 0 and wrapping at a byte, so
## clients can tell a fresh world's snapshots from the last one's.
var world_number := 0

var _result_ticks_left := 0
## By session ID, which survives reconnects.
var _seats: Dictionary[String, Seat] = {}
## Set by anything that changes what [method state] reports.
var _changed := true
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
		seat.spectating = phase != RoomState.Phase.LOBBY
		if not seat.spectating:
			world.add_player(seat.player_id)
		_seats[session_id] = seat
	seat.peer_id = peer_id
	seat.state = State.SILENT
	world.set_connected(seat.player_id, true)
	_changed = true
	return seat


## A disconnected player can't be ready, so a drop clears it.
func drop(seat: Seat, now_msec: int) -> void:
	seat.state = State.DROPPED
	seat.peer_id = 0
	seat.since_msec = now_msec
	seat.ready = false
	world.set_connected(seat.player_id, false)
	_changed = true


func input(seat: Seat, move: Vector2, attack_count: int, now_msec: int) -> void:
	if seat.state != State.SILENT and seat.state != State.ACTIVE:
		return
	seat.state = State.ACTIVE
	seat.since_msec = now_msec
	if phase == RoomState.Phase.RESULT:
		# Presses now are spent, so none swings once the lobby comes back.
		world.absorb_attacks(seat.player_id, attack_count)
		return
	# Longer than 1 would move faster than the player's speed. A spectator
	# has no character, so the world ignores it.
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
	_changed = true


## Only in the lobby. Returns whether anything changed.
func set_ready(seat: Seat, ready: bool) -> bool:
	if phase != RoomState.Phase.LOBBY or seat.spectating or seat.ready == ready:
		return false
	seat.ready = ready
	_changed = true
	return true


## Any seat may start the match once every connected seat is ready (see
## [method RoomState.all_ready]). Returns whether it started.
func start_match(seat: Seat) -> bool:
	if phase != RoomState.Phase.LOBBY or seat.spectating or not state().all_ready():
		return false
	_new_world(World.Layout.MATCH)
	phase = RoomState.Phase.MATCH
	match_ticks_left = Tuning.match_ticks
	_changed = true
	return true


## Ends a match in progress with [param result]; ignored outside one.
func end_match(result: RoomState.Outcome) -> void:
	if phase != RoomState.Phase.MATCH:
		return
	phase = RoomState.Phase.RESULT
	outcome = result
	match_ticks_left = 0
	_result_ticks_left = Tuning.result_ticks
	# Everyone stands while the outcome shows.
	for seat: Seat in _seats.values():
		world.set_input(seat.player_id, Vector2.ZERO, 0)
	_changed = true


## One tick: input silence, seat holds, the world and what its swings hit,
## then the phase timers.
func step(now_msec: int) -> void:
	# Before the holds below, so the empty wait starts when the last one ends.
	if not _seats.is_empty():
		_last_seated_msec = now_msec
	for session_id: String in _seats.keys():
		_step_seat(session_id, now_msec)

	world.step()
	for contact in world.swing_contacts:
		_on_swing_contact(contact)
	match phase:
		RoomState.Phase.MATCH:
			match_ticks_left -= 1
			if world.enemies_left() == 0:
				end_match(RoomState.Outcome.WON)
			elif match_ticks_left <= 0:
				end_match(RoomState.Outcome.LOST)
		RoomState.Phase.RESULT:
			_result_ticks_left -= 1
			if _result_ticks_left <= 0:
				_back_to_lobby(now_msec)


## Whether nobody has held a seat for [constant Protocol.EMPTY_EXIT_SEC].
func is_abandoned(now_msec: int) -> bool:
	return (_seats.is_empty()
			and now_msec - _last_seated_msec > Protocol.EMPTY_EXIT_SEC * 1000)


## Whether [method state] changed since the last call.
func take_changed() -> bool:
	var was := _changed
	_changed = false
	return was


## [param you] is the seat it's for, so its holder learns their number.
func state(you: Seat = null) -> RoomState:
	var out := RoomState.new()
	out.phase = phase
	out.outcome = outcome
	out.you = you.player_id if you else 0
	var sorted := seats()
	sorted.sort_custom(func(a: Seat, b: Seat) -> bool: return a.player_id < b.player_id)
	for seat in sorted:
		var s := RoomState.Seat.new()
		s.id = seat.player_id
		s.ready = seat.ready
		s.spectating = seat.spectating
		match seat.state:
			State.AWAY:
				s.presence = RoomState.Presence.AWAY
			State.DROPPED:
				s.presence = RoomState.Presence.DROPPED
		out.seats.append(s)
	return out


func snapshot() -> Snapshot:
	var snap := world.snapshot()
	snap.match_ticks_left = match_ticks_left
	snap.world_number = world_number
	return snap


## Hitting the lobby's READY dummy toggles the hitter's ready; hitting
## START starts the match if everyone is ready.
func _on_swing_contact(contact: World.SwingContact) -> void:
	var seat := _seat_of_player(contact.attacker_id)
	if not seat:
		return
	match contact.dummy_kind:
		World.Kind.READY:
			set_ready(seat, not seat.ready)
		World.Kind.START:
			start_match(seat)


func _seat_of_player(player_id: int) -> Seat:
	for seat: Seat in _seats.values():
		if seat.player_id == player_id:
			return seat
	return null


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
			# In a match the seat waits for the lobby.
			if phase == RoomState.Phase.LOBBY and since > Protocol.LOBBY_SEAT_HOLD_SEC * 1000:
				_seats.erase(session_id)
				world.remove_player(seat.player_id)
				_close_gaps()
				_changed = true


func _back_to_lobby(now_msec: int) -> void:
	phase = RoomState.Phase.LOBBY
	outcome = RoomState.Outcome.NONE
	for seat: Seat in _seats.values():
		# PLACEHOLDER (design): ready resets when the lobby comes back.
		seat.ready = false
		seat.spectating = false
		# A seat held through the match gets the lobby's hold from now.
		if seat.state == State.DROPPED:
			seat.since_msec = now_msec
	_new_world(World.Layout.LOBBY)
	_changed = true


## A fresh world with a character for every seat that isn't spectating. The
## old world, with its dummies, is dropped.
func _new_world(layout: World.Layout) -> void:
	var fresh := World.new(layout)
	# Clients drop snapshots whose tick goes backwards.
	fresh.tick = world.tick
	world_number = (world_number + 1) % RoomState.BYTE_VALUES
	for seat: Seat in _seats.values():
		if seat.spectating:
			continue
		fresh.add_player(seat.player_id)
		fresh.set_connected(seat.player_id, seat.state != State.DROPPED)
		# The client keeps counting presses across worlds; without this the
		# press that hit START would swing again in the match.
		var old: World.Player = world.players.get(seat.player_id)
		if old:
			fresh.absorb_attacks(seat.player_id, old.attack_count)
	world = fresh


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
	## Cleared by a drop.
	var ready := false
	## Joined mid-match: no character until the lobby.
	var spectating := false
