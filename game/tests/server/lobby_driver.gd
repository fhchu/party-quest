extends RefCounted
## A Lobby on a test clock, with shortcuts for the steps every lobby test takes.

const GameTime := preload("res://shared/game_time.gd")
const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const World := preload("res://sim/world.gd")
const Run := preload("res://server/run.gd")

## Milliseconds per tick on the test clock, rounded down.
@warning_ignore("integer_division")
const TICK_MSEC := 1000 / GameTime.TICK_RATE

## How long a run's outcome shows.
static var result_ticks := World.result_ticks

## The test clock, in ms. Tests may move it forward between steps.
var now := 0
var lobby := Lobby.new(now)
var _next_peer := 100


## Joins as [param session] on a new peer. Null when the lobby is full.
func join(session: String) -> Seat:
	_next_peer += 1
	return lobby.join(session, _next_peer)


func step(ticks := 1) -> void:
	for i in ticks:
		now += TICK_MSEC
		lobby.step(now)


## The lobby's run; fails the test outside one.
func running_run() -> Run:
	return lobby.phase as Run


## Seats [param sessions], readies them all and starts the run. Empty if
## it didn't start.
func start_with(sessions: Array[String]) -> Array[Seat]:
	var seats: Array[Seat] = []
	for s in sessions:
		seats.append(join(s))
	for seat in seats:
		lobby.set_ready(seat, true)
	if not lobby.start_run():
		seats.clear()
	return seats


## The first dummy that toggles readiness when hit; null if there's none.
func ready_dummy() -> World.Dummy:
	for dummy in lobby.world.dummies:
		if dummy.on_hit == Lobby.TOGGLE_READY:
			return dummy
	return null


## Puts [param seat]'s character just left of [param target], facing it,
## and presses attack once more.
func press_at(seat: Seat, target: World.Dummy) -> void:
	var p: World.Player = lobby.world.players[seat.player_id]
	p.pos = target.pos - Vector2(World.swing_radius / 2, 0)
	p.facing = Vector2.RIGHT
	lobby.input(seat, Vector2.ZERO, p.attack_count + 1, now)


## Swings [param seat]'s character at the READY dummy and steps until the
## swing is over. False if there's no READY dummy.
func swing_at_ready(seat: Seat) -> bool:
	var target := ready_dummy()
	if not target:
		return false
	press_at(seat, target)
	step(World.swing_ticks + 1)
	return true


## The current room's first door, the way town's lobby leaves it.
func door() -> World.RoomPlan.DoorPlan:
	return lobby.world.room.doors[0]


## Walks [param seat]'s character out through the room's door from the
## middle of the floor, until the run starts or for as long as crossing the
## room takes. Returns whether the run started.
func walk_through_town_door(seat: Seat) -> bool:
	var p: World.Player = lobby.world.players[seat.player_id]
	p.pos = World.floor_area.get_center()
	var out := -door().wall.inward
	for i in ceili(World.arena.size.length() / p.walk_step):
		lobby.input(seat, out, p.attack_count, now)
		step()
		if lobby.phase is Run:
			return true
	return false


## Plays the result out, so town comes back.
func finish_result() -> void:
	step(result_ticks)
