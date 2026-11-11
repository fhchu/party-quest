extends RefCounted
## A substitute player for tests: in town it walks to the READY dummy and
## hits it until it's ready, then waits; in a run it moves and attacks at
## random, for load tests. May grow into the Phase 4 simulator bots.

const World := preload("res://sim/world.gd")
const Tuning := preload("res://sim/tuning.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")

# Arbitrary: enough to keep a load test busy.
const TURN_SEC := 1.0
const ATTACK_SEC := 0.5
## Close enough to the READY dummy that a swing reaches it, as a share of
## the swing's radius.
const REACH := 0.6

var move := Vector2.ZERO
var _next_turn := 0.0
var _next_attack := 0.0


## Returns whether to press attack now. [param view] is what's drawn,
## [param my_id] the bot's seat and [param lobby] the lobby state; either may
## be null before they arrive.
func tick(now: float, view: Snapshot, my_id: int, lobby: LobbyState) -> bool:
	if lobby and lobby.phase == LobbyState.Phase.TOWN:
		var me: Snapshot.Player = view.find_player(my_id) if view else null
		return _ready_up(now, view, lobby.find_seat(my_id), me)
	if now >= _next_turn:
		_next_turn = now + TURN_SEC
		move = Vector2.from_angle(randi_range(0, World.DIRECTIONS - 1) * World.DIRECTION_STEP)
	return _attack_due(now)


## Walks to the READY dummy and swings at it until the seat is ready, then
## stops, so it never starts the run by hitting START.
func _ready_up(now: float, view: Snapshot, seat: LobbyState.Seat, me: Snapshot.Player) -> bool:
	move = Vector2.ZERO
	if not seat or seat.readiness == LobbyState.Readiness.READY or not me:
		return false
	for d in view.dummies:
		if d.kind != World.Kind.READY:
			continue
		var to := d.pos - me.pos
		if to.length() > Tuning.swing_radius * REACH:
			move = to.normalized()
			return false
		return _attack_due(now)
	return false


func _attack_due(now: float) -> bool:
	if now < _next_attack:
		return false
	_next_attack = now + ATTACK_SEC
	return true
