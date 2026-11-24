extends Resource
## A way between two rooms, always both ways: [member from]'s [member side]
## wall leads to [member to]'s opposite wall.

const Room := preload("res://shared/data/room.gd")

@export var from: Room
@export var side := Direction.Cardinal.NORTH
@export var to: Room
