extends Resource
## A room's layout: what's in it when the party first enters.

const MapDummy := preload("res://shared/data/map_dummy.gd")
const Condition := preload("res://shared/data/condition.gd")

@export var dummies: Array[MapDummy] = []
## The room is cleared once any of these is met; with none, it starts
## cleared.
@export var clear_when: Array[Condition] = []
