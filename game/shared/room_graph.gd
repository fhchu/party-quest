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


## [param sides] as one number, bit [code]1 << side[/code] for each.
static func door_bits(sides: Array[RoomGraph.Side]) -> int:
	var out := 0
	for side in sides:
		out |= 1 << side
	return out


## The sides [method door_bits] packed into [param bits].
static func sides_in(bits: int) -> Array[RoomGraph.Side]:
	var out: Array[RoomGraph.Side] = []
	for side: RoomGraph.Side in Side.values():
		if bits & (1 << side):
			out.append(side)
	return out


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
