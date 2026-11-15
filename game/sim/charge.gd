extends RefCounted
## A dummy's charge, from its kind's charge attack with durations in ticks
## (see [method WorldLoader.new_dummy]), and the charge in progress.

const Actor := preload("res://sim/actor.gd")

## From its aim lock to the charge.
var aim_lock_ticks := 0
## How far it moves the dummy each tick before it brakes, in px.
var step := 0.0
## How much slower each braking tick is than the last, in px.
var brake_slowdown := 0.0
## The slowest a braking tick goes, in px.
var brake_end_step := 0.0
## From the end of the charge, where braking starts, in px.
var brake_px := 0.0
## How far a whole charge moves the dummy, in px.
var length := 0.0
## Set when it locks.
var direction := Vector2.ZERO
## Left of the charge in progress, in px; 0 for none.
var px_left := 0.0
## How far this tick of the charge moves the dummy, in px.
var step_now := 0.0
## After a charge, how long the dummy takes to speed up steadily from
## [member cooldown_walk_step] a tick back to its own step.
var cooldown_ticks := 0
## In px.
var cooldown_walk_step := 0.0
## Left of the cooldown in progress; 0 for none.
var cooldown_ticks_left := 0


## Whether a whole charge by [param charger] along [param heading] would
## touch [param target].
func reaches(charger: Actor, heading: Vector2, target: Actor) -> bool:
	return charger.collider.collide_with_motion(
			Transform2D(heading.angle(), charger.pos), heading * length,
			target.collider, target.collider_transform(), Vector2.ZERO)


func start() -> void:
	px_left = length
	step_now = step


## Its move this tick.
func offset() -> Vector2:
	return direction * minf(step_now, px_left)


## Counts this tick's move off, and slows the next once it's braking.
## Returns whether the charge is over.
func advance() -> bool:
	px_left -= step_now
	if px_left <= 0:
		return true
	if px_left <= brake_px:
		# The speed a steady slowdown leaves this far from the end. Set by the
		# distance left, not by ticks, so even braking to a stop it ends:
		# near enough to the end, one step covers the rest.
		step_now = minf(step, sqrt(
				brake_end_step * brake_end_step + 2 * brake_slowdown * px_left))
	return false


## Ends the charge in progress and starts the cooldown.
func stop() -> void:
	px_left = 0.0
	cooldown_ticks_left = cooldown_ticks


func is_cooling_down() -> bool:
	return cooldown_ticks_left > 0
