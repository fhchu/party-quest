extends RefCounted
## Where a room's walls and doors are, in px: a ring one tile thick just
## inside the arena, with a door's gap centered on each wall that has one.
## The server collides with these rectangles and the client draws them, so
## both work them out here.

const RoomShape := preload("res://shared/room_shape.gd")
const Balance := preload("res://shared/data/balance.gd")

## A room's four walls. Opposite walls are two apart.
enum Side {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

const BALANCE: Balance = preload("res://shared/data/balance.tres")

static var _arena: Rect2 = BALANCE.arena()
static var _tile: float = BALANCE.tile_size
static var _door_width: float = BALANCE.door_width


## The wall across the room from [param side].
static func opposite(side: RoomShape.Side) -> RoomShape.Side:
	return (side + 2) % Side.size() as RoomShape.Side


## [param sides] as one number, bit [code]1 << side[/code] for each.
static func door_bits(sides: Array[RoomShape.Side]) -> int:
	var out := 0
	for side in sides:
		out |= 1 << side
	return out


## The sides [method door_bits] packed into [param bits].
static func sides_in(bits: int) -> Array[RoomShape.Side]:
	var out: Array[RoomShape.Side] = []
	for side: RoomShape.Side in Side.values():
		if bits & (1 << side):
			out.append(side)
	return out


## Where bodies can be while every door is shut: the arena inside its walls.
static func floor_area() -> Rect2:
	return _arena.grow(-_tile)


## Every wall piece, with a gap on each of [param door_sides]. North and
## south run the arena's whole width; west and east fit between them, so no
## two overlap.
static func walls(door_sides: Array[RoomShape.Side]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for side: RoomShape.Side in RoomShape.Side.values():
		out.append_array(wall(side, door_sides.has(side)))
	return out


## The pieces of the wall on [param side]: one, or the two either side of
## its door's gap.
static func wall(side: RoomShape.Side, has_door: bool) -> Array[Rect2]:
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
static func door(side: RoomShape.Side) -> Rect2:
	var center := _arena.get_center()
	var half := _door_width / 2
	match side:
		RoomShape.Side.NORTH:
			return Rect2(center.x - half, _arena.position.y, _door_width, _tile)
		RoomShape.Side.SOUTH:
			return Rect2(center.x - half, _arena.end.y - _tile, _door_width, _tile)
		RoomShape.Side.WEST:
			return Rect2(_arena.position.x, center.y - half, _tile, _door_width)
	return Rect2(_arena.end.x - _tile, center.y - half, _tile, _door_width)


## Away from the wall on [param side], toward the middle of the room.
static func inward(side: RoomShape.Side) -> Vector2:
	match side:
		RoomShape.Side.NORTH:
			return Vector2.DOWN
		RoomShape.Side.SOUTH:
			return Vector2.UP
		RoomShape.Side.WEST:
			return Vector2.RIGHT
	return Vector2.LEFT


static func _whole_wall(side: RoomShape.Side) -> Rect2:
	var inner := floor_area()
	match side:
		RoomShape.Side.NORTH:
			return Rect2(_arena.position.x, _arena.position.y, _arena.size.x, _tile)
		RoomShape.Side.SOUTH:
			return Rect2(_arena.position.x, inner.end.y, _arena.size.x, _tile)
		RoomShape.Side.WEST:
			return Rect2(_arena.position.x, inner.position.y, _tile, inner.size.y)
	return Rect2(inner.end.x, inner.position.y, _tile, inner.size.y)
