extends RefCounted
## The game's state: everything the simulator advances and the snapshot
## reads, as plain data with no nodes, so the server can run it headless.
## WorldSimulator changes it; WorldSnapshot gathers it for the wire.

const Player := preload("res://sim/player.gd")
const Dummy := preload("res://sim/dummy.gd")
const RoomPlan := preload("res://sim/room_plan.gd")
const RunPlan := preload("res://sim/run_plan.gd")
const Projectile := preload("res://sim/projectile.gd")
const HitArea := preload("res://sim/hit_area.gd")
const WorldData := preload("res://sim/world_data.gd")
const RoomState := preload("res://sim/room_state.gd")
const Walls := preload("res://sim/walls.gd")

## Whether the run in this world is over, and how.
enum Outcome {
	NONE,
	WON,
	LOST,
}

## [member time_up_tick] for a world with no time limit.
const NO_TIME_LIMIT := -1

## The gameplay values; a test swaps in its own and puts a fresh one back.
static var data := WorldData.new()

var tick := 0
## Makes every random choice in the world, in its update order, so the same
## seed and inputs play out the same way. The lobby seeds it at a run's
## start.
var rng := RandomNumberGenerator.new()
## One more than the world this one replaces, so clients jump to the new
## positions instead of sliding there.
var layout_number := 0
## Set when one of the world's run conditions is met. A town world has none.
var outcome := Outcome.NONE
## The tick its time runs out, set by a TIME_UP goal or
## [method WorldSimulator.show_result].
var time_up_tick := NO_TIME_LIMIT
## A frozen world only counts its tick, so snapshots still count up and
## clients keep accepting them. Presses made meanwhile are spent, so none
## swings if it runs again.
var frozen := false
var players: Dictionary[int, Player] = {}
## The room the party is in.
var room := RoomState.new(data.floor_area, data.tile_size)
## The current room's.
var dummies: Array[Dummy]:
	get:
		return room.dummies
	set(value):
		room.dummies = value
var projectiles: Array[Projectile] = []
## What players' busy actions hit with.
var hit_areas: Array[HitArea] = []
## Every dummy a swing touched during the last
## [method WorldSimulator.step], for the lobby to act on.
var swing_contacts: Array[SwingContact] = []

## The last ID handed out; see [method WorldSimulator.new_id].
var last_id := 0
## What bodies are pushed back out of in the current room.
var walls := Walls.new()
## Each is passed this world and returns whether that condition is met.
var win_checks: Array[Callable] = []
var lose_checks: Array[Callable] = []
## Where the party's square starts: the first room's spawn, or the arena's
## center in a world with no room.
var spawn := data.arena.get_center()
## Which way the party faces at [member spawn]: the first room's way, or
## this in a world with no room.
var spawn_facing := Direction.Cardinal.SOUTH
## Every room the party has been in, as they left it.
var rooms: Dictionary[RoomPlan, RoomState] = {}
## What it plays, for its rooms; null for none.
var run_plan: RunPlan


func is_room_cleared(which: RoomPlan) -> bool:
	return rooms.has(which) and rooms[which].cleared


func is_time_up() -> bool:
	return time_up_tick != NO_TIME_LIMIT and tick >= time_up_tick


## The gold each player earns from this world's [member outcome]: its
## run's win gold once won, else none.
func gold_earned() -> int:
	return run_plan.win_gold if run_plan and outcome == Outcome.WON else 0


## The players not downed.
func players_alive() -> int:
	return players.values().filter(func(p: Player) -> bool: return not p.is_downed()).size()


## A swing touching a dummy.
class SwingContact:
	var attacker_id: int
	var on_hit: String
