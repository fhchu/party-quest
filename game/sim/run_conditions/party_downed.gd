extends "res://sim/run_conditions/run_condition.gd"
## Met once every player is downed.


func step(world: World) -> bool:
	return world.players_alive() == 0
