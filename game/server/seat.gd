extends RefCounted
## A place in the lobby. It outlives its connection, so a reconnect gets
## the same seat back.

## Its connection's state. SILENT: connected, no input yet or lately.
## AWAY: tab hidden, so input is ignored and no snapshots are sent.
## DROPPED: disconnected, seat held.
enum State {
	SILENT,
	ACTIVE,
	AWAY,
	DROPPED,
}

const LobbyState := preload("res://net/lobby_state.gd")

## Also the seat number, 1 to [constant Lobby.MAX_PLAYERS]. A player's color and spawn spot
## go with it, like a controller port. Lowered when an earlier lobby seat
## is freed.
var player_id: int
## 0 while DROPPED: no Godot peer has ID 0.
var peer_id := 0
var state := State.SILENT
## ACTIVE: the last input.
var since_msec := 0
## A drop clears READY. A seat that joins mid-run spectates, with no
## character, until town.
var readiness := LobbyState.Readiness.NOT_READY
