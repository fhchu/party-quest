extends "res://server/lobby_phase.gd"
## Plays until its world's run conditions give an outcome.


func is_over(outcome: LobbyState.Outcome, _tick: int) -> bool:
	return outcome != LobbyState.Outcome.NONE
