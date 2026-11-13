extends RefCounted
## How a run's rooms join: its maps are the nodes and its passages the
## edges. The world asks it where a room's doors lead.

const RoomShape := preload("res://shared/room_shape.gd")
const Map := preload("res://shared/data/map.gd")
const Passage := preload("res://shared/data/passage.gd")

var _passages: Array[Passage] = []


func _init(passages: Array[Passage]) -> void:
	_passages = passages


## The doors out of [param room]: one for each passage that joins it, seen
## from it, whichever end the passage was listed from.
func doors(room: Map) -> Array[Door]:
	var out: Array[Door] = []
	for passage in _passages:
		if passage.from == room:
			out.append(Door.new(passage.side, passage.to))
		if passage.to == room:
			out.append(Door.new(RoomShape.opposite(passage.side), passage.from))
	return out


## One way out of a room.
class Door:
	var side := RoomShape.Side.NORTH
	## The room it leads to.
	var to: Map

	func _init(door_side: RoomShape.Side, leads_to: Map) -> void:
		side = door_side
		to = leads_to
