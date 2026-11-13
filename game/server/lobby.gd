extends RefCounted
## One lobby's rules about people: who holds which seat, seat holds, and
## which phase the lobby is in. The lobby makes every phase change; each
## phase's own rules live in its object (see [code]lobby_phase.gd[/code]),
## which never knows what comes next.
##
## No networking: server.gd maps connections onto seats and calls in. Every
## time-dependent call takes the current time, so tests run on their own
## clock.

const World := preload("res://sim/world.gd")
const DataLoader := preload("res://shared/data_loader.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const LobbyPhase := preload("res://server/lobby_phase.gd")
const Seat := preload("res://server/seat.gd")
const Town := preload("res://server/town.gd")
const Run := preload("res://server/run.gd")
const Result := preload("res://server/result.gd")

## The MVP's party size. The backend's maxParticipants
## (server/internal/matches/submit.go) is the same limit.
const MAX_PLAYERS := 4
## The server stops a player whose client sends no input for this long. Inputs
## come every tick, so this rides out a burst of lost or late ones.
const INPUT_SILENCE_SEC := 0.25
## A game server started with --exit-when-empty quits once no seat has been
## held for this long. Untuned.
const EMPTY_EXIT_SEC := 60.0
## Town's map, and the run, in balance.json.
const TOWN_MAP := "town"
# PLACEHOLDER (design): every run is the same one.
const RUN := "first"
## The on_hit names in balance.json's maps that the lobby acts on.
const TOGGLE_READY := "toggle_ready"
const START_RUN := "start_run"
## Each readiness as clients see it.
const WIRE_READINESS := {
	Seat.Readiness.NOT_READY: LobbyState.Readiness.NOT_READY,
	Seat.Readiness.READY: LobbyState.Readiness.READY,
	Seat.Readiness.SPECTATING: LobbyState.Readiness.SPECTATING,
}
## Each world outcome as clients see it.
const WIRE_OUTCOME := {
	World.Outcome.NONE: LobbyState.Outcome.NONE,
	World.Outcome.WON: LobbyState.Outcome.WON,
	World.Outcome.LOST: LobbyState.Outcome.LOST,
}
## Each phase's name on the wire, by its script.
const WIRE_PHASE := {
	Town: LobbyState.Phase.TOWN,
	Run: LobbyState.Phase.RUN,
	Result: LobbyState.Phase.RESULT,
}

## A [code]town.gd[/code], [code]run.gd[/code] or [code]result.gd[/code].
## Changed only by [method _change_phase].
var phase: LobbyPhase = Town.new()
## Replaced by a fresh one in town and at the start of each run.
var world: World
## Which world this is, counting up from 0, so clients can tell a fresh
## world's snapshots from the last one's.
var world_number := 0

## By session ID, which survives reconnects.
var _seats: Dictionary[String, Seat] = {}
## Whether clients' copies of [method state] are out of date, or a newcomer
## has none yet.
var _lobby_state_unsent := true
## The last time anyone held a seat, or when the lobby was made.
var _last_seated_msec := 0


func _init(now_msec: int) -> void:
	_last_seated_msec = now_msec
	world = World.new(DataLoader.map(TOWN_MAP))


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
## town and a spectator otherwise. Returns null when every seat is
## taken. The caller handles a seat that's still connected elsewhere.
func join(session_id: String, peer_id: int) -> Seat:
	var seat: Seat = _seats.get(session_id)
	if not seat:
		if _seats.size() >= MAX_PLAYERS:
			return null
		seat = Seat.new()
		seat.player_id = _free_seat_number()
		seat.readiness = phase.newcomer_readiness()
		if seat.readiness != Seat.Readiness.SPECTATING:
			world.add_player(seat.player_id)
		_seats[session_id] = seat
	seat.peer_id = peer_id
	seat.state = Seat.State.SILENT
	world.set_connected(seat.player_id, true)
	_lobby_state_unsent = true
	return seat


## A disconnected player can't be ready, so a drop clears it.
func drop(seat: Seat) -> void:
	seat.state = Seat.State.DROPPED
	seat.peer_id = 0
	if seat.readiness == Seat.Readiness.READY:
		seat.readiness = Seat.Readiness.NOT_READY
	world.set_connected(seat.player_id, false)
	_lobby_state_unsent = true


func input(seat: Seat, move: Vector2, attack_count: int, now_msec: int) -> void:
	if seat.state != Seat.State.SILENT and seat.state != Seat.State.ACTIVE:
		return
	seat.state = Seat.State.ACTIVE
	seat.since_msec = now_msec
	# A spectator has no character, so the world ignores it.
	world.set_input(seat.player_id, move, attack_count)


## An away player stays connected and just stops.
func set_away(seat: Seat, away: bool) -> void:
	if seat.state == Seat.State.DROPPED or away == (seat.state == Seat.State.AWAY):
		return
	if away:
		seat.state = Seat.State.AWAY
		world.stop_player(seat.player_id)
	else:
		seat.state = Seat.State.SILENT
	_lobby_state_unsent = true


## One tick: input silence, the world (unless the phase freezes it), what
## the world's swings touched, dropped seats, then the phase.
func step(now_msec: int) -> void:
	# Before dropped seats are freed, so the empty wait starts when the last
	# one is freed.
	if not _seats.is_empty():
		_last_seated_msec = now_msec
	for seat: Seat in _seats.values():
		_step_seat(seat, now_msec)

	world.step()
	# Reads world each time round: a contact that starts a run replaces the
	# world, and the new one has no contacts.
	var i := 0
	while i < world.swing_contacts.size():
		_act_on_contact(world.swing_contacts[i])
		i += 1
	if not phase.holds_dropped_seats():
		for seat in seats():
			if seat.state == Seat.State.DROPPED:
				_free_seat(seat)
	if phase.is_over(world.outcome != World.Outcome.NONE, world.is_time_up()):
		_end_phase()


## Whether nobody has held a seat for [constant EMPTY_EXIT_SEC].
func is_abandoned(now_msec: int) -> bool:
	return (_seats.is_empty()
			and now_msec - _last_seated_msec > EMPTY_EXIT_SEC * 1000)


## Whether clients need [method state] sent: it changed, or someone joined.
func is_lobby_state_unsent() -> bool:
	return _lobby_state_unsent


## Called once every connected seat has been sent its [method state].
func mark_lobby_state_sent() -> void:
	_lobby_state_unsent = false


## Returns whether anything changed.
func set_ready(seat: Seat, ready: bool) -> bool:
	var readiness := Seat.Readiness.READY if ready else Seat.Readiness.NOT_READY
	if seat.readiness == readiness:
		return false
	seat.readiness = readiness
	_lobby_state_unsent = true
	return true


## Whether every seat is ready, so a run may start. False with no seats.
func all_ready() -> bool:
	return (not _seats.is_empty()
			and _seats.values().all(
				func(s: Seat) -> bool: return s.readiness == Seat.Readiness.READY))


## Starts a new run if [method all_ready], from any phase. Returns whether
## it did.
func start_run() -> bool:
	if not all_ready():
		return false
	var setup := DataLoader.run(RUN)
	_change_phase(Run.new())
	_replace_world(setup.map_name, setup.win, setup.lose)
	return true


## Shows the result of a run that ended with [param outcome], over the
## run's world, frozen, until the world's time is up.
func end_run(outcome: World.Outcome) -> void:
	# Its world keeps the outcome, for clients to see during the result.
	world.outcome = outcome
	_change_phase(Result.new())
	world.frozen = true
	world.limit_time(DataLoader.result_sec)


## [param you] is the seat it's for, so its holder learns their number.
func state(you: Seat = null) -> LobbyState:
	var out := LobbyState.new()
	out.phase = WIRE_PHASE[phase.get_script()]
	out.outcome = WIRE_OUTCOME[world.outcome]
	out.all_ready = all_ready()
	out.you = you.player_id if you else 0
	var sorted := seats()
	sorted.sort_custom(func(a: Seat, b: Seat) -> bool: return a.player_id < b.player_id)
	for seat in sorted:
		var s := LobbyState.Seat.new()
		s.id = seat.player_id
		s.readiness = WIRE_READINESS[seat.readiness]
		match seat.state:
			Seat.State.AWAY:
				s.presence = LobbyState.Presence.AWAY
			Seat.State.DROPPED:
				s.presence = LobbyState.Presence.DROPPED
		out.seats.append(s)
	return out


func snapshot() -> Snapshot:
	var snap := world.snapshot()
	snap.world_number = world_number
	return snap


func _change_phase(next: LobbyPhase) -> void:
	phase = next
	_lobby_state_unsent = true


## Moves on from [member phase], which just ended on its own.
func _end_phase() -> void:
	match WIRE_PHASE[phase.get_script()]:
		LobbyState.Phase.RUN:
			end_run(world.outcome)
		LobbyState.Phase.RESULT:
			_start_town()


func _start_town() -> void:
	_change_phase(Town.new())
	for seat in seats():
		# PLACEHOLDER (design): ready resets when town comes back.
		seat.readiness = Seat.Readiness.NOT_READY
	_replace_world(TOWN_MAP)


## Toggles readiness or starts a run, by what the dummy it touched asks.
func _act_on_contact(contact: World.SwingContact) -> void:
	var seat := _seat_of_player(contact.attacker_id)
	if not seat:
		return
	match contact.on_hit:
		TOGGLE_READY:
			set_ready(seat, seat.readiness != Seat.Readiness.READY)
		START_RUN:
			start_run()


## Null if no seat has [param player_id].
func _seat_of_player(player_id: int) -> Seat:
	for seat: Seat in _seats.values():
		if seat.player_id == player_id:
			return seat
	return null


## Frees [param seat] for someone else; the seats after it move down.
func _free_seat(seat: Seat) -> void:
	_seats.erase(_seats.find_key(seat))
	world.remove_player(seat.player_id)
	_close_gaps()
	_lobby_state_unsent = true


## A fresh world with a character for every seat that isn't spectating. The
## old world, with its dummies, is dropped.
func _replace_world(map_name: String, win: Array[DataLoader.ConditionEntry] = [],
		lose: Array[DataLoader.ConditionEntry] = []) -> void:
	var fresh := World.new(DataLoader.map(map_name), world, win, lose)
	world_number += 1
	for seat: Seat in _seats.values():
		if seat.readiness == Seat.Readiness.SPECTATING:
			continue
		fresh.add_player(seat.player_id, seat.state != Seat.State.DROPPED)
	world = fresh


func _step_seat(seat: Seat, now_msec: int) -> void:
	# The client went quiet without disconnecting.
	if (seat.state == Seat.State.ACTIVE
			and now_msec - seat.since_msec > INPUT_SILENCE_SEC * 1000):
		seat.state = Seat.State.SILENT
		world.stop_player(seat.player_id)


## Moves everyone after a freed seat down one (2 to 1, 3 to 2 ...), so the
## lobby's seats are always 1 to n. Only town frees seats.
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
