extends Resource
## A way between two rooms, always both ways: [member from]'s [member side]
## wall leads to [member to]'s opposite wall.

const Room := preload("res://shared/data/room.gd")
const RoomShape := preload("res://shared/room_shape.gd")

@export var from: Room
@export var side := RoomShape.Side.NORTH
@export var to: Room
