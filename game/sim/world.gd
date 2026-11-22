extends RefCounted
## The game simulation.
##
## Plain data with no nodes, so the server can step it headless.

const World := preload("res://sim/world.gd")
const Player := preload("res://sim/player.gd")
const Dummy := preload("res://sim/dummy.gd")
const Fire := preload("res://sim/fire.gd")
const Charge := preload("res://sim/charge.gd")
const AttackChoice := preload("res://sim/attack_choice.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const Goal := preload("res://sim/goal.gd")
const RoomPlan := preload("res://sim/room_plan.gd")
const RunPlan := preload("res://sim/run_plan.gd")
const Projectile := preload("res://sim/projectile.gd")
const WorldData := preload("res://sim/world_data.gd")
const RoomState := preload("res://sim/room_state.gd")
const Walls := preload("res://sim/walls.gd")
const PartySquare := preload("res://sim/party_square.gd")

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
## [method show_result].
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
## Every dummy a swing touched during the last
## [method WorldSimulator.step], for the lobby to act on.
var swing_contacts: Array[SwingContact] = []

var _last_id := 0
## What bodies are pushed back out of in the current room.
var walls := Walls.new()
## Each takes this world and returns whether that condition is met.
var win_checks: Array[Callable] = []
var lose_checks: Array[Callable] = []
## The press totals of the world before, by player ID, until
## [method WorldSimulator.add_player] carries each one over.
var carried_presses: Dictionary[int, int] = {}
## Where the party's square starts: the first room's spawn, or the arena's
## center in a world with no room.
var spawn := data.arena.get_center()
## Which way the party faces at [member spawn]: the first room's way, or
## a player's default in a world with no room.
var spawn_facing := Vector2.RIGHT
## Every room the party has been in, as they left it.
var _rooms: Dictionary[RoomPlan, RoomState] = {}
## What it plays, for its rooms; null for none.
var run_plan: RunPlan


## A check for [param goal]: it takes the world and returns whether the
## goal is met. A TIME_UP goal also limits [param world]'s time.
static func goal_check(goal: Goal, world: World) -> Callable:
	var check := Callable()
	match goal.type:
		Goal.Type.DEFEAT_ALL:
			if goal.kind == Goal.EVERY_KIND:
				check = func(w: World) -> bool: return w.dummies.is_empty()
			else:
				var kind := goal.kind
				check = func(w: World) -> bool:
					return w.dummies.all(func(d: Dummy) -> bool: return d.kind != kind)
		Goal.Type.PARTY_DOWNED:
			check = func(w: World) -> bool: return w.players_alive() == 0
		Goal.Type.CLEAR_ROOM:
			var to_clear: RoomPlan = goal.room
			check = func(w: World) -> bool: return w.is_room_cleared(to_clear)
		Goal.Type.TIME_UP:
			world.time_up_tick = world.tick + goal.ticks
			check = func(w: World) -> bool: return w.is_time_up()
		Goal.Type.ENTERED:
			# Only the current room's clear checks run.
			check = func(_w: World) -> bool: return true
	return check


## Town, replacing [param previous] if any.
static func town(previous: World = null) -> World:
	return World.new(WorldLoader.town(), previous)


## The run, replacing [param previous], its random choices seeded.
static func run(previous: World) -> World:
	var plan := WorldLoader.first_run()
	var out := World.new(plan, previous)
	out.rng.seed = run_seed(plan.rng_seed)
	return out


## [param rng_seed] if it's set, else a new random seed.
static func run_seed(rng_seed: int) -> int:
	return rng_seed if rng_seed >= 0 else randi()


## Plays [param plan]; with none, an empty room with no doors that never ends.
## [param previous] is the world this one replaces: its tick and its
## players' presses carry over.
func _init(plan: RunPlan = null, previous: World = null) -> void:
	if previous:
		# Clients drop snapshots whose tick goes backwards.
		tick = previous.tick
		layout_number = previous.layout_number + 1
		for id: int in previous.players:
			carried_presses[id] = previous.players[id].attack_count
	run_plan = plan
	if plan and plan.start:
		_build_room(plan.start)
		spawn = plan.start.spawn
		spawn_facing = plan.start.spawn_facing
	_place_walls()
	if not plan:
		return
	# After the tick carries over: a time limit counts from it.
	for goal in plan.win:
		win_checks.append(goal_check(goal, self))
	for goal in plan.lose:
		lose_checks.append(goal_check(goal, self))


## Moves the party into [param next]: as they left it if they've been
## there, else as its data lays it out. Shots in flight are gone.
func enter_room(next: RoomPlan) -> void:
	if _rooms.has(next):
		room = _rooms[next]
	else:
		_build_room(next)
	projectiles.clear()
	layout_number += 1
	_place_walls()


## Opens or shuts the current room's doors from outside the world, with no
## heal: town's door opens only while everyone is ready.
func set_room_cleared(cleared: bool) -> void:
	if room.cleared == cleared:
		return
	room.cleared = cleared
	_place_walls()


func _place_walls() -> void:
	walls.place(room, data.walls, data.floor_area, data.arena, _player_size())


func is_room_cleared(which: RoomPlan) -> bool:
	return _rooms.has(which) and _rooms[which].cleared


## Freezes it with its outcome showing, until its time runs out
## [member WorldData.result_ticks] from now. A frozen world's tick still counts.
func show_result() -> void:
	frozen = true
	time_up_tick = tick + data.result_ticks


func is_time_up() -> bool:
	return time_up_tick != NO_TIME_LIMIT and tick >= time_up_tick


## The gold each player earns from this world's [member outcome]: its
## run's win gold once won, else none.
func gold_earned() -> int:
	return run_plan.win_gold if run_plan and outcome == Outcome.WON else 0


## The players not downed.
func players_alive() -> int:
	return players.values().filter(func(p: Player) -> bool: return not p.is_downed()).size()


## A new ID, unique within this world.
func new_id() -> int:
	_last_id += 1
	return _last_id


## Makes [param next] the current room, with its dummies placed.
func _build_room(next: RoomPlan) -> void:
	room = RoomState.new(data.floor_area, data.tile_size)
	_rooms[next] = room
	room.doors = next.doors
	for goal in next.clear_goals:
		room.clear_checks.append(goal_check(goal, self))
	room.cleared = room.clear_checks.is_empty()
	for spot in next.spots:
		_add_dummy(spot.kind, spot.offset, spot.on_hit)


## A dummy of [param kind] at [param offset] from the arena's center, with
## that kind's attributes and [param on_hit] passed on.
func _add_dummy(kind: int, offset: Vector2, on_hit: String) -> Dummy:
	var d := WorldLoader.new_dummy(kind)
	d.id = new_id()
	d.on_hit = on_hit
	d.pos = data.arena.get_center() + offset
	d.personal_space = data.personal_space
	dummies.append(d)
	return d


## A swing touching a dummy.
class SwingContact:
	var attacker_id: int
	var on_hit: String
