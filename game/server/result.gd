extends "res://server/lobby_phase.gd"
## The outcome shows over a frozen world until the world's time is up.

var outcome: LobbyState.Outcome


func _init(run_outcome: LobbyState.Outcome) -> void:
	outcome = run_outcome


func fill_state(out: LobbyState) -> void:
	out.outcome = outcome


func is_over(_outcome: LobbyState.Outcome, time_up: bool) -> bool:
	return time_up
