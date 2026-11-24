extends GdUnitTestSuite
## The Lobby's phases on a test clock: ready, start, the timer, the result and
## spectators. Seats and holds are in lobby_seats_test.gd.

const Run := preload("res://server/run.gd")
const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const WorldState := preload("res://sim/world_state.gd")
const WorldLoader := preload("res://sim/world_loader.gd")

const TOWN := LobbyState.Phase.TOWN
const RUN := LobbyState.Phase.RUN
const RESULT := LobbyState.Phase.RESULT
const NOT_READY := Seat.Participation.NOT_READY
const SPECTATING := Seat.Participation.SPECTATING
const Player := preload("res://sim/player.gd")

var d: LobbyDriver


func before_test() -> void:
	d = LobbyDriver.new()


func test_joining_the_lobby_gives_a_character() -> void:
	var a := d.join("a")
	assert_int(a.participation).is_equal(NOT_READY)
	assert_bool(d.lobby.world.players.has(a.player_id)).is_true()


func test_the_run_starts_the_party_at_its_first_rooms_spawn() -> void:
	var a := d.join("a")
	d.lobby.input(a, Vector2.RIGHT, 0, d.now)
	d.step(GameTime.TICK_RATE)
	d.lobby.set_ready(a, true)
	d.lobby.start_run()
	var spawn := WorldLoader.RUN.start.spawn
	assert_vector(d.lobby.world.players[a.player_id].pos).is_equal(spawn)


func test_ticks_keep_counting_across_new_worlds() -> void:
	d.step(3)
	var earlier := d.lobby.world.tick
	d.start_with(["a"])
	assert_int(d.lobby.world.tick).is_equal(earlier)
	d.step()
	assert_int(d.lobby.snapshot().tick).is_greater(earlier)


func test_the_timer_runs_out_into_a_loss() -> void:
	d.start_with(["a"])
	var start_ticks := d.lobby.snapshot().run_ticks_left
	d.step()
	assert_int(d.lobby.snapshot().run_ticks_left).is_equal(start_ticks - 1)
	# Skip to the last tick.
	d.lobby.world.time_up_tick = d.lobby.world.tick + 1
	d.step()
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.LOST)


func test_a_won_run_shows_the_result_then_town() -> void:
	d.start_with(["a"])
	d.lobby.end_run(WorldState.Outcome.WON)
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.WON)
	d.step(WorldState.data.result_ticks - 1)
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	d.step()
	assert_int(d.lobby.state().phase).is_equal(TOWN)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.NONE)


func test_nobody_moves_during_the_result() -> void:
	var a := d.start_with(["a"])[0]
	d.lobby.input(a, Vector2.RIGHT, 0, d.now)
	d.lobby.end_run(WorldState.Outcome.LOST)
	var pos: Vector2 = d.lobby.world.players[a.player_id].pos
	d.lobby.input(a, Vector2.RIGHT, 0, d.now)
	d.step()
	assert_vector(d.lobby.world.players[a.player_id].pos).is_equal(pos)


func test_the_world_freezes_during_the_result_but_ticks_count_on() -> void:
	var a := d.start_with(["a"])[0]
	var p: Player = d.lobby.world.players[a.player_id]
	p.invulnerable_ticks = p.invulnerable_duration_ticks
	d.lobby.end_run(WorldState.Outcome.LOST)
	var tick := d.lobby.world.tick
	d.step(3)
	assert_int(p.invulnerable_ticks).is_equal(p.invulnerable_duration_ticks)
	assert_int(d.lobby.snapshot().tick).is_equal(tick + 3)


func test_the_run_is_lost_once_nobody_is_alive() -> void:
	var seats := d.start_with(["a", "b"])
	d.lobby.world.players[seats[0].player_id].health = 0
	d.step()
	assert_int(d.lobby.state().phase).is_equal(RUN)
	d.lobby.world.players[seats[1].player_id].health = 0
	d.step()
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.LOST)


func test_ready_resets_when_town_comes_back() -> void:
	var seats := d.start_with(["a", "b"])
	d.lobby.end_run(WorldState.Outcome.WON)
	d.finish_result()
	for seat in seats:
		assert_int(seat.participation).is_equal(NOT_READY)


func test_a_mid_run_joiner_spectates_without_acting() -> void:
	d.start_with(["a"])
	var b := d.join("b")
	assert_int(b.participation).is_equal(SPECTATING)
	assert_bool(d.lobby.world.players.has(b.player_id)).is_false()
	d.lobby.input(b, Vector2.RIGHT, 1, d.now)
	d.step()
	assert_bool(d.lobby.world.players.has(b.player_id)).is_false()


func test_a_joiner_during_the_result_spectates() -> void:
	d.start_with(["a"])
	d.lobby.end_run(WorldState.Outcome.LOST)
	assert_int(d.join("b").participation).is_equal(SPECTATING)


func test_spectators_play_from_the_next_town() -> void:
	d.start_with(["a"])
	var b := d.join("b")
	d.lobby.end_run(WorldState.Outcome.LOST)
	d.finish_result()
	assert_int(b.participation).is_equal(NOT_READY)
	assert_bool(d.lobby.world.players.has(b.player_id)).is_true()


func test_spectators_take_seats() -> void:
	d.start_with(["a"])
	for s in ["b", "c", "d"]:
		assert_int(d.join(s).participation).is_equal(SPECTATING)
	assert_object(d.join("e")).is_null()


func test_the_run_swaps_the_town_dummies_for_its_first_rooms() -> void:
	d.start_with(["a"])
	assert_array(_kinds(d.lobby.world.dummies)).is_equal(
			_kinds(WorldLoader.first_run().start.spots))


func test_a_run_whose_world_is_won_shows_a_won_result() -> void:
	d.start_with(["a"])
	d.lobby.world.outcome = WorldState.Outcome.WON
	d.step()
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.WON)


func test_town_brings_back_the_town_dummies() -> void:
	d.start_with(["a"])
	d.lobby.end_run(WorldState.Outcome.LOST)
	d.finish_result()
	assert_array(_kinds(d.lobby.world.dummies)).is_equal(
			_kinds(WorldLoader.town().start.spots))


func test_the_press_that_starts_the_run_doesnt_swing_in_it() -> void:
	var a := d.join("a")
	# The client's press count from here on: one press, at READY.
	assert_bool(d.swing_at_ready(a)).is_true()
	assert_bool(d.walk_through_town_door(a)).is_true()
	var p: Player = d.lobby.world.players[a.player_id]
	d.lobby.input(a, Vector2.ZERO, 1, d.now)
	d.step()
	assert_int(p.state).is_equal(Player.State.IDLE)
	# The next press does swing, so the one before was carried, not lost.
	d.lobby.input(a, Vector2.ZERO, 2, d.now)
	d.step()
	assert_int(p.state).is_equal(Player.State.SWINGING)


func test_presses_during_the_result_dont_swing_in_town() -> void:
	var a: Seat = d.start_with(["a"])[0]
	d.lobby.end_run(WorldState.Outcome.WON)
	d.lobby.input(a, Vector2.ZERO, 5, d.now)
	d.finish_result()
	assert_int(d.lobby.state().phase).is_equal(TOWN)
	d.lobby.input(a, Vector2.ZERO, 5, d.now)
	d.step()
	assert_int(d.lobby.world.players[a.player_id].state).is_equal(Player.State.IDLE)


func test_each_new_world_gets_a_new_number() -> void:
	var earlier := d.lobby.snapshot().layout_number
	d.start_with(["a"])
	assert_int(d.lobby.snapshot().layout_number).is_not_equal(earlier)


## The kind of each of [param things]: dummies or a room plan's spots.
func _kinds(things: Array) -> Array:
	return things.map(func(thing: RefCounted) -> int: return thing.kind)
