extends "res://server/lobby_phase.gd"
## Walking around and readying up by hitting the READY dummy. Town's door
## opens once everyone is ready, and walking through it opens the level
## select over town's frozen world. Choosing a level wins town's world, which
## ends town and starts that level's run. Only town frees a dropped player's
## seat.


## A run holds a dropped seat for its player's return; town lets it go
## at once, and frees the seats a run held as soon as it comes back.
func holds_dropped_seats() -> bool:
	return false


func doors_follow_readiness() -> bool:
	return true


func is_over(world_ended: bool, _time_up: bool) -> bool:
	return world_ended


func newcomers_play() -> bool:
	return true
