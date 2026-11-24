extends RefCounted
## Where a room's walls and doors are, in px: a ring
## [member Balance.wall_thickness] thick just inside the arena, with a
## door's gap centered on each wall that has one.
## The server collides with these rectangles and the client draws them, so
## both work them out here.

const Balance := preload("res://shared/data/balance.gd")

const BALANCE: Balance = preload("res://shared/data/balance.tres")

static var _arena: Rect2 = BALANCE.arena()
static var _wall: float = BALANCE.wall_thickness
## How wide a door's gap in its wall is, in px: a whole number of tiles.
static var door_width := 64.0


## [param sides] as one number, bit [code]1 << side[/code] for each.
static func door_bits(sides: Array[Direction.Cardinal]) -> int:
	var out := 0
	for side in sides:
		out |= 1 << side
	return out


## The sides [method door_bits] packed into [param bits].
static func sides_in(bits: int) -> Array[Direction.Cardinal]:
	var out: Array[Direction.Cardinal] = []
	for side: Direction.Cardinal in Direction.Cardinal.values():
		if bits & (1 << side):
			out.append(side)
	return out


## Where bodies can be while every door is shut: the arena inside its walls.
static func floor_area() -> Rect2:
	return _arena.grow(-_wall)


## Every wall piece, with a gap on each of [param door_sides]. North and
## south run the arena's whole width; west and east fit between them, so no
## two overlap.
static func walls(door_sides: Array[Direction.Cardinal]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for side: Direction.Cardinal in Direction.Cardinal.values():
		out.append_array(wall(side, door_sides.has(side)))
	return out


## The pieces of the wall on [param side]: one, or the two either side of
## its door's gap.
static func wall(side: Direction.Cardinal, has_door: bool) -> Array[Rect2]:
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


## The gap for a door on [param side], centered on that wall and as deep
## as it.
static func door(side: Direction.Cardinal) -> Rect2:
	var center := _arena.get_center()
	var half := door_width / 2
	match side:
		Direction.Cardinal.NORTH:
			return Rect2(center.x - half, _arena.position.y, door_width, _wall)
		Direction.Cardinal.SOUTH:
			return Rect2(center.x - half, _arena.end.y - _wall, door_width, _wall)
		Direction.Cardinal.WEST:
			return Rect2(_arena.position.x, center.y - half, _wall, door_width)
	return Rect2(_arena.end.x - _wall, center.y - half, _wall, door_width)


static func _whole_wall(side: Direction.Cardinal) -> Rect2:
	var inner := floor_area()
	match side:
		Direction.Cardinal.NORTH:
			return Rect2(_arena.position.x, _arena.position.y, _arena.size.x, _wall)
		Direction.Cardinal.SOUTH:
			return Rect2(_arena.position.x, inner.end.y, _arena.size.x, _wall)
		Direction.Cardinal.WEST:
			return Rect2(_arena.position.x, inner.position.y, _wall, inner.size.y)
	return Rect2(inner.end.x, inner.position.y, _wall, inner.size.y)
