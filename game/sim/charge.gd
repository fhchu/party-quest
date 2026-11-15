extends RefCounted
## A dummy's charge, from its kind's charge attack with durations in ticks,
## and the charge in progress.

const Charge := preload("res://sim/charge.gd")
const ChargeAttack := preload("res://shared/data/attacks/charge_attack.gd")
const GameTime := preload("res://shared/game_time.gd")
const Actor := preload("res://sim/actor.gd")

## From its aim lock to the charge.
var aim_lock_ticks := 0
## How far it moves the dummy each tick, in px.
var step := 0.0
## How far a whole charge moves the dummy, in px.
var length := 0.0
## Set when it locks.
var direction := Vector2.ZERO
## Left of the charge in progress, in px; 0 for none.
var px_left := 0.0
## After a charge, how long the dummy walks [member cooldown_walk_step] a
## tick instead of its own step.
var cooldown_ticks := 0
## In px.
var cooldown_walk_step := 0.0
## Left of the cooldown in progress; 0 for none.
var cooldown_ticks_left := 0


static func from_attack(attack: ChargeAttack) -> Charge:
	var charge := Charge.new()
	charge.aim_lock_ticks = GameTime.ticks(attack.aim_lock_sec)
	charge.step = attack.speed * GameTime.TICK_SEC
	charge.length = attack.length
	charge.cooldown_ticks = GameTime.ticks(attack.cooldown_sec)
	charge.cooldown_walk_step = attack.cooldown_walk_speed * GameTime.TICK_SEC
	return charge


## Whether a whole charge by [param charger] along [param heading] would
## touch [param target].
func reaches(charger: Actor, heading: Vector2, target: Actor) -> bool:
	return charger.collider.collide_with_motion(
			Transform2D(heading.angle(), charger.pos), heading * length,
			target.collider, target.collider_transform(), Vector2.ZERO)


func start() -> void:
	px_left = length


## Its move this tick.
func offset() -> Vector2:
	return direction * minf(step, px_left)


## Counts this tick's move off. Returns whether the charge is over.
func advance() -> bool:
	px_left -= step
	return px_left <= 0


## Ends the charge in progress and starts the cooldown.
func stop() -> void:
	px_left = 0.0
	cooldown_ticks_left = cooldown_ticks


func is_cooling_down() -> bool:
	return cooldown_ticks_left > 0
