extends "res://sim/run_conditions/run_condition.gd"
## Met once its timer runs out.

var ticks_left: int


func _init(ticks: int) -> void:
	ticks_left = ticks


func step(_world: World) -> bool:
	ticks_left -= 1
	return ticks_left <= 0
