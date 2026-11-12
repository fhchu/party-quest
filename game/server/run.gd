extends "res://server/lobby_phase.gd"
## Plays until its world's run conditions give an outcome.


func is_over(outcome: LobbyState.Outcome, _time_up: bool) -> bool:
	return outcome != LobbyState.Outcome.NONE
