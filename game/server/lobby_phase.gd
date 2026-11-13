@abstract
extends RefCounted
## One of the lobby's phases: [code]town.gd[/code], [code]run.gd[/code]
## or [code]result.gd[/code]. The lobby holds one at a time and asks it
## about its rules. A phase never knows which comes next; the lobby decides
## when one ends.

const LobbyState := preload("res://net/lobby_state.gd")


## Sets the phase's own part of what clients see. The lobby sets which
## phase it is.
func fill_state(_out: LobbyState) -> void:
	pass


## Whether a dropped player's seat waits for their return. When it doesn't,
## the lobby frees it.
func holds_dropped_seats() -> bool:
	return true


## Whether this phase is over, given its world's [param outcome] and
## whether its world's time is up.
func is_over(_outcome: LobbyState.Outcome, _time_up: bool) -> bool:
	return false


func newcomer_readiness() -> LobbyState.Readiness:
	return LobbyState.Readiness.SPECTATING
