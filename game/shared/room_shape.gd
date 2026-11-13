extends RefCounted
## Where a room's walls and doors are, in px: a ring one tile thick just
## inside the arena, with a door's gap centered on each wall that has one.
## The server collides with these rectangles and the client draws them, so
## both work them out here.

const DataLoader := preload("res://shared/data_loader.gd")
const RoomGraph := preload("res://shared/room_graph.gd")

static var _arena: Rect2 = DataLoader.arena
static var _tile: float = DataLoader.tile_size
static var _door_width: float = DataLoader.door_width


## Where bodies can be while every door is shut: the arena inside its walls.
static func floor_area() -> Rect2:
	return _arena.grow(-_tile)


## Every wall piece, with a gap on each of [param door_sides]. North and
## south run the arena's whole width; west and east fit between them, so no
## two overlap.
static func walls(door_sides: Array[RoomGraph.Side]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for side: RoomGraph.Side in RoomGraph.Side.values():
		out.append_array(wall(side, door_sides.has(side)))
	return out


## The pieces of the wall on [param side]: one, or the two either side of
## its door's gap.
static func wall(side: RoomGraph.Side, has_door: bool) -> Array[Rect2]:
	var whole := _whole_wall(side)
	if not has_door:
		return [whole]
	var gap := door(side)
	var out: Array[Rect2] = []
	if whole.size.x > whole.size.y:
		out.append(Rect2(whole.position.x, whole.position.y,
				gap.position.x - whole.position.x, whole.size.y))
		out.append(Rect2(gap.end.x, whole.position.y, whole.end.x - gap.end.x, whole.size.y))
	else:
		out.append(Rect2(whole.position.x, whole.position.y,
				whole.size.x, gap.position.y - whole.position.y))
		out.append(Rect2(whole.position.x, gap.end.y, whole.size.x, whole.end.y - gap.end.y))
	return out


## The gap for a door on [param side], centered on that wall and one tile
## deep.
static func door(side: RoomGraph.Side) -> Rect2:
	var center := _arena.get_center()
	var half := _door_width / 2
	match side:
		RoomGraph.Side.NORTH:
			return Rect2(center.x - half, _arena.position.y, _door_width, _tile)
		RoomGraph.Side.SOUTH:
			return Rect2(center.x - half, _arena.end.y - _tile, _door_width, _tile)
		RoomGraph.Side.WEST:
			return Rect2(_arena.position.x, center.y - half, _tile, _door_width)
	return Rect2(_arena.end.x - _tile, center.y - half, _tile, _door_width)


## Away from the wall on [param side], toward the middle of the room.
static func inward(side: RoomGraph.Side) -> Vector2:
	match side:
		RoomGraph.Side.NORTH:
			return Vector2.DOWN
		RoomGraph.Side.SOUTH:
			return Vector2.UP
		RoomGraph.Side.WEST:
			return Vector2.RIGHT
	return Vector2.LEFT


static func _whole_wall(side: RoomGraph.Side) -> Rect2:
	var inner := floor_area()
	match side:
		RoomGraph.Side.NORTH:
			return Rect2(_arena.position.x, _arena.position.y, _arena.size.x, _tile)
		RoomGraph.Side.SOUTH:
			return Rect2(_arena.position.x, inner.end.y, _arena.size.x, _tile)
		RoomGraph.Side.WEST:
			return Rect2(_arena.position.x, inner.position.y, _tile, inner.size.y)
	return Rect2(inner.end.x, inner.position.y, _tile, inner.size.y)
