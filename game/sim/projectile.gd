extends RefCounted
## A shot in flight: a circle moving in a straight line. It has no hurtbox,
## so nothing can hit it; the world removes it when it touches a living
## player or a wall.

const GameTime := preload("res://shared/game_time.gd")
const World := preload("res://sim/world.gd")
const Actor := preload("res://sim/actor.gd")

## Unique within its world, so clients can follow it from snapshot to
## snapshot.
var id := 0
## Its center.
var pos := Vector2.ZERO
## In px/s.
var velocity := Vector2.ZERO
## In px.
var radius: float:
	get:
		return _shape.radius
	set(value):
		_shape.radius = value
## Health it takes from the player it touches.
var damage := 0
## How far it pushes that player away, in px, and over how long.
var push_px := 0.0
var push_ticks := 0

var _shape := CircleShape2D.new()


func step() -> void:
	pos += velocity * GameTime.TICK_SEC


func touches(actor: Actor) -> bool:
	return actor.touches(_shape, Transform2D(0.0, pos))


## Whether it touches a wall of [param arena].
func is_at_wall(arena: Rect2) -> bool:
	return not arena.grow(-radius).has_point(pos)
