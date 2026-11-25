extends RefCounted
## What bodies are pushed back out of in the current room, and moving them
## so they slide along it.

const Body := preload("res://sim/body.gd")
const RoomState := preload("res://sim/room_state.gd")
const RoomPlan := preload("res://sim/room_plan.gd")
const WallPlan := preload("res://sim/wall_plan.gd")

var _solids: Array[Solid] = []


## Solid behind the side of [param rect] that [param normal] points away
## from; the normal points into the room.
static func _half_plane(normal: Vector2, rect: Rect2) -> Solid:
	var plane := WorldBoundaryShape2D.new()
	plane.normal = normal
	plane.distance = normal.dot(rect.get_center() - normal * rect.size / 2)
	var out := Solid.new()
	out.shape = plane
	return out


static func _box(rect: Rect2) -> Solid:
	var box := RectangleShape2D.new()
	box.size = rect.size
	var out := Solid.new()
	out.shape = box
	out.at = Transform2D(0.0, rect.get_center())
	return out


static func _has_door(room: RoomState, wall: WallPlan) -> bool:
	return room.doors.any(func(d: RoomPlan.DoorPlan) -> bool: return d.wall == wall)


## Places the walls for [param room]. Each wall is solid as far back as
## anything can be pushed: a half-plane along its inner face, or, while its
## door is open, a player's size past the arena's edge, so a player's center
## can get into the gap, with the pieces either side of the gap reaching far
## behind it, so nothing gets stuck inside one.
func place(room: RoomState, walls: Array[WallPlan], floor_area: Rect2, arena: Rect2,
		player_size: Vector2) -> void:
	_solids.clear()
	for wall in walls:
		var normal := Direction.to_vector(wall.inward)
		if not (room.cleared and _has_door(room, wall)):
			_solids.append(_half_plane(normal, floor_area))
			continue
		var past_edge := absf(player_size.dot(normal))
		_solids.append(_half_plane(normal, arena.grow(past_edge)))
		for piece in wall.pieces_beside_gap:
			var far_behind := piece.get_center() - normal * arena.size.length()
			_solids.append(_box(piece.expand(far_behind)))


## Moves [param body] by [param offset], then pushes it back out of every
## wall it overlaps, so it slides along them. A [param push] slides the
## whole way: what the walls cut off its length is added along them.
## Returns whether a wall stopped it.
func move(body: Body, offset: Vector2, push := false) -> bool:
	var start := body.pos
	body.pos += offset
	var out := _push_out(body)
	if not push or out.is_zero_approx():
		return not out.is_zero_approx()
	var normal := out.normalized()
	var along := offset - normal * offset.dot(normal)
	# Straight into a wall, it slides counterclockwise around the room as
	# seen on screen; the direction is an arbitrary choice.
	var tangent := along.normalized() if not along.is_zero_approx() else -normal.orthogonal()
	body.pos += tangent * (offset.length() - body.pos.distance_to(start))
	_push_out(body)
	return true


## Pushes [param body] out of every wall it overlaps. Returns how far it
## moved.
func _push_out(body: Body) -> Vector2:
	var start := body.pos
	for solid in _solids:
		# Pairs of points: one on the body, then the matching one on the wall.
		var contacts := body.collider.collide_and_get_contacts(
				body.collider_transform(), solid.shape, solid.at)
		var deepest := Vector2.ZERO
		for k in range(0, contacts.size(), 2):
			var out := contacts[k + 1] - contacts[k]
			if out.length_squared() > deepest.length_squared():
				deepest = out
		body.pos += deepest
	return body.pos - start


## A shape bodies can't overlap, placed at [member at].
class Solid:
	var shape: Shape2D
	var at := Transform2D.IDENTITY
