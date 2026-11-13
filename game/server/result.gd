extends "res://server/lobby_phase.gd"
## The outcome shows over the run's frozen world until the world's time is
## up. The world keeps the outcome.


func is_over(_world_ended: bool, time_up: bool) -> bool:
	return time_up
