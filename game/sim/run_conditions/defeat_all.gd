extends "res://sim/run_conditions/run_condition.gd"
## Met once no dummy of its kind is left.

var _kind: int


func _init(kind: int) -> void:
	_kind = kind


func step(world: World) -> bool:
	return world.dummies.all(func(d: World.Dummy) -> bool: return d.kind != _kind)
