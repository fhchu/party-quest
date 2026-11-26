extends RefCounted
## A Lobby on a test clock, with shortcuts for the steps every lobby test needs.

const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const WorldState := preload("res://sim/world_state.gd")
const Run := preload("res://server/run.gd")
const Dummy := preload("res://sim/dummy.gd")
const Player := preload("res://sim/player.gd")
const ItemSword := preload("res://shared/data/items/item_sword.gd")
const SWORD: ItemSword = preload("res://shared/data/items/item_sword.tres")
const RoomPlan := preload("res://sim/room_plan.gd")
const Protocol := preload("res://net/protocol.gd")
const Server := preload("res://server/server.gd")

## Milliseconds per tick on the test clock, rounded down.
@warning_ignore("integer_division")
const TICK_MSEC := 1000 / GameTime.TICK_RATE

## The test clock, in ms. Tests may move it forward between steps.
var now := 0
var lobby := Lobby.new(now)
var _next_peer := 100


## Joins as [param session] on a new peer. Null when the lobby is full.
func join(session: String) -> Seat:
	_next_peer += 1
	return lobby.join(session, _next_peer)


## Sends [param seat]'s input: [param move], with input action
## [param index] pressed once more.
func press(seat: Seat, move := Vector2.ZERO, index := 0) -> void:
	press_many(seat, { index: 1 }, move)


## Sends [param seat]'s input: [param move], with each input action in
## [param counts] pressed that many times more. Like the server's, it holds a
## count for every input action.
## The menu half copies the server's own step from presses to the menu;
## server_test.gd checks that step over a real connection.
func press_many(seat: Seat, counts: Dictionary, move := Vector2.ZERO) -> void:
	var presses := PackedByteArray()
	presses.resize(Protocol.INPUT_ACTION_COUNT)
	for index: int in counts:
		presses[index] = counts[index]
	lobby.input(seat, move, presses, 0, now)
	lobby.menu_input(seat, Server.menu_presses_of(presses))


## Sends [param seat]'s input: [param move], with no new press.
func steer(seat: Seat, move: Vector2) -> void:
	press_many(seat, {}, move)


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
	if not lobby.start_run(0):
		seats.clear()
	return seats


## The first dummy that toggles readiness when hit; null if there's none.
func ready_dummy() -> Dummy:
	return dummy_on_hit(Lobby.TOGGLE_READY)


## The first dummy whose on_hit is [param on_hit]; null if there's none.
func dummy_on_hit(on_hit: String) -> Dummy:
	for dummy in lobby.world.dummies:
		if dummy.on_hit == on_hit:
			return dummy
	return null


## Puts [param seat]'s character just left of [param target], facing it,
## and presses attack once more.
func press_at(seat: Seat, target: Dummy) -> void:
	var p: Player = lobby.world.players[seat.player_id]
	p.pos = target.pos - Vector2(SWORD.swing_radius / 2, 0)
	p.facing = Direction.Cardinal.EAST
	press(seat)


## Swings [param seat]'s character at the READY dummy and steps until the
## swing is over. False if there's no READY dummy.
func swing_at_ready(seat: Seat) -> bool:
	return swing_at(seat, Lobby.TOGGLE_READY)


## Swings [param seat]'s character at the first dummy whose on_hit is
## [param on_hit] and steps until the swing is over. False if there's no
## such dummy.
func swing_at(seat: Seat, on_hit: String) -> bool:
	var target := dummy_on_hit(on_hit)
	if not target:
		return false
	press_at(seat, target)
	step(swing_ticks() + 1)
	return true


## How long the data's sword swings.
static func swing_ticks() -> int:
	return GameTime.ticks(SWORD.swing_active_sec)


## Whether [param p]'s first item slot is busy, as the sword's is while it
## swings.
static func is_swinging(p: Player) -> bool:
	return p.slot_actions[0].is_busy()


## The current room's first door, the way town's lobby leaves it.
func door() -> RoomPlan.DoorPlan:
	return lobby.world.room.doors[0]


## Walks [param seat]'s character out through the room's door from the
## middle of the floor, until the level select opens or for as long as
## crossing the room needs. Returns whether it opened.
func walk_through_town_door(seat: Seat) -> bool:
	var p: Player = lobby.world.players[seat.player_id]
	p.pos = WorldState.data.floor_area.get_center()
	var out := -Direction.to_vector(door().wall.inward)
	for i in ceili(WorldState.data.arena.size.length() / p.walk_step):
		steer(seat, out)
		step()
		if lobby.state().level_select_open:
			return true
	return false


## Walks [param seat] out of town and presses select on the level select's
## cursor, then steps until the run starts or the press plainly failed.
## Returns whether the run started.
func leave_town_by_select(seat: Seat) -> bool:
	if not walk_through_town_door(seat):
		return false
	press(seat, Vector2.ZERO, Protocol.InputAction.USE_ITEM_1)
	# One step acts on the press, the next sees the level chosen.
	step(2)
	return lobby.phase is Run


## Plays the result out, so town comes back.
func finish_result() -> void:
	step(WorldState.data.result_ticks)
