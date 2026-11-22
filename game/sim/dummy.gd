extends "res://sim/actor.gd"
## A target in the arena. What it does comes from its attributes, which
## [method WorldSimulator._add_dummy] sets from its kind; the defaults are an
## inert dummy.

const Actor := preload("res://sim/actor.gd")
const Dummy := preload("res://sim/dummy.gd")
const RoomPaths := preload("res://sim/room_paths.gd")
const Fire := preload("res://sim/fire.gd")
const Charge := preload("res://sim/charge.gd")
const AttackChoice := preload("res://sim/attack_choice.gd")

## What it's doing. Only an IDLE dummy walks or locks its aim.
enum State {
	IDLE,
	## Its aim is locked; it attacks when [member lock_ticks_left] runs out.
	AIMING,
	## Moving along its charge's direction until the charge is used up or a
	## wall stops it.
	CHARGING,
}

## What it does when its aim locks.
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
## From the start of one aim lock to the next. The first lock comes one
## interval after it spawns.
var attack_interval_ticks := 0
## Its kind's attacks in list order, each a Fire or its [member charge].
## With none, it never turns or walks.
var attacks: Array[RefCounted] = []
## One per attack.
var weights := PackedFloat32Array()
var attack_rule := AttackChoice.Rule.WEIGHTED_VALID
## Null if it doesn't charge.
var charge: Charge
## The shot its aim last locked for; null before any.
var fire: Fire
## The attack after the one its aim last locked for: the one CYCLE makes
## next.
var next_in_cycle := 0
## How far it turns toward its target each tick, in radians.
var turn_step := 0.0
## How far it walks toward its target each tick while IDLE, in px.
var walk_step := 0.0
## A walking dummy steers away from any other whose edge is closer than
## this to its own, in px.
var personal_space := 0.0
## Its hurtbox turns with it, about its center. It starts toward the players'
## spawn row.
var facing := Vector2.DOWN
var state := State.IDLE
## Until its next aim lock, counted in every state. At 0 it locks as soon
## as it's IDLE and its attack is ready for its target.
var attack_ticks_left := 0
## Set when the aim locks.
var locked_attack := Attack.NONE
## Until the locked attack, while AIMING.
var lock_ticks_left := 0
## Where it attacks toward, set when the aim locks. It attacks toward that
## spot, not toward where the target is by then.
var aim_spot := Vector2.ZERO
## Its walk this tick, set by [method step]: a unit vector, or zero.
var move := Vector2.ZERO
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
## [param others] are the dummies it keeps its distance from and walks
## around; it skips itself. [param paths] finds its way around them.
## [param rng] makes its random choices.
func step(target: Actor, others: Array[Dummy], paths: RoomPaths,
		rng: RandomNumberGenerator) -> bool:
	if is_pushed():
		_count_down_push()
	move = Vector2.ZERO
	if attacks.is_empty():
		return false
	if attack_ticks_left > 0:
		attack_ticks_left -= 1
	if charge and charge.is_cooling_down():
		charge.cooldown_ticks_left -= 1
	match state:
		State.CHARGING:
			if charge.advance():
				end_charge()
			return false
		State.IDLE:
			if attack_ticks_left == 0:
				_lock_if_ready(target, rng)
			# With no aim lock time, it attacks on the tick it locks.
			if state == State.IDLE:
				_chase(target, others, paths)
				return false
		State.AIMING:
			lock_ticks_left -= 1
	return _aim_or_attack()


## Carried by its charge, or by a push, or by its walk.
func offset_this_tick() -> Vector2:
	if state == State.CHARGING:
		return charge.offset()
	if is_pushed():
		return super.offset_this_tick()
	return move * _walk_step()


## Nothing pushes it while it charges.
func push(offset: Vector2, ticks: int) -> bool:
	if state == State.CHARGING:
		return false
	return super.push(offset, ticks)


## Which way it pushes a player at [param target] that it touches: straight
## away; while it charges, square to the charge, to whichever side of its
## line the player is on.
func contact_push_direction(target: Vector2) -> Vector2:
	if state != State.CHARGING:
		return direction_away(target, pos, Vector2.RIGHT)
	# The charge's right, as seen on screen.
	var right := -charge.direction.orthogonal()
	# To the charge's right if exactly on its line.
	return -right if charge.direction.cross(target - pos) < 0 else right


func end_charge() -> void:
	state = State.IDLE
	charge.stop()


## Turned with its facing.
func collider_transform() -> Transform2D:
	return Transform2D(facing.angle(), pos)


func is_aim_locked() -> bool:
	return state == State.AIMING


func is_destroyed() -> bool:
	return damageable and health <= 0


## How far it walks a tick. While its charge cools down, it speeds up
## steadily from the charge's cooldown step back to its own.
func _walk_step() -> float:
	if not charge or not charge.is_cooling_down():
		return walk_step
	var cooled := 1.0 - float(charge.cooldown_ticks_left) / charge.cooldown_ticks
	return lerpf(charge.cooldown_walk_step, walk_step, cooled)


## Turns toward the spot a shot will go, and attacks once the aim lock is
## over. Returns whether it fires now.
func _aim_or_attack() -> bool:
	# A charge's facing snapped when it locked.
	if locked_attack == Attack.FIRE:
		_turn_toward(aim_spot)
	if lock_ticks_left > 0:
		return false
	if locked_attack == Attack.FIRE:
		state = State.IDLE
		return true
	state = State.CHARGING
	charge.start()
	knockback.ticks = 0
	return false


## Locks onto [param target] for the attack its [member attack_rule]
## picks, if any. A charge can be made now if it would reach; a shot always
## can. With no target, it skips this attack instead.
func _lock_if_ready(target: Actor, rng: RandomNumberGenerator) -> void:
	if not target:
		attack_ticks_left = attack_interval_ticks
		return
	var heading := _toward(target.pos)
	var usable: Array[bool] = []
	for attack in attacks:
		usable.append(attack != charge or charge.reaches(self, heading, target))
	var picked := AttackChoice.pick(attack_rule, weights, usable, next_in_cycle, rng)
	if picked < 0:
		return
	next_in_cycle = (picked + 1) % attacks.size()
	if attacks[picked] == charge:
		locked_attack = Attack.CHARGE
		lock_ticks_left = charge.aim_lock_ticks
		charge.direction = heading
		facing = heading
	else:
		locked_attack = Attack.FIRE
		fire = attacks[picked]
		lock_ticks_left = fire.aim_lock_ticks
	state = State.AIMING
	aim_spot = target.pos
	attack_ticks_left = attack_interval_ticks


## Turns toward [param target] and, if it walks, heads for it, around any
## of [param others] in the way, steering away from each one inside its
## personal space: the closer, the harder.
func _chase(target: Actor, others: Array[Dummy], paths: RoomPaths) -> void:
	if not target:
		return
	_turn_toward(target.pos)
	if walk_step == 0:
		return
	var heading := _toward(_walk_goal(target, others, paths))
	for other in others:
		if other == self:
			continue
		var gap := pos.distance_to(other.pos) - footprint_radius() - other.footprint_radius()
		if gap < personal_space:
			heading += _away_from(other) * (1.0 - gap / personal_space)
	move = heading.normalized()


## Straight at [param target] when nothing is in the way, else the next
## point on a way around. A dummy's personal space blocks the way; a
## charging dummy's doesn't, and one it's already inside is left to
## steering.
func _walk_goal(target: Actor, others: Array[Dummy], paths: RoomPaths) -> Vector2:
	var blockers: Array[RoomPaths.Blocker] = []
	for other in others:
		if other == self or other.state == State.CHARGING:
			continue
		var blocker := RoomPaths.Blocker.new()
		blocker.center = other.pos
		blocker.radius = footprint_radius() + other.footprint_radius() + personal_space
		if pos.distance_to(blocker.center) >= blocker.radius:
			blockers.append(blocker)
	var in_the_way := blockers.any(func(b: RoomPaths.Blocker) -> bool:
		var nearest := Geometry2D.get_closest_point_to_segment(b.center, pos, target.pos)
		return nearest.distance_to(b.center) < b.radius)
	return paths.next_point(pos, target.pos, blockers) if in_the_way else target.pos


## The smallest circle around its hurtbox, in px: how far its edge is from
## its center, whichever way it faces.
func footprint_radius() -> float:
	if collider is CircleShape2D:
		return (collider as CircleShape2D).radius
	return collider.get_rect().size.length() / 2


## The unit vector from [param other] to it. On top of each other, the two
## go opposite ways across its facing, by ID.
func _away_from(other: Dummy) -> Vector2:
	var away := pos - other.pos
	if not away.is_zero_approx():
		return away.normalized()
	return facing.orthogonal() * (1 if id < other.id else -1)


## The unit vector toward [param spot]; its facing when on top of it.
func _toward(spot: Vector2) -> Vector2:
	var to := spot - pos
	return to.normalized() if not to.is_zero_approx() else facing


func _turn_toward(spot: Vector2) -> void:
	var to := spot - pos
	if to.is_zero_approx():
		return
	facing = Vector2.from_angle(rotate_toward(facing.angle(), to.angle(), turn_step))
