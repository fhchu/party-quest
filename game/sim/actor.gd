extends "res://sim/body.gd"
## What players and dummies share: a body that can be hurt and pushed. Its
## collider is its hurtbox. It changes only itself; the world decides who
## touches whom and where it can go.


## Its hurtbox's size, in px.
var size: Vector2:
	get:
		return _box.size
	set(value):
		_box.size = value
var health := 0
var knockback := Knockback.new()

var _box := RectangleShape2D.new()


func _init() -> void:
	collider = _box


func is_pushed() -> bool:
	return knockback.ticks > 0


## The knockback step while pushed.
func offset_this_tick() -> Vector2:
	return knockback.step if is_pushed() else Vector2.ZERO


## Starts a push of [param offset] px over [param ticks]. A 0-tick push is
## the world's to apply at once. Returns whether it took the push.
func push(offset: Vector2, ticks: int) -> bool:
	if ticks == 0:
		knockback.ticks = 0
		return true
	knockback.step = offset / ticks
	knockback.ticks = ticks
	return true


## Takes [param amount] health, stopping at 0. Returns whether it hurt.
func take_damage(amount: int) -> bool:
	health = maxi(health - amount, 0)
	return true


## Counts down the push in progress.
func _count_down_push() -> void:
	knockback.ticks -= 1


## A push in progress: px per tick, and ticks of it left (0 when not being
## pushed).
class Knockback:
	var step := Vector2.ZERO
	var ticks := 0
