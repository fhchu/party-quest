extends RefCounted
## A shot in flight: a circle moving in a straight line. It has no hurtbox,
## so nothing can hit it; the world removes it when it touches a standing
## player or a wall.

const World := preload("res://sim/world.gd")

## Unique within its world, so clients can follow it from snapshot to
## snapshot.
var id := 0
## Its center.
var pos := Vector2.ZERO
## In px/s.
var velocity := Vector2.ZERO
## In px.
var radius := 0.0
## Health it takes from the player it touches.
var damage := 0
## How far it pushes that player away, in px, and over how long.
var push_px := 0.0
var push_ticks := 0


func step() -> void:
	pos += velocity * World.DT


func touches(box: Rect2) -> bool:
	return pos.distance_to(pos.clamp(box.position, box.end)) <= radius


## Whether it touches a wall of [param arena].
func is_at_wall(arena: Rect2) -> bool:
	return not arena.grow(-radius).has_point(pos)
