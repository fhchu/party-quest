extends RefCounted
## How a run's rooms join: its rooms are the nodes and its passages the
## edges. The world asks it where a room's doors lead.

const RoomShape := preload("res://shared/room_shape.gd")
const Room := preload("res://shared/data/room.gd")
const Passage := preload("res://shared/data/passage.gd")

var _passages: Array[Passage] = []


func _init(passages: Array[Passage]) -> void:
	_passages = passages


## The doors out of [param room]: one for each passage that joins it, seen
## from it, whichever end the passage was listed from.
func doors(room: Room) -> Array[Door]:
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
	var to: Room

	func _init(door_side: RoomShape.Side, leads_to: Room) -> void:
		side = door_side
		to = leads_to
