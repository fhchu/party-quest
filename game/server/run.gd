extends "res://server/lobby_phase.gd"
## Plays until its world's run conditions give an outcome.


func is_over(world_ended: bool, _time_up: bool) -> bool:
	return world_ended
