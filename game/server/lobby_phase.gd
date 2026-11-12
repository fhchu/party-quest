@abstract
extends RefCounted
## One of the lobby's phases: [code]town.gd[/code], [code]run.gd[/code]
## or [code]result.gd[/code]. The lobby holds one at a time, asks it about
## its rules and steps it. A phase never knows which comes next; the lobby
## decides when one ends.

const World := preload("res://sim/world.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")


## Sets the phase's own part of what clients see. The lobby sets which
## phase it is.
func fill_state(_out: LobbyState) -> void:
	pass


## Whether a dropped player's seat waits for their return. When it doesn't,
## the lobby frees it.
func holds_dropped_seats() -> bool:
	return true


## One tick, after the world's. Returns whether this phase is over.
func step(_world: World) -> bool:
	return false


func newcomer_readiness() -> LobbyState.Readiness:
	return LobbyState.Readiness.SPECTATING


func fill_snapshot(_snap: Snapshot) -> void:
	pass
