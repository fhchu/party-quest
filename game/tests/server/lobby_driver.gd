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
	var presses := PackedByteArray()
	presses.resize(index + 1)
	presses[index] = 1
	lobby.input(seat, move, presses, 0, now)


## Sends [param seat]'s input: [param move], with no new press.
func steer(seat: Seat, move: Vector2) -> void:
	lobby.input(seat, move, PackedByteArray(), 0, now)


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
## middle of the floor, until the run starts or for as long as crossing the
## room needs. Returns whether the run started.
func walk_through_town_door(seat: Seat) -> bool:
	var p: Player = lobby.world.players[seat.player_id]
	p.pos = WorldState.data.floor_area.get_center()
	var out := -Direction.to_vector(door().wall.inward)
	for i in ceili(WorldState.data.arena.size.length() / p.walk_step):
		steer(seat, out)
		step()
		if lobby.phase is Run:
			return true
	return false


## Plays the result out, so town comes back.
func finish_result() -> void:
	step(WorldState.data.result_ticks)
