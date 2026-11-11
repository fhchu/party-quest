extends "res://sim/actor.gd"
## A target in the arena. What it does comes from its attributes, which
## [method World._add_dummy] sets from its kind; the defaults are an inert
## dummy.

const Snapshot := preload("res://net/snapshot.gd")

## Unique within its world, so clients can follow it from snapshot to
## snapshot.
var id := 0
var kind := World.Kind.READY
## What a swing touching it asks the room to do.
var on_hit := World.OnHit.NOTHING
## Whether swings take health from it. A damageable dummy at 0 health is
## destroyed.
var damageable := false
var pushed_by_swings := false
## Health a player loses touching it; 0 for none.
var contact_damage := 0
## How far touching it pushes a player away, in px, and over how long.
var contact_push_px := 0.0
var contact_push_ticks := 0
## Between shots; 0 for a dummy that never shoots. The first comes one
## interval after it spawns.
var fire_interval_ticks := 0
## How long before each shot it locks onto where its target is. It fires
## at that spot, not at where the target is by then.
var aim_lock_ticks := 0
## How fast it turns toward its target, in radians per second.
var turn_rate := 0.0
## Its shots' radius, in px.
var projectile_radius := 0.0
## In px/s.
var projectile_speed := 0.0
## Health a player loses to one of its shots. They push like touching it.
var projectile_damage := 0
## Its hurtbox turns with it, about its center.
# PLACEHOLDER (design): toward the players' spawn row.
var facing := Vector2.DOWN
## Until the next shot.
var fire_ticks_left := 0
## Where it will fire, set when the aim locks.
var aim_spot := Vector2.ZERO
## The tick a swing last touched it. It starts far enough back to read as
## never struck.
var struck_tick := -Snapshot.STRUCK_LONG_AGO


## A swing touched it on [param at_tick]: it takes [param damage] if
## damageable and is pushed by [param offset] px over [param ticks] if
## pushed by swings.
func take_hit(damage: int, offset: Vector2, ticks: int, at_tick: int) -> void:
	struck_tick = at_tick
	if damageable:
		take_damage(damage)
	if pushed_by_swings:
		push(offset, ticks)


## One tick: it rides its push, turns toward [param target] (null for
## none) or the locked spot, and counts down to its shot. Returns whether it
## fires now, toward [member aim_spot]. With no target when the aim would
## lock, it skips that shot and starts the next interval.
func step(target: Actor) -> bool:
	if is_pushed():
		_step_push()
	if fire_interval_ticks == 0:
		return false
	fire_ticks_left -= 1
	if fire_ticks_left == aim_lock_ticks:
		if target:
			aim_spot = target.pos
		else:
			fire_ticks_left = fire_interval_ticks
	if is_aim_locked():
		_turn_toward(aim_spot)
	elif target:
		_turn_toward(target.pos)
	if fire_ticks_left > 0:
		return false
	fire_ticks_left = fire_interval_ticks
	return true


## Turned with its facing.
func hurtbox_transform() -> Transform2D:
	return Transform2D(facing.angle(), pos)


func is_aim_locked() -> bool:
	return fire_interval_ticks > 0 and fire_ticks_left <= aim_lock_ticks


func is_destroyed() -> bool:
	return damageable and health <= 0


func _turn_toward(spot: Vector2) -> void:
	var to := spot - pos
	if to.is_zero_approx():
		return
	facing = Vector2.from_angle(rotate_toward(facing.angle(), to.angle(), turn_rate * World.DT))
	# Turning beside a wall can swing a corner past it.
	_move_within_arena(Vector2.ZERO)
