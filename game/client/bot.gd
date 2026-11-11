extends RefCounted
## A substitute player for tests: in town it walks to the READY dummy and
## hits it until it's ready, then waits; in a match it moves and attacks at
## random, for load tests. May grow into the Phase 4 simulator bots.

const Protocol := preload("res://net/protocol.gd")
const ClientTuning := preload("res://net/client_tuning.gd")
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
## [param my_id] the bot's seat, [param lobby] the lobby state and
## [param tuning] the welcome's sizes; any may be null before they arrive. The
## lobby state comes after the welcome, so with a lobby there are sizes.
func tick(
		now: float, view: Snapshot, my_id: int, lobby: LobbyState, tuning: ClientTuning) -> bool:
	if lobby and lobby.phase == LobbyState.Phase.TOWN:
		var me: Snapshot.Player = view.find_player(my_id) if view else null
		return _ready_up(now, view, lobby.find_seat(my_id), me, tuning.swing_reach())
	if now >= _next_turn:
		_next_turn = now + TURN_SEC
		move = Vector2.from_angle(randi_range(0, Protocol.DIRECTIONS - 1) * Protocol.DIRECTION_STEP)
	return _attack_due(now)


## Walks to the READY dummy and swings at it until the seat is ready, then
## stops, so it never starts the match by hitting START.
func _ready_up(
		now: float, view: Snapshot, seat: LobbyState.Seat, me: Snapshot.Player,
		reach: float) -> bool:
	move = Vector2.ZERO
	if not seat or seat.readiness == LobbyState.Readiness.READY or not me:
		return false
	for d in view.dummies:
		if d.kind != Protocol.DummyKind.READY:
			continue
		var to := d.pos - me.pos
		if to.length() > reach * REACH:
			move = to.normalized()
			return false
		return _attack_due(now)
	return false


func _attack_due(now: float) -> bool:
	if now < _next_attack:
		return false
	_next_attack = now + ATTACK_SEC
	return true
