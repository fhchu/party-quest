extends Resource
## A way between two rooms, always both ways: [member from]'s [member side]
## wall leads to [member to]'s opposite wall.

const Map := preload("res://shared/data/map.gd")
const RoomShape := preload("res://shared/room_shape.gd")

@export var from: Map
@export var side := RoomShape.Side.NORTH
@export var to: Map
