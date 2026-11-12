extends "res://sim/actor.gd"
## A player's character: an actor its player steers and swings with.

## Where the swing is. A 0-tick cooldown is skipped. A buffered press can
## wait in any state.
enum State {
	IDLE,
	SWINGING,
	COOLDOWN,
}

const GameTime := preload("res://shared/game_time.gd")
const DataLoader := preload("res://shared/data_loader.gd")

## Shorter inputs have no reliable direction, so they count as none. Real
## input is 0 or far longer.
const MOVE_DEAD_ZONE := 0.01
## Movement and facing snap to what four keys can make.
const DIRECTIONS := 8
const DIRECTION_STEP := TAU / DIRECTIONS

## In px/s.
static var speed: float = DataLoader.player_speed
static var root_during_cooldown: bool = DataLoader.swing_root_during_cooldown
## How long the arc is active. The player is rooted meanwhile.
static var swing_ticks := GameTime.ticks(DataLoader.swing_active_sec)
## From the end of the arc to the next possible swing.
static var swing_cooldown_ticks := GameTime.ticks(DataLoader.swing_cooldown_sec)
## A press this close to idle is remembered and fires when idle.
static var swing_buffer_ticks := GameTime.ticks(DataLoader.swing_buffer_sec)
## After a player takes damage, how long no damage can hurt them.
static var hurt_invulnerable_ticks := GameTime.ticks(DataLoader.player_invulnerable_sec)

## The seat number.
var id: int
var facing := Vector2.RIGHT
var move := Vector2.ZERO
## Latest total from the client.
var attack_count := 0
var attacks_handled := 0
## A buffered press.
var attack_pending := false
var state := State.IDLE
## Left in the state; unused while IDLE.
var state_ticks := 0
var connected := true
## Left in which no damage can hurt them, after they were last hurt.
var invulnerable_ticks := 0


## Snaps a direction to the nearest of [constant DIRECTIONS].
static func snap_direction(v: Vector2) -> Vector2:
	if v.length() < MOVE_DEAD_ZONE:
		return Vector2.ZERO
	return Vector2.from_angle(snappedf(v.angle(), DIRECTION_STEP))


## Out of the fight until the run ends: at 0 health. A downed player
## doesn't move, swing or get hurt or pushed.
func is_downed() -> bool:
	return health == 0


## Does nothing while invulnerable or downed. Otherwise hurts and makes them
## invulnerable for [member hurt_invulnerable_ticks], or downs them,
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
		invulnerable_ticks = hurt_invulnerable_ticks
	return true


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
	return move * speed * GameTime.TICK_SEC


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
## rooted (no moving or turning) during the swing, and during the cooldown if
## the balance says so. Returns whether a swing started, so the world can
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
	return (state == State.SWINGING
			or state == State.COOLDOWN and root_during_cooldown)


## Counts down the swing or the cooldown, and moves on when it ends.
func _advance_state() -> void:
	if state == State.IDLE:
		return
	state_ticks -= 1
	if state_ticks > 0:
		return
	if state == State.SWINGING and swing_cooldown_ticks > 0:
		state = State.COOLDOWN
		state_ticks = swing_cooldown_ticks
	else:
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
	return true


func _ticks_until_idle() -> int:
	match state:
		State.SWINGING:
			return state_ticks + swing_cooldown_ticks
		State.COOLDOWN:
			return state_ticks
	return 0
