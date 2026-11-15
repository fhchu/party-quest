extends RefCounted
## A swing's reach: a pie slice around where it starts, pointing along +x,
## cut into pieces under half a turn each, since a fan of half a turn or
## more isn't convex. The server hits with the pieces and the client draws
## them, so both build them here.

## Straight edges along the curved side of a whole turn: enough that a
## slice looks round.
const SEGMENTS_PER_TURN := 32


## The pieces of a slice [param arc] radians wide and [param radius] px
## long, side by side from one edge to the other. Each is a fan of points
## from (0, 0).
static func pieces(radius: float, arc: float) -> Array[PackedVector2Array]:
	var count := floori(arc / PI) + 1
	var piece_arc := arc / count
	var segments := maxi(1, ceili(piece_arc / TAU * SEGMENTS_PER_TURN))
	var out: Array[PackedVector2Array] = []
	for i in count:
		var first := -arc / 2 + piece_arc * i
		var points := PackedVector2Array([Vector2.ZERO])
		for j in segments + 1:
			points.append(Vector2.from_angle(first + piece_arc * j / segments) * radius)
		out.append(points)
	return out
