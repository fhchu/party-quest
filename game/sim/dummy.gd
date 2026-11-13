extends "res://sim/actor.gd"
## A target in the arena. What it does comes from its attributes, which
## [method World._add_dummy] sets from its kind; the defaults are an inert
## dummy.

const Actor := preload("res://sim/actor.gd")
const DummyKind := preload("res://shared/data/dummy_kind.gd")

## What it's doing. Only an IDLE dummy walks or counts down to its aim lock.
enum State {
	IDLE,
	## Its aim is locked; it attacks when [member attack_ticks_left] runs out.
	AIMING,
	## Moving along [member charge_direction] until [member charge_px_left]
	## is used up or a wall stops it.
	CHARGING,
}

## What it does when its aim locks; NONE while a charger waits for reach.
enum Attack {
	NONE,
	FIRE,
	CHARGE,
}

## [member struck_tick] before any swing touches it: far enough back that
## every tick reads as long after it.
const NEVER_STRUCK := -0x7fffffff

## Unique within its world, so clients can follow it from snapshot to
## snapshot.
var id := 0
## Its number in shared/data/dummy_kinds.tres.
var kind := 0
## What a swing touching it asks the lobby to do, by a name the world
## never reads; empty for nothing.
var on_hit := ""
## Whether swings take health from it. A damageable dummy at 0 health is
## destroyed.
var damageable := false
var pushed_by_swings := false
## Health a player loses touching it; 0 for none.
var contact_damage := 0
## How far touching it pushes a player away, in px, and over how long.
var contact_push_px := 0.0
var contact_push_ticks := 0
## Between attacks, from the end of one to the next; 0 for a dummy that
## never attacks. The first comes one interval after it spawns.
var attack_interval_ticks := 0
## Which attack it makes when its aim locks.
var attack_choice := DummyKind.AttackChoice.FIRE
## How long before each attack it locks onto where its target is. It
## attacks toward that spot, not toward where the target is by then.
var aim_lock_ticks := 0
## How far it turns toward its target each tick, in radians.
var turn_step := 0.0
## Its shots' radius, in px.
var projectile_radius := 0.0
## In px/s.
var projectile_speed := 0.0
## Health a player loses to one of its shots. They push like touching it.
var projectile_damage := 0
## How far it walks toward its target each tick while IDLE, in px.
var walk_step := 0.0
## How far a charge moves it each tick, in px.
var charge_step := 0.0
## How far a whole charge moves it, in px. A target whose edge is this close
## to its edge, along the line between them, is in reach.
var charge_length := 0.0
## Its hurtbox turns with it, about its center.
# PLACEHOLDER (design): toward the players' spawn row.
var facing := Vector2.DOWN
var state := State.IDLE
## Until the next attack. An IDLE dummy holds at [member aim_lock_ticks]
## while it waits for its target to be in reach.
var attack_ticks_left := 0
## Set when the aim locks.
var locked_attack := Attack.NONE
## Where it will fire, set when the aim locks.
var aim_spot := Vector2.ZERO
## Its walk this tick, set by [method step]: a unit vector, or zero.
var move := Vector2.ZERO
## Set when a charge locks, along with its facing.
var charge_direction := Vector2.ZERO
## Left of the charge in progress, in px.
var charge_px_left := 0.0
## The tick a swing last touched it.
var struck_tick := NEVER_STRUCK


## A swing touched it on [param at_tick]: it takes [param damage] if
## damageable. The world pushes it if [member pushed_by_swings].
func take_hit(damage: int, at_tick: int) -> void:
	struck_tick = at_tick
	if damageable:
		take_damage(damage)


## One tick: it counts down its push, and, if it attacks, turns, walks and
## counts down to its next attack. Returns whether it fires now, toward
## [member aim_spot]. [param target] is null for none; with no target when
## the aim would lock, it skips that attack and starts the next interval.
func step(target: Actor) -> bool:
	if is_pushed():
		_count_down_push()
	move = Vector2.ZERO
	if attack_interval_ticks == 0:
		return false
	match state:
		State.CHARGING:
			_advance_charge()
			return false
		State.IDLE:
			_step_idle(target)
			# With no aim lock time, it attacks on the tick it locks.
			if state == State.IDLE:
				return false
		State.AIMING:
			attack_ticks_left -= 1
	return _aim_or_attack()


## Carried by its charge, or by a push, or by its walk.
func offset_this_tick() -> Vector2:
	if state == State.CHARGING:
		return charge_direction * minf(charge_step, charge_px_left)
	if is_pushed():
		return super.offset_this_tick()
	return move * walk_step


## Nothing pushes it while it charges.
func push(offset: Vector2, ticks: int) -> bool:
	if state == State.CHARGING:
		return false
	return super.push(offset, ticks)


## The charge in progress is over; the next attack is an interval away.
func end_charge() -> void:
	state = State.IDLE
	charge_px_left = 0.0
	attack_ticks_left = attack_interval_ticks


## Turned with its facing.
func collider_transform() -> Transform2D:
	return Transform2D(facing.angle(), pos)


func is_aim_locked() -> bool:
	return state == State.AIMING


func is_destroyed() -> bool:
	return damageable and health <= 0


## Counts down to its aim lock, holding there until it locks, and chases
## [param target] while it doesn't.
func _step_idle(target: Actor) -> void:
	if attack_ticks_left > aim_lock_ticks:
		attack_ticks_left -= 1
	if attack_ticks_left == aim_lock_ticks:
		_lock_if_ready(target)
	if state == State.IDLE:
		_chase(target)


## Turns toward the spot a shot will go, and attacks once the aim lock is
## over. Returns whether it fires now.
func _aim_or_attack() -> bool:
	# A charge's facing snapped when it locked.
	if locked_attack == Attack.FIRE:
		_turn_toward(aim_spot)
	if attack_ticks_left > 0:
		return false
	if locked_attack == Attack.FIRE:
		state = State.IDLE
		attack_ticks_left = attack_interval_ticks
		return true
	state = State.CHARGING
	charge_px_left = charge_length
	knockback.ticks = 0
	return false


func _advance_charge() -> void:
	charge_px_left -= charge_step
	if charge_px_left <= 0:
		end_charge()


## Locks onto [param target] if its attack is ready for it. With no target,
## it skips this attack instead.
func _lock_if_ready(target: Actor) -> void:
	if not target:
		attack_ticks_left = attack_interval_ticks
		return
	var reaches := _charge_reaches(target)
	match attack_choice:
		DummyKind.AttackChoice.FIRE:
			locked_attack = Attack.FIRE
		DummyKind.AttackChoice.CHARGE:
			locked_attack = Attack.CHARGE if reaches else Attack.NONE
		DummyKind.AttackChoice.BY_RANGE:
			locked_attack = Attack.CHARGE if reaches else Attack.FIRE
	if locked_attack == Attack.NONE:
		return
	state = State.AIMING
	aim_spot = target.pos
	if locked_attack == Attack.CHARGE:
		charge_direction = _toward(target.pos)
		facing = charge_direction


## Whether a whole charge straight at [param target] would touch it.
func _charge_reaches(target: Actor) -> bool:
	var direction := _toward(target.pos)
	return collider.collide_with_motion(
			Transform2D(direction.angle(), pos), direction * charge_length,
			target.collider, target.collider_transform(), Vector2.ZERO)


## Turns toward [param target] and, if it walks, heads for it.
func _chase(target: Actor) -> void:
	if not target:
		return
	_turn_toward(target.pos)
	if walk_step > 0:
		move = (target.pos - pos).normalized()


## The unit vector toward [param spot]; its facing when on top of it.
func _toward(spot: Vector2) -> Vector2:
	var to := spot - pos
	return to.normalized() if not to.is_zero_approx() else facing


func _turn_toward(spot: Vector2) -> void:
	var to := spot - pos
	if to.is_zero_approx():
		return
	facing = Vector2.from_angle(rotate_toward(facing.angle(), to.angle(), turn_step))
