extends RefCounted
## A place in the lobby. It outlives its connection, so a reconnect gets
## the same seat back.

const PlayerData := preload("res://server/player_data.gd")
const Protocol := preload("res://net/protocol.gd")

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
## Its holder's account data, kept while the seat is held and lost when
## the seat is freed.
var player_data: PlayerData
## A drop clears READY. A seat that joins mid-run spectates, with no
## character, until town.
var participation := Participation.NOT_READY
## The press counters its connection last sent, one per input action. A new
## connection counts from 0.
var press_counters := PackedByteArray()


func _init() -> void:
	press_counters.resize(Protocol.INPUT_ACTION_COUNT)


## How many times each input action was pressed since the counters last sent,
## from [param counters], which become the last.
func take_presses(counters: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(counters.size())
	for i in counters.size():
		out[i] = posmod(counters[i] - press_counters[i], Protocol.PRESS_COUNTER_MODULUS)
	press_counters = counters.duplicate()
	return out
