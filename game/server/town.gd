extends "res://server/lobby_phase.gd"
## Walking around and readying up by hitting the READY dummy. Hitting START
## starts the run once everyone is ready. Only town frees a dropped
## player's seat.

const Run := preload("res://server/run.gd")


func fill_state(out: LobbyState) -> void:
	out.phase = LobbyState.Phase.TOWN


func enter(lobby: Lobby, now_msec: int) -> void:
	for seat in lobby.seats():
		# PLACEHOLDER (design): ready resets when town comes back.
		seat.readiness = LobbyState.Readiness.NOT_READY
	lobby.replace_world(World.Layout.TOWN)


## A run holds a dropped seat for its player's return; town lets it go
## at once, and frees the seats a run held as soon as it comes back.
func step(lobby: Lobby, _now_msec: int) -> void:
	for seat in lobby.seats():
		if seat.state == Lobby.State.DROPPED:
			lobby.free_seat(seat)


func on_swing_contact(lobby: Lobby, contact: World.SwingContact, now_msec: int) -> void:
	var seat := lobby.seat_of_player(contact.attacker_id)
	if not seat:
		return
	match contact.on_hit:
		World.Dummy.OnHit.TOGGLE_READY:
			set_ready(lobby, seat, seat.readiness != LobbyState.Readiness.READY)
		World.Dummy.OnHit.START_RUN:
			start_run(lobby, now_msec)


func newcomer_readiness() -> LobbyState.Readiness:
	return LobbyState.Readiness.NOT_READY


## Returns whether anything changed.
func set_ready(lobby: Lobby, seat: Lobby.Seat, ready: bool) -> bool:
	var readiness := LobbyState.Readiness.READY if ready else LobbyState.Readiness.NOT_READY
	if seat.readiness == readiness:
		return false
	seat.readiness = readiness
	lobby.mark_lobby_state_unsent()
	return true


## Starts the run if [method LobbyState.all_ready]. Returns whether it did.
func start_run(lobby: Lobby, now_msec: int) -> bool:
	if not lobby.state().all_ready():
		return false
	lobby.change_phase(Run.new(), now_msec)
	return true
