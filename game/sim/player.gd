extends "res://sim/actor.gd"
## A player's character: an actor its player steers and swings with.

## Where the swing is. A buffered press can wait in either state.
enum State {
	IDLE,
	SWINGING,
}

## Movement and facing snap to what four keys can make.
const DIRECTIONS := 8
const DIRECTION_STEP := TAU / DIRECTIONS

# PLACEHOLDER (design): the values below. World converts them to ticks
# for the fields that count in ticks.
## How fast it walks, in px/s.
static var walk_speed := 160.0
## After damage or an invulnerable heal, how long no damage can hurt it.
static var invulnerable_sec := 0.5
## A press this close to idle is remembered and fires when idle.
static var swing_buffer_sec := 0.0

## The seat number.
var id: int
# What it can do: [method WorldSimulator.add_player] sets these, from the static
# variables above and from balance.tres.
## How far it walks each tick, in px.
var walk_step := 0.0
## How long the arc is active. The player is rooted meanwhile.
var swing_ticks := 0
## A press this close to idle is remembered and fires when idle.
var swing_buffer_ticks := 0
## Health is never healed above this.
var max_health := 0
## How long no damage can hurt them after damage or an invulnerable heal.
var invulnerable_duration_ticks := 0
var facing := Vector2.RIGHT
var move := Vector2.ZERO
## Latest total from the client.
var attack_count := 0
var attacks_handled := 0
## A buffered press.
var attack_pending := false
## The dummies this swing has hit, by ID: each is hit once per swing.
var swing_struck: Array[int] = []
var state := State.IDLE
## Left in the state; unused while IDLE.
var state_ticks := 0
var connected := true
## Left in which no damage can hurt them, after they were last hurt.
var invulnerable_ticks := 0


## Snaps a direction to the nearest of [constant DIRECTIONS].
static func snap_direction(v: Vector2) -> Vector2:
	# No direction: its angle would read as right.
	if v.is_zero_approx():
		return Vector2.ZERO
	return Vector2.from_angle(snappedf(v.angle(), DIRECTION_STEP))


## Out of the fight until the run ends: at 0 health. A downed player
## doesn't move, swing or get hurt or pushed.
func is_downed() -> bool:
	return health == 0


## Does nothing while invulnerable or downed. Otherwise hurts and makes them
## invulnerable for [member invulnerable_duration_ticks], or downs them,
## stopping any swing or push.
func take_damage(amount: int) -> bool:
	if invulnerable_ticks > 0 or is_downed():
		return false
	super.take_damage(amount)
	if is_downed():
		state = State.IDLE
		attack_pending = false
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


## A push cancels the swing in progress; until it ends, the player can't
## steer or start another (see [method step]). A downed player isn't pushed.
func push(offset: Vector2, ticks: int) -> bool:
	if is_downed():
		return false
	if state == State.SWINGING:
		state = State.IDLE
		state_ticks = 0
	return super.push(offset, ticks)


## Carried by a push; otherwise its walk, unless rooted or downed.
func offset_this_tick() -> Vector2:
	if is_downed():
		return Vector2.ZERO
	if is_pushed():
		return super.offset_this_tick()
	if _is_rooted():
		return Vector2.ZERO
	return move * walk_step


func set_input(new_move: Vector2, new_attack_count: int) -> void:
	move = snap_direction(new_move)
	attack_count = maxi(attack_count, new_attack_count)


## Throws away every press up to [param through_count] unswung.
func discard_attacks(through_count: int) -> void:
	attack_count = maxi(attack_count, through_count)
	attacks_handled = attack_count
	attack_pending = false


## For a new connection, which counts its presses from scratch.
func reset_presses() -> void:
	move = Vector2.ZERO
	attack_count = 0
	attacks_handled = 0
	attack_pending = false


## One tick, before the world moves it by [method offset_this_tick].
## Facing is the last direction moved. A pushed player is carried
## by the push and can't steer or start a swing. Otherwise the player is
## rooted (no moving or turning) during the swing. Returns whether a swing started, so the world can
## resolve what it touches. A downed player does nothing.
func step() -> bool:
	if is_downed():
		return false
	if invulnerable_ticks > 0:
		invulnerable_ticks -= 1
	var pushed := is_pushed()
	if pushed:
		_count_down_push()
	elif not _is_rooted() and move != Vector2.ZERO:
		facing = move
	_advance_state()
	return _start_swing_if_pressed(pushed)


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


## A new press is remembered if the player will be idle within the buffer.
## Returns whether a swing started.
func _start_swing_if_pressed(pushed: bool) -> bool:
	if attack_count > attacks_handled:
		attacks_handled = attack_count
		attack_pending = _ticks_until_idle() <= swing_buffer_ticks
	if state != State.IDLE or not attack_pending or pushed:
		return false
	attack_pending = false
	state = State.SWINGING
	state_ticks = swing_ticks
	swing_struck.clear()
	return true


func _ticks_until_idle() -> int:
	return state_ticks if state == State.SWINGING else 0
