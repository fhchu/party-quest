extends RefCounted
## A unit's shot, from its unit type's fire attack with durations in ticks
## (see [method WorldLoader.new_unit]). The world fires it toward the
## unit's locked aim.

const Actor := preload("res://sim/actor.gd")

## From its aim lock to the shot.
var aim_lock_ticks := 0
## In px.
var radius := 0.0
## How far the shot moves each tick, in px.
var step := 0.0
## Health a player loses to the shot.
var damage := 0
## How far the shot pushes the player it hits, in px, and over how long.
var push_px := 0.0
var push_ticks := 0
## Whether it goes only up, down, left or right: along [method nearest_axis]
## to the target's direction when the aim locks.
var cardinal_only := false


## The unit vector along x or y nearest [param direction]; along x when
## they're as near.
static func nearest_axis(direction: Vector2) -> Vector2:
	if absf(direction.x) >= absf(direction.y):
		return Vector2(signf(direction.x), 0)
	return Vector2(0, signf(direction.y))


## Whether a shot by [param shooter], its aim locking along [param heading]
## toward [param target], would touch the target if the target stayed put.
## Only a cardinal-only shot can miss.
func reaches(shooter: Actor, heading: Vector2, target: Actor) -> bool:
	if not cardinal_only:
		return true
	var axis := nearest_axis(heading)
	var shot := CircleShape2D.new()
	shot.radius = radius
	# As far along the axis as the target is.
	var distance := axis.dot(target.pos - shooter.pos)
	return shot.collide_with_motion(Transform2D(0, shooter.pos), axis * distance,
			target.collider, target.collider_transform(), Vector2.ZERO)
