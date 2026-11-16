@abstract
extends RefCounted
## One of the lobby's phases: [code]town.gd[/code], [code]run.gd[/code]
## or [code]result.gd[/code]. The lobby holds one at a time and asks it
## about its rules. A phase never knows which comes next; the lobby decides
## when one ends.


## Whether a dropped player's seat waits for their return. When it doesn't,
## the lobby frees it.
func holds_dropped_seats() -> bool:
	return true


## Whether its world's doors are open only while every seat is ready.
func doors_follow_readiness() -> bool:
	return false


## Whether this phase is over, given whether its world's run has ended and
## whether its world's time is up.
func is_over(_world_ended: bool, _time_up: bool) -> bool:
	return false


## Whether someone who joins now gets a character. When they don't, they
## spectate until town.
func newcomers_play() -> bool:
	return false
