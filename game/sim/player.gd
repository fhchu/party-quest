extends "res://sim/actor.gd"
## A player's character: an actor its player steers and uses items with.

const Action := preload("res://sim/action.gd")
const HitArea := preload("res://sim/hit_area.gd")
const InputActionState := preload("res://sim/input_action_state.gd")

## Movement snaps to what four keys can make: each cardinal and each
## diagonal between two.
const DIRECTIONS := len(Direction.Cardinal) * 2
const DIRECTION_STEP := TAU / DIRECTIONS

# WorldLoader converts the values below to ticks for the fields that count
# in ticks.
## How fast it walks, in px/s.
static var walk_speed := 160.0
## After damage or an invulnerable heal, how long no damage can hurt it.
static var invulnerable_sec := 0.5

## The seat number.
var id: int
# What it can do: [method WorldSimulator.add_player] sets these, from the
# static variables above and from balance.tres.
## How far it walks each tick, in px.
var walk_step := 0.0
## Health is never healed above this.
var max_health := 0
## How long no damage can hurt them after damage or an invulnerable heal.
var invulnerable_duration_ticks := 0
var facing := Direction.Cardinal.EAST
var move := Vector2.ZERO
## One per input action its client reports, in that order; the first ones
## use the item slots. Filled in by its first input.
var input_actions: Array[InputActionState] = []
var connected := true
## Left in which no damage can hurt them, after they were last hurt.
var invulnerable_ticks := 0
## What using each of its holder's two item slots does, null for an empty
## slot. The lobby sets them from its holder's player data.
var slot_actions: Array[Action] = []


## Snaps a direction to the nearest of [constant DIRECTIONS].
static func snap_direction(v: Vector2) -> Vector2:
	# No direction: its angle would read as right.
	if v.is_zero_approx():
		return Vector2.ZERO
	return Vector2.from_angle(snappedf(v.angle(), DIRECTION_STEP))


## Which way a player facing [param old_facing] faces after moving
## [param new_move], a direction [method snap_direction] made. A move along a
## cardinal faces it. A diagonal keeps either of its two cardinals and
## otherwise faces the one counter-clockwise of it on screen: southwest
## faces south.
static func turn_to(old_facing: Direction.Cardinal, new_move: Vector2) -> Direction.Cardinal:
	if new_move.is_zero_approx():
		return old_facing
	# Clockwise from north in half steps between cardinals: even on a
	# cardinal, odd on a diagonal.
	var halves := posmod(
			roundi((new_move.angle() - Vector2.UP.angle()) / DIRECTION_STEP), DIRECTIONS)
	var counter_clockwise := floori(halves / 2.0) as Direction.Cardinal
	if halves % 2 == 0:
		return counter_clockwise
	var clockwise := (counter_clockwise + 1) % Direction.Cardinal.size() as Direction.Cardinal
	return clockwise if old_facing == clockwise else counter_clockwise


## Out of the fight until the run ends: at 0 health. A downed player
## doesn't move, swing or get hurt or pushed.
func is_downed() -> bool:
	return health == 0


## Does nothing while invulnerable or downed. Otherwise hurts, cancelling
## every action, and makes them invulnerable for
## [member invulnerable_duration_ticks], or downs them, stopping any push.
func lose_health(amount: int) -> bool:
	if invulnerable_ticks > 0 or is_downed():
		return false
	super.lose_health(amount)
	_stop_actions()
	if is_downed():
		knockback.ticks = 0
	else:
		invulnerable_ticks = invulnerable_duration_ticks
	return true


## Gives [param amount] health, up to [member max_health]; a downed player
## is up again where they are. With [param invulnerable], no damage can hurt
## them for [member invulnerable_duration_ticks].
func heal(amount: int, invulnerable: bool) -> void:
	health = mini(health + amount, max_health)
	if invulnerable:
		invulnerable_ticks = invulnerable_duration_ticks


## Until the push ends, the player can't steer or start an action (see
## [method step]). A downed player isn't pushed.
func push(offset: Vector2, ticks: int) -> bool:
	if is_downed():
		return false
	return super.push(offset, ticks)


## Back to neutral, as on entering a room: no action, push or
## invulnerability.
func reset_stance() -> void:
	_stop_actions()
	knockback.ticks = 0
	invulnerable_ticks = 0


## Carried by a push; otherwise its walk, unless rooted or downed.
func offset_this_tick() -> Vector2:
	if is_downed():
		return Vector2.ZERO
	if is_pushed():
		return super.offset_this_tick()
	if _is_rooted():
		return Vector2.ZERO
	return move * walk_step


## [param presses] counts each input action's presses since the last input;
## [param held_bits] has a bit per input action held.
func set_input(new_move: Vector2, presses: PackedByteArray, held_bits: int) -> void:
	move = snap_direction(new_move)
	for i in presses.size():
		if i == input_actions.size():
			input_actions.append(InputActionState.new())
		input_actions[i].unhandled_presses += presses[i]
		input_actions[i].held = held_bits & (1 << i) != 0


## Lets go of every input action, as if its keys were released.
func release_input_actions() -> void:
	for action in input_actions:
		action.held = false


## For a new connection: no move, nothing held and no press waiting.
func reset_presses() -> void:
	move = Vector2.ZERO
	input_actions.clear()


## Sets what using each item slot does, held by this player.
func set_slot_actions(actions: Array[Action]) -> void:
	slot_actions = actions
	for action in slot_actions:
		if action:
			action.holder = weakref(self)


## One tick, before the world moves it by [method offset_this_tick].
## Facing turns with each move (see [method turn_to]). A pushed player is carried
## by the push and can't steer or start an action. Otherwise a busy action that
## roots stops it moving, turning or starting another; one that doesn't
## gives way to another slot's press. Returns what a started action hits
## with, for the world to resolve. A downed player does nothing.
func step() -> HitArea:
	if is_downed():
		return null
	if invulnerable_ticks > 0:
		invulnerable_ticks -= 1
	var pushed := is_pushed()
	if pushed:
		_count_down_push()
	elif not _is_rooted():
		facing = turn_to(facing, move)
	for i in slot_actions.size():
		if slot_actions[i]:
			slot_actions[i].step(_is_held(i))
	var pressed := _consume_presses()
	if pushed or _is_rooted():
		return null
	return _start_pressed_action(pressed)


## Starts the first pressed slot's action, stopping any other. Returns
## what it hits with; null for nothing.
func _start_pressed_action(pressed: Array[bool]) -> HitArea:
	var index := _first_pressed_slot(pressed)
	if index < 0:
		return null
	_stop_actions()
	return slot_actions[index].start(_is_held(index)) as HitArea


## Some busy action roots it: no moving or turning.
func _is_rooted() -> bool:
	return slot_actions.any(func(a: Action) -> bool: return a and a.is_busy() and a.is_rooted())


func _stop_actions() -> void:
	for action in slot_actions:
		if action:
			action.cancel()


func _is_held(index: int) -> bool:
	return index < input_actions.size() and input_actions[index].held


## Which input actions were pressed since the last tick, by index. Uses up
## every press, acted on or not.
func _consume_presses() -> Array[bool]:
	var out: Array[bool] = []
	for action in input_actions:
		out.append(action.unhandled_presses > 0)
		action.unhandled_presses = 0
	return out


## The first input action in [param pressed] whose item slot holds an
## action; -1 if none.
func _first_pressed_slot(pressed: Array[bool]) -> int:
	for i in mini(pressed.size(), slot_actions.size()):
		if pressed[i] and slot_actions[i]:
			return i
	return -1
