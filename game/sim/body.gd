extends RefCounted
## Something in the arena with a collider: walls stop it, and the world
## tests what it touches. It never moves itself; it says how far it means
## to go, and the world moves it.

const Body := preload("res://sim/body.gd")

## The center of its collider.
var pos := Vector2.ZERO
## Placed by [method collider_transform].
var collider: Shape2D


## Straight from [param from] to [param point], or along [param fallback]
## when exactly on top of it.
static func direction_away(point: Vector2, from: Vector2, fallback: Vector2) -> Vector2:
	var away := point - from
	return away.normalized() if not away.is_zero_approx() else fallback


## Where its collider is: on [member pos], upright.
func collider_transform() -> Transform2D:
	return Transform2D(0.0, pos)


## Whether [param shape] placed at [param at] overlaps its collider. Shapes
## that only touch at an edge count.
func touches(shape: Shape2D, at: Transform2D) -> bool:
	return collider.collide(collider_transform(), shape, at)


func touches_body(other: Body) -> bool:
	return touches(other.collider, other.collider_transform())


## How far it means to move this tick, in px.
func offset_this_tick() -> Vector2:
	return Vector2.ZERO
