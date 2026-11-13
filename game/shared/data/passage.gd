extends Resource
## A way between two rooms, always both ways: [member from]'s [member side]
## wall leads to [member to]'s opposite wall.

const Map := preload("res://shared/data/map.gd")
const RoomGraph := preload("res://shared/room_graph.gd")

@export var from: Map
@export var side := RoomGraph.Side.NORTH
@export var to: Map
