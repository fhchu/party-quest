extends RefCounted
## A place in the lobby. It outlives its connection, so a reconnect gets
## the same seat back.

## How it's connected. SILENT: connected, no input yet or lately.
## AWAY: tab hidden, so input is ignored and no snapshots are sent.
## DROPPED: disconnected, seat held.
enum Connection {
	SILENT,
	ACTIVE,
	AWAY,
	DROPPED,
}

## How it takes part: playing, ready or not, or watching. SPECTATING:
## joined mid-run, so no character until town.
enum Participation {
	NOT_READY,
	READY,
	SPECTATING,
}

## Also the seat number, 1 to [constant Lobby.MAX_PLAYERS]. A player's color and spawn spot
## go with it, like a controller port. Lowered when an earlier lobby seat
## is freed.
var player_id: int
## 0 while DROPPED: no Godot peer has ID 0.
var peer_id := 0
var connection := Connection.SILENT
## ACTIVE: the last input.
var since_msec := 0
## Earned from won runs while the seat is held. PLACEHOLDER: lost when the
## seat is freed, until gold is saved per account.
var gold := 0
## A drop clears READY. A seat that joins mid-run spectates, with no
## character, until town.
var participation := Participation.NOT_READY
