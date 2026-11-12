@abstract
extends RefCounted
## One of the lobby's phases: [code]town.gd[/code], [code]run.gd[/code]
## or [code]result.gd[/code]. The lobby holds one at a time and calls these
## hooks; what only one phase can do (start a run, end one) is a method on
## that phase alone.

const Lobby := preload("res://server/lobby.gd")
const World := preload("res://sim/world.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")


## Sets the phase's part of what clients see, including which phase it is.
@abstract func fill_state(out: LobbyState) -> void


## Called once, when the lobby changes to this phase.
func enter(_lobby: Lobby, _now_msec: int) -> void:
	pass


## Whether the world steps this tick. When it doesn't, only its tick counts
## on, so it looks frozen.
func runs_world() -> bool:
	return true


## One tick, after the world's.
func step(_lobby: Lobby, _now_msec: int) -> void:
	pass


func on_swing_contact(_lobby: Lobby, _contact: World.SwingContact, _now_msec: int) -> void:
	pass


func on_input(lobby: Lobby, seat: Lobby.Seat, move: Vector2, attack_count: int) -> void:
	# Longer than 1 would move faster than the player's speed. A spectator
	# has no character, so the world ignores it.
	lobby.world.set_input(seat.player_id, move.limit_length(1.0), attack_count)


func newcomer_readiness() -> LobbyState.Readiness:
	return LobbyState.Readiness.SPECTATING


func fill_snapshot(_snap: Snapshot) -> void:
	pass
