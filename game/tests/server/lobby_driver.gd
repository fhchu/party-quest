extends RefCounted
## A Lobby on a test clock, with shortcuts for the steps every lobby test takes.

const GameTime := preload("res://shared/game_time.gd")
const Lobby := preload("res://server/lobby.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")
const Town := preload("res://server/town.gd")
const Match := preload("res://server/match.gd")

## Milliseconds per tick on the test clock, rounded down.
@warning_ignore("integer_division")
const TICK_MSEC := 1000 / GameTime.TICK_RATE

## The test clock, in ms. Tests may move it forward between steps.
var now := 0
var lobby := Lobby.new(now)
var _next_peer := 100


## Joins as [param session] on a new peer. Null when the lobby is full.
func join(session: String) -> Lobby.Seat:
	_next_peer += 1
	return lobby.join(session, _next_peer)


func step(ticks := 1) -> void:
	for i in ticks:
		now += TICK_MSEC
		lobby.step(now)


## The lobby's town phase; fails the test outside one.
func town() -> Town:
	return lobby.phase as Town


## The lobby's match; fails the test outside one.
func running_match() -> Match:
	return lobby.phase as Match


func set_ready(seat: Lobby.Seat, ready: bool) -> bool:
	return town().set_ready(lobby, seat, ready)


func start_match() -> bool:
	return town().start_match(lobby, now)


func end_match(outcome: LobbyState.Outcome) -> void:
	running_match().end_match(lobby, outcome, now)


## Seats [param sessions], readies them all and starts the match. Empty if
## it didn't start.
func start_with(sessions: Array[String]) -> Array[Lobby.Seat]:
	var seats: Array[Lobby.Seat] = []
	for s in sessions:
		seats.append(join(s))
	for seat in seats:
		set_ready(seat, true)
	if not start_match():
		seats.clear()
	return seats


## Puts [param seat]'s character just left of the first dummy of [param kind],
## facing it, swings once and steps until the swing is over. False if
## there's no such dummy.
func swing_at(seat: Lobby.Seat, kind: World.Kind) -> bool:
	var target: World.Dummy = null
	for dummy in lobby.world.dummies:
		if dummy.kind == kind:
			target = dummy
			break
	var p: World.Player = lobby.world.players.get(seat.player_id)
	if not target or not p:
		return false
	p.pos = target.pos - Vector2(Tuning.swing_radius / 2, 0)
	p.facing = Vector2.RIGHT
	lobby.input(seat, Vector2.ZERO, p.attack_count + 1, now)
	step(Tuning.swing_ticks + 1)
	return true


## Plays the result out, so town comes back.
func finish_result() -> void:
	step(Tuning.result_ticks)
