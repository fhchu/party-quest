extends "res://server/lobby_phase.gd"
## Walking around and readying up by hitting the READY dummy. Hitting START
## starts the run once everyone is ready. Only town frees a dropped
## player's seat.


## A run holds a dropped seat for its player's return; town lets it go
## at once, and frees the seats a run held as soon as it comes back.
func holds_dropped_seats() -> bool:
	return false


func newcomer_readiness() -> Seat.Readiness:
	return Seat.Readiness.NOT_READY
