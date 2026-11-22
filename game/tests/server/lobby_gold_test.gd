extends GdUnitTestSuite
## Gold from won runs: who earns it at the run's end, and what clients see.

const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const WorldState := preload("res://sim/world_state.gd")
const WorldLoader := preload("res://sim/world_loader.gd")

## Unlike the real run's, so a payout read from anywhere else shows.
const WIN_GOLD := 7

var d: LobbyDriver
var _real_win_gold := 0
## The real run's data, pinned for each test. A variable, since a property
## can't be set through a constant.
var _run_setup: Resource = WorldLoader.RUN


func before_test() -> void:
	d = LobbyDriver.new()
	_real_win_gold = _run_setup.win_gold
	_run_setup.win_gold = WIN_GOLD


func after_test() -> void:
	_run_setup.win_gold = _real_win_gold


func test_a_won_run_pays_every_seat_that_played_it() -> void:
	var seats := d.start_with(["a", "b"])
	d.lobby.end_run(WorldState.Outcome.WON)
	for seat in seats:
		assert_int(seat.gold).is_equal(WIN_GOLD)


func test_a_lost_run_pays_nothing() -> void:
	var a := d.start_with(["a"])[0]
	d.lobby.end_run(WorldState.Outcome.LOST)
	assert_int(a.gold).is_equal(0)


func test_a_spectator_earns_nothing() -> void:
	var a := d.start_with(["a"])[0]
	var b := d.join("b")
	assert_int(b.participation).is_equal(Seat.Participation.SPECTATING)
	d.lobby.end_run(WorldState.Outcome.WON)
	assert_int(a.gold).is_equal(WIN_GOLD)
	assert_int(b.gold).is_equal(0)


func test_a_seat_still_dropped_at_the_end_earns_nothing() -> void:
	var seats := d.start_with(["a", "b"])
	d.lobby.drop(seats[1])
	d.lobby.end_run(WorldState.Outcome.WON)
	assert_int(seats[0].gold).is_equal(WIN_GOLD)
	assert_int(seats[1].gold).is_equal(0)


func test_a_seat_that_dropped_and_came_back_earns() -> void:
	var b := d.start_with(["a", "b"])[1]
	d.lobby.drop(b)
	assert_object(d.join("b")).is_same(b)
	d.lobby.end_run(WorldState.Outcome.WON)
	assert_int(b.gold).is_equal(WIN_GOLD)


func test_an_away_seat_earns() -> void:
	var b := d.start_with(["a", "b"])[1]
	d.lobby.set_away(b, true)
	assert_int(b.connection).is_equal(Seat.Connection.AWAY)
	d.lobby.end_run(WorldState.Outcome.WON)
	assert_int(b.gold).is_equal(WIN_GOLD)


func test_gold_adds_up_over_runs() -> void:
	var a := d.start_with(["a"])[0]
	d.lobby.end_run(WorldState.Outcome.WON)
	d.finish_result()
	d.lobby.set_ready(a, true)
	assert_bool(d.lobby.start_run()).is_true()
	d.lobby.end_run(WorldState.Outcome.WON)
	assert_int(a.gold).is_equal(2 * WIN_GOLD)


func test_clients_see_each_seats_gold() -> void:
	var seats := d.start_with(["a", "b"])
	d.lobby.drop(seats[1])
	d.lobby.end_run(WorldState.Outcome.WON)
	var state := d.lobby.state()
	assert_int(state.find_seat(seats[0].player_id).gold).is_equal(WIN_GOLD)
	assert_int(state.find_seat(seats[1].player_id).gold).is_equal(0)
