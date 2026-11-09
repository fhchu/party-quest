extends RefCounted
## What players and dummies share: a body in the arena that can be hurt and
## pushed. It changes only itself; the world decides who touches whom.

const World := preload("res://sim/world.gd")
const Tuning := preload("res://sim/tuning.gd")

## The center of its hurtbox.
var pos: Vector2
## Its hurtbox's size, in px.
var size: Vector2
var health := 0
var knockback := Knockback.new()


func hurtbox() -> Rect2:
	return World.hurtbox(pos, size)


func is_pushed() -> bool:
	return knockback.ticks > 0


## Pushes it by [param offset] px over [param ticks]; 0 ticks moves it at
## once.
func push(offset: Vector2, ticks: int) -> void:
	if ticks == 0:
		knockback.ticks = 0
		_move_within_arena(offset)
		return
	knockback.step = offset / ticks
	knockback.ticks = ticks


## Takes [param amount] health, stopping at 0. Returns whether it hurt.
func take_damage(amount: int) -> bool:
	health = maxi(health - amount, 0)
	return true


## One tick of the push in progress.
func _step_push() -> void:
	knockback.ticks -= 1
	_move_within_arena(knockback.step)


func _move_within_arena(offset: Vector2) -> void:
	var area := World.walkable(size)
	pos = (pos + offset).clamp(area.position, area.end)


## A push in progress: px per tick, and ticks of it left (0 when not being
## pushed).
class Knockback:
	var step := Vector2.ZERO
	var ticks := 0
