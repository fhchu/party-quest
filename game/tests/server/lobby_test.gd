extends GdUnitTestSuite
## The Lobby's phases on a test clock: ready, start, the timer, the result and
## spectators. Seats and holds are in lobby_seats_test.gd.

const Lobby := preload("res://server/lobby.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Protocol := preload("res://net/protocol.gd")
const Tuning := preload("res://sim/tuning.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const World := preload("res://sim/world.gd")

const TOWN := LobbyState.Phase.TOWN
const MATCH := LobbyState.Phase.MATCH
const RESULT := LobbyState.Phase.RESULT
const NOT_READY := LobbyState.Readiness.NOT_READY
const SPECTATING := LobbyState.Readiness.SPECTATING

var d: LobbyDriver


func before_test() -> void:
	d = LobbyDriver.new()


func test_joining_the_lobby_gives_a_character() -> void:
	var a := d.join("a")
	assert_int(a.readiness).is_equal(NOT_READY)
	assert_bool(d.lobby.world.players.has(a.player_id)).is_true()


func test_the_match_puts_everyone_at_their_spawn_spot() -> void:
	var a := d.join("a")
	var spawn: Vector2 = d.lobby.world.players[a.player_id].pos
	d.lobby.input(a, Vector2.RIGHT, 0, d.now)
	d.step(Protocol.TICK_RATE)
	assert_vector(d.lobby.world.players[a.player_id].pos).is_not_equal(spawn)
	d.set_ready(a, true)
	d.start_match()
	assert_vector(d.lobby.world.players[a.player_id].pos).is_equal(spawn)


func test_ticks_keep_counting_across_new_worlds() -> void:
	d.step(3)
	var before := d.lobby.world.tick
	d.start_with(["a"])
	assert_int(d.lobby.world.tick).is_equal(before)
	d.step()
	assert_int(d.lobby.snapshot().tick).is_greater(before)


func test_the_timer_runs_out_into_a_loss() -> void:
	d.start_with(["a"])
	d.step()
	assert_int(d.lobby.snapshot().match_ticks_left).is_equal(Tuning.match_ticks - 1)
	# Skip to the last tick.
	d.running_match().ticks_left = 1
	d.step()
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.LOST)


func test_a_won_match_shows_the_result_then_town() -> void:
	d.start_with(["a"])
	d.end_match(LobbyState.Outcome.WON)
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.WON)
	d.step(Tuning.result_ticks - 1)
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	d.step()
	assert_int(d.lobby.state().phase).is_equal(TOWN)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.NONE)


func test_nobody_moves_during_the_result() -> void:
	var a := d.start_with(["a"])[0]
	d.lobby.input(a, Vector2.RIGHT, 0, d.now)
	d.end_match(LobbyState.Outcome.LOST)
	var pos: Vector2 = d.lobby.world.players[a.player_id].pos
	d.lobby.input(a, Vector2.RIGHT, 0, d.now)
	d.step()
	assert_vector(d.lobby.world.players[a.player_id].pos).is_equal(pos)


func test_the_world_freezes_during_the_result_but_ticks_count_on() -> void:
	var a := d.start_with(["a"])[0]
	var p: World.Player = d.lobby.world.players[a.player_id]
	p.invulnerable_ticks = Tuning.player_invulnerable_ticks
	d.end_match(LobbyState.Outcome.LOST)
	var tick := d.lobby.world.tick
	d.step(3)
	assert_int(p.invulnerable_ticks).is_equal(Tuning.player_invulnerable_ticks)
	assert_int(d.lobby.snapshot().tick).is_equal(tick + 3)


func test_the_match_is_lost_once_nobody_is_alive() -> void:
	var seats := d.start_with(["a", "b"])
	d.lobby.world.players[seats[0].player_id].health = 0
	d.step()
	assert_int(d.lobby.state().phase).is_equal(MATCH)
	d.lobby.world.players[seats[1].player_id].health = 0
	d.step()
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.LOST)


func test_ready_resets_when_town_comes_back() -> void:
	var seats := d.start_with(["a", "b"])
	d.end_match(LobbyState.Outcome.WON)
	d.finish_result()
	for seat in seats:
		assert_int(seat.readiness).is_equal(NOT_READY)


func test_a_mid_match_joiner_spectates_without_acting() -> void:
	d.start_with(["a"])
	var b := d.join("b")
	assert_int(b.readiness).is_equal(SPECTATING)
	assert_bool(d.lobby.world.players.has(b.player_id)).is_false()
	d.lobby.input(b, Vector2.RIGHT, 1, d.now)
	d.step()
	assert_bool(d.lobby.world.players.has(b.player_id)).is_false()


func test_a_joiner_during_the_result_spectates() -> void:
	d.start_with(["a"])
	d.end_match(LobbyState.Outcome.LOST)
	assert_int(d.join("b").readiness).is_equal(SPECTATING)


func test_spectators_play_from_the_next_town() -> void:
	d.start_with(["a"])
	var b := d.join("b")
	d.end_match(LobbyState.Outcome.LOST)
	d.finish_result()
	assert_int(b.readiness).is_equal(NOT_READY)
	assert_bool(d.lobby.world.players.has(b.player_id)).is_true()


func test_spectators_take_seats() -> void:
	d.start_with(["a"])
	for s in ["b", "c", "d"]:
		assert_int(d.join(s).readiness).is_equal(SPECTATING)
	assert_object(d.join("e")).is_null()


func test_the_match_swaps_the_town_dummies_for_an_enemy() -> void:
	d.start_with(["a"])
	var kinds := d.lobby.world.dummies.map(
			func(x: World.Dummy) -> Protocol.DummyKind: return x.kind)
	assert_array(kinds).is_not_empty()
	assert_array(kinds).not_contains([Protocol.DummyKind.READY, Protocol.DummyKind.START])


func test_killing_every_enemy_wins() -> void:
	var a: Lobby.Seat = d.start_with(["a"])[0]
	for i in ceili(float(Tuning.dummy_stats("enemy").health) / Tuning.swing_damage):
		assert_bool(d.swing_at(a, Protocol.DummyKind.ENEMY)).is_true()
	assert_int(d.lobby.state().phase).is_equal(RESULT)
	assert_int(d.lobby.state().outcome).is_equal(LobbyState.Outcome.WON)


func test_town_brings_back_the_town_dummies() -> void:
	d.start_with(["a"])
	d.end_match(LobbyState.Outcome.LOST)
	d.finish_result()
	var kinds := d.lobby.world.dummies.map(
			func(x: World.Dummy) -> Protocol.DummyKind: return x.kind)
	assert_array(kinds).contains_exactly_in_any_order(
			[Protocol.DummyKind.READY, Protocol.DummyKind.START])


func test_the_press_that_starts_the_match_doesnt_swing_in_it() -> void:
	var a := d.join("a")
	d.swing_at(a, Protocol.DummyKind.READY)
	d.swing_at(a, Protocol.DummyKind.START)
	assert_int(d.lobby.state().phase).is_equal(MATCH)
	var p: World.Player = d.lobby.world.players[a.player_id]
	d.lobby.input(a, Vector2.ZERO, p.attack_count, d.now)
	d.step()
	assert_int(p.phase).is_equal(World.Phase.READY)


func test_presses_during_the_result_dont_swing_in_town() -> void:
	var a: Lobby.Seat = d.start_with(["a"])[0]
	d.end_match(LobbyState.Outcome.WON)
	d.lobby.input(a, Vector2.ZERO, 5, d.now)
	d.finish_result()
	assert_int(d.lobby.state().phase).is_equal(TOWN)
	d.lobby.input(a, Vector2.ZERO, 5, d.now)
	d.step()
	assert_int(d.lobby.world.players[a.player_id].phase).is_equal(World.Phase.READY)


func test_each_new_world_gets_a_new_number() -> void:
	var before := d.lobby.snapshot().world_number
	d.start_with(["a"])
	assert_int(d.lobby.snapshot().world_number).is_not_equal(before)
