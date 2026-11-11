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


func step() -> void:
	if is_pushed():
		_step_push()


func is_destroyed() -> bool:
	return damageable and health <= 0
