extends RefCounted
## What players and dummies share: a body in the arena that can be hurt and
## pushed. It changes only itself; the world decides who touches whom.

const World := preload("res://sim/world.gd")
const GameTime := preload("res://shared/game_time.gd")
const DataLoader := preload("res://shared/data_loader.gd")
const Actor := preload("res://sim/actor.gd")

## The center of its hurtbox.
var pos: Vector2
## Its hurtbox's size, in px.
var size: Vector2:
	get:
		return hurtbox_shape.size
	set(value):
		hurtbox_shape.size = value
var health := 0
var knockback := Knockback.new()
## Centered on [member pos], placed by [method hurtbox_transform].
var hurtbox_shape := RectangleShape2D.new()


## Where its hurtbox is: on [member pos], upright.
func hurtbox_transform() -> Transform2D:
	return Transform2D(0.0, pos)


## Whether [param shape] placed at [param at] overlaps its hurtbox. Shapes
## that only touch at an edge count.
func touches(shape: Shape2D, at: Transform2D) -> bool:
	return hurtbox_shape.collide(hurtbox_transform(), shape, at)


func touches_actor(other: Actor) -> bool:
	return touches(other.hurtbox_shape, other.hurtbox_transform())


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


## Moves it by [param offset], keeping its whole hurtbox, turned or not,
## inside the arena.
func _move_within_arena(offset: Vector2) -> void:
	# The upright box around the turned hurtbox.
	var turn := Transform2D(hurtbox_transform().get_rotation(), Vector2.ZERO)
	var area := World.walkable((turn * Rect2(-size / 2, size)).size)
	pos = (pos + offset).clamp(area.position, area.end)


## A push in progress: px per tick, and ticks of it left (0 when not being
## pushed).
class Knockback:
	var step := Vector2.ZERO
	var ticks := 0
