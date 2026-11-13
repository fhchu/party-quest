extends RefCounted
## How a run's rooms join: the passages between them. A run's rooms are
## the nodes and its passages the edges.

const RoomShape := preload("res://shared/room_shape.gd")


## The Side named [param side_name] in any case ([code]"north"[/code]); -1
## for none.
static func side_named(side_name: String) -> int:
	return RoomShape.Side.keys().find(side_name.to_upper())


## The doors out of [param room]: each passage that joins it, seen from it,
## whichever end it was listed from.
static func doors(passages: Array[Passage], room: String) -> Array[Passage]:
	var out: Array[Passage] = []
	for passage in passages:
		if passage.from == room:
			out.append(passage)
		if passage.to == room:
			out.append(Passage.new(passage.to, RoomShape.opposite(passage.side), passage.from))
	return out


## A way between two rooms, always both ways: [member from]'s
## [member side] wall leads to [member to]'s opposite wall.
class Passage:
	var from := ""
	var side := RoomShape.Side.NORTH
	var to := ""

	func _init(from_room: String, from_side: RoomShape.Side, to_room: String) -> void:
		from = from_room
		side = from_side
		to = to_room
