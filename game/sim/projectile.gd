extends "res://sim/body.gd"
## A shot in flight: a circle moving in a straight line. It has no hurtbox,
## so nothing can hit it; the world removes it when it touches a living
## player or a wall.

## Unique within its world, so clients can follow it from snapshot to
## snapshot.
var id := 0
## How far it flies each tick, in px.
var step := Vector2.ZERO
## In px.
var radius: float:
	get:
		return _circle.radius
	set(value):
		_circle.radius = value
## Health it takes from the player it touches.
var damage := 0
## How far it pushes that player away, in px, and over how long.
var push_px := 0.0
var push_ticks := 0

var _circle := CircleShape2D.new()


func _init() -> void:
	collider = _circle


func offset_this_tick() -> Vector2:
	return step
