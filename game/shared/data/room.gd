extends Resource
## A room's layout: what's in it when the party first enters.

const RoomDummy := preload("res://shared/data/room_dummy.gd")
const Condition := preload("res://shared/data/condition.gd")

@export var dummies: Array[RoomDummy] = []
## The room is cleared once any of these is met; with none, it starts
## cleared.
@export var clear_when: Array[Condition] = []
