extends Resource
## Every unit type, in a fixed order: a unit type's place in it is the number
## snapshots send for it.

const UnitType := preload("res://shared/data/unit_type.gd")

@export var types: Array[UnitType] = []


## [param unit_type]'s number in snapshots.
func index_of(unit_type: UnitType) -> int:
	return types.find(unit_type)
