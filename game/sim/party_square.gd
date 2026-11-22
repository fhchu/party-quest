extends RefCounted
## Where the party goes together: a square of players, hurtboxes touching,
## two wide.

const RoomPlan := preload("res://sim/room_plan.gd")

## How many players wide the square is. PLACEHOLDER (design).
const COLUMNS := 2


## Where each of [param ids] goes, by seat order: the first at
## [param first], the second to its right, the third below the first and the
## fourth below the second. Each player is [param size] across. The whole
## square shifts as little as it must to be on [param floor_area].
static func spots(ids: Array, first: Vector2, size: Vector2,
		floor_area: Rect2) -> Dictionary[int, Vector2]:
	var sorted := ids.duplicate()
	sorted.sort()
	var square := Rect2(first - size / 2, size_of(sorted.size(), size))
	var shift := Vector2(
			clampf(square.position.x, floor_area.position.x, floor_area.end.x - square.size.x),
			clampf(square.position.y, floor_area.position.y, floor_area.end.y - square.size.y)
	) - square.position
	var out: Dictionary[int, Vector2] = {}
	for i in sorted.size():
		var cell := Vector2(i % COLUMNS, floori(float(i) / COLUMNS))
		out[sorted[i]] = first + shift + cell * size
	return out


## How big a square of [param count] players [param size] across is, in px.
static func size_of(count: int, size: Vector2) -> Vector2:
	return size * Vector2(mini(count, COLUMNS), ceili(float(count) / COLUMNS))


## Where each of [param ids] goes on coming in by [param door]: in the
## square just inside it, centered across it, its near edge half a player in
## from the floor's edge, clear of the gap.
static func inside_door(ids: Array, door: RoomPlan.DoorPlan, size: Vector2,
		floor_area: Rect2) -> Dictionary[int, Vector2]:
	var gap := door.arrive_by.gap
	var normal := door.arrive_by.inward
	var in_from_gap := (absf(gap.size.dot(normal)) + absf(size.dot(normal))) / 2
	var near_edge := gap.get_center() + normal * in_from_gap
	var square_size := size_of(ids.size(), size)
	var center := near_edge + normal * absf(square_size.dot(normal)) / 2
	return spots(ids, center - square_size / 2 + size / 2, size, floor_area)
