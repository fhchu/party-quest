class_name Direction
extends RefCounted
## The four ways across a room: which wall something is in, and which way a
## player faces.

## Clockwise from north, so opposite ways are two apart.
enum Cardinal {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

# Indexed by Cardinal.
const _VECTORS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]


## The way across from [param way].
static func opposite(way: Cardinal) -> Cardinal:
	return (way + 2) % Cardinal.size() as Cardinal


## A unit vector pointing [param way].
static func to_vector(way: Cardinal) -> Vector2:
	return _VECTORS[way]
