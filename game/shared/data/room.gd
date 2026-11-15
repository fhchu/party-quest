extends Resource
## A room's layout: what's in it when the party first enters.

const RoomDummy := preload("res://shared/data/room_dummy.gd")
const Condition := preload("res://shared/data/condition.gd")

@export var dummies: Array[RoomDummy] = []
## The room is cleared once any of these is met; with none, it starts
## cleared.
@export var clear_when: Array[Condition] = []
## Where the first player starts when a world starts in this room, in arena
## px; the rest of the party forms a square from there. Only a world's
## first room uses it.
@export var spawn := Vector2.ZERO
## Which way the party faces when a world starts in this room. Only a
## world's first room uses it.
@export var spawn_facing := Vector2.DOWN
