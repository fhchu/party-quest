extends RefCounted
## How a run's rooms join: the walls doors are on, and the passages between
## rooms. A run's rooms are the nodes and its passages the edges.

const RoomGraph := preload("res://shared/room_graph.gd")

## A room's four walls. Opposite walls are two apart.
enum Side {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}


## The wall across the room from [param side].
static func opposite(side: RoomGraph.Side) -> RoomGraph.Side:
	return (side + 2) % Side.size() as RoomGraph.Side


## The Side named [param side_name] in any case ([code]"north"[/code]); -1
## for none.
static func side_named(side_name: String) -> int:
	return Side.keys().find(side_name.to_upper())


## The doors out of [param room]: each passage that joins it, seen from it,
## whichever end it was listed from.
static func doors(passages: Array[Passage], room: String) -> Array[Passage]:
	var out: Array[Passage] = []
	for passage in passages:
		if passage.from == room:
			out.append(passage)
		if passage.to == room:
			out.append(Passage.new(passage.to, opposite(passage.side), passage.from))
	return out


## A way between two rooms, always both ways: [member from]'s
## [member side] wall leads to [member to]'s opposite wall.
class Passage:
	var from := ""
	var side := RoomGraph.Side.NORTH
	var to := ""

	func _init(from_room: String, from_side: RoomGraph.Side, to_room: String) -> void:
		from = from_room
		side = from_side
		to = to_room
