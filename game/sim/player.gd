extends "res://sim/actor.gd"
## A player's character: an actor its player steers and swings with.

## In px/s.
static var speed: float = DataLoader.player_speed
static var root_during_cooldown: bool = DataLoader.swing_root_during_cooldown
## How long the arc is active. The player is rooted meanwhile.
static var swing_ticks := GameTime.ticks(DataLoader.swing_active_sec)
## From the end of the arc to the next possible swing.
static var swing_cooldown_ticks := GameTime.ticks(DataLoader.swing_cooldown_sec)
## A press this close to ready is remembered and fires when ready.
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
var phase := World.Phase.READY
## Left in the phase; unused while READY.
var phase_ticks := 0
var connected := true
## Left in which no damage can hurt them, after they were last hurt.
var invulnerable_ticks := 0


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
		phase = World.Phase.READY
		attack_pending = false
		knockback.ticks = 0
	else:
		invulnerable_ticks = hurt_invulnerable_ticks
	return true


## A push cancels the swing in progress; until it ends, the player can't
## steer or start another (see [method step]). A downed player isn't pushed.
func push(offset: Vector2, ticks: int) -> void:
	if is_downed():
		return
	if phase == World.Phase.SWINGING:
		phase = World.Phase.READY
		phase_ticks = 0
	super.push(offset, ticks)


func set_input(new_move: Vector2, new_attack_count: int) -> void:
	move = World.snap_direction(new_move)
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


## One tick. Facing is the last direction moved. A pushed player is carried
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
	var rooted := (phase == World.Phase.SWINGING
			or phase == World.Phase.COOLDOWN and root_during_cooldown)
	if pushed:
		_step_push()
	elif not rooted:
		if move != Vector2.ZERO:
			facing = move
		_move_within_arena(move * speed * GameTime.TICK_SEC)
	_advance_phase()
	return _start_swing_if_pressed(pushed)


## Counts down the swing or the cooldown, and moves on when it ends.
func _advance_phase() -> void:
	if phase == World.Phase.READY:
		return
	phase_ticks -= 1
	if phase_ticks > 0:
		return
	if phase == World.Phase.SWINGING and swing_cooldown_ticks > 0:
		phase = World.Phase.COOLDOWN
		phase_ticks = swing_cooldown_ticks
	else:
		phase = World.Phase.READY


## A new press is remembered if the swing will be ready within the buffer.
## Returns whether a swing started.
func _start_swing_if_pressed(pushed: bool) -> bool:
	if attack_count > attacks_handled:
		attacks_handled = attack_count
		attack_pending = _ticks_until_ready() <= swing_buffer_ticks
	if phase != World.Phase.READY or not attack_pending or pushed:
		return false
	attack_pending = false
	phase = World.Phase.SWINGING
	phase_ticks = swing_ticks
	return true


func _ticks_until_ready() -> int:
	match phase:
		World.Phase.SWINGING:
			return phase_ticks + swing_cooldown_ticks
		World.Phase.COOLDOWN:
			return phase_ticks
	return 0
