extends "res://sim/actor.gd"
## A player's character: an actor its player steers and uses items with.

const Action := preload("res://sim/action.gd")
const ActionSwing := preload("res://sim/action_swing.gd")
const ActionGuard := preload("res://sim/action_guard.gd")
const Shield := preload("res://sim/shield.gd")
const InputActionState := preload("res://sim/input_action_state.gd")

## Where the swing is.
enum State {
	IDLE,
	SWINGING,
}

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
## How long the arc is active. The player is rooted meanwhile.
var swing_ticks := 0
## Health is never healed above this.
var max_health := 0
## How long no damage can hurt them after damage or an invulnerable heal.
var invulnerable_duration_ticks := 0
var facing := Direction.Cardinal.EAST
var move := Vector2.ZERO
## One per input action its client reports, in that order; the first ones
## use the item slots. Filled in by its first input.
var input_actions: Array[InputActionState] = []
## The dummies this swing has hit, by ID: each is hit once per swing.
var swing_struck: Array[int] = []
var state := State.IDLE
## Left in the state; unused while IDLE.
var state_ticks := 0
var connected := true
## Left in which no damage can hurt them, after they were last hurt.
var invulnerable_ticks := 0
## What using each of its holder's two item slots does, null for an empty
## slot. The lobby sets them from its holder's player data.
var slot_actions: Array[Action] = []
## Null while no shield is up. Raised by a press of an input action whose
## slot holds a guard, while idle; lowered by letting go of it, a swing,
## being hurt, a change of items or a new room. Raising it again needs a new
## press.
var shield: Shield


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


## Does nothing while invulnerable or downed. Otherwise hurts, stopping any
## swing and lowering the shield, and makes them invulnerable for
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


## Until the push ends, the player can't steer or start a swing (see
## [method step]). A downed player isn't pushed.
func push(offset: Vector2, ticks: int) -> bool:
	if is_downed():
		return false
	return super.push(offset, ticks)


## Back to neutral, as on entering a room: no swing, shield, push or
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
	shield = null


## Sets what using each item slot does; a raised shield goes down.
func set_slot_actions(actions: Array[Action]) -> void:
	slot_actions = actions
	shield = null


## One tick, before the world moves it by [method offset_this_tick].
## Facing turns with each move (see [method turn_to]). A pushed player is carried
## by the push and can't steer or start a swing. Otherwise the player is
## rooted (no moving or turning) during the swing. A shield goes up or down
## (see [member shield]). Returns whether a swing started, so the world can
## resolve what it touches. A downed player does nothing.
func step() -> bool:
	if is_downed():
		return false
	if invulnerable_ticks > 0:
		invulnerable_ticks -= 1
	var pushed := is_pushed()
	if pushed:
		_count_down_push()
	elif not _is_rooted():
		facing = turn_to(facing, move)
	_advance_state()
	var pressed := _consume_presses()
	if shield and not input_actions[shield.input_index].held:
		shield = null
	var swung := _start_swing_if_pressed(pressed, pushed)
	if swung:
		shield = null
	elif not shield and not pushed and state == State.IDLE:
		_raise_shield_if_pressed(pressed)
	return swung


func _stop_actions() -> void:
	state = State.IDLE
	state_ticks = 0
	shield = null


## No moving or turning.
func _is_rooted() -> bool:
	return state == State.SWINGING


## Counts down the swing, and goes idle when it ends.
func _advance_state() -> void:
	if state == State.IDLE:
		return
	state_ticks -= 1
	if state_ticks <= 0:
		state = State.IDLE


## A press while swinging or pushed is dropped. Returns whether a swing
## started.
func _start_swing_if_pressed(pressed: Array[bool], pushed: bool) -> bool:
	if state != State.IDLE or pushed or _pressed_slot(pressed, ActionSwing) < 0:
		return false
	state = State.SWINGING
	state_ticks = swing_ticks
	swing_struck.clear()
	return true


## Raises a shield from the first pressed input action whose slot holds a
## guard, if it's still held.
func _raise_shield_if_pressed(pressed: Array[bool]) -> void:
	var index := _pressed_slot(pressed, ActionGuard)
	if index >= 0 and input_actions[index].held:
		shield = Shield.new(self, slot_actions[index], index)


## Which input actions were pressed since the last tick, by index. Uses up
## every press, acted on or not.
func _consume_presses() -> Array[bool]:
	var out: Array[bool] = []
	for action in input_actions:
		out.append(action.unhandled_presses > 0)
		action.unhandled_presses = 0
	return out


## The first input action in [param pressed] whose item slot holds an action
## of type [param kind]; -1 if none.
func _pressed_slot(pressed: Array[bool], kind: GDScript) -> int:
	for i in mini(pressed.size(), slot_actions.size()):
		if pressed[i] and is_instance_of(slot_actions[i], kind):
			return i
	return -1
