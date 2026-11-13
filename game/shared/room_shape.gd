extends RefCounted
## Where a room's walls are, in px: a ring one tile thick just inside the
## arena. The server collides with these rectangles and the client draws
## them, so both work them out here.

const DataLoader := preload("res://shared/data_loader.gd")

static var _arena: Rect2 = DataLoader.arena
static var _tile: float = DataLoader.tile_size


## Where bodies can be: the arena inside its walls.
static func floor_area() -> Rect2:
	return _arena.grow(-_tile)


## North and south run the arena's whole width; west and east fit between
## them, so no two overlap.
static func walls() -> Array[Rect2]:
	var inner := floor_area()
	var out: Array[Rect2] = [
		Rect2(_arena.position.x, _arena.position.y, _arena.size.x, _tile),
		Rect2(_arena.position.x, inner.end.y, _arena.size.x, _tile),
		Rect2(_arena.position.x, inner.position.y, _tile, inner.size.y),
		Rect2(inner.end.x, inner.position.y, _tile, inner.size.y),
	]
	return out
