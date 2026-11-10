extends GdUnitTestSuite
## The Room's phases on a test clock: ready, start, the timer, the result and
## spectators. Seats and holds are in room_seats_test.gd.

const Room := preload("res://server/room.gd")
const RoomState := preload("res://net/room_state.gd")
const Protocol := preload("res://net/protocol.gd")
const Tuning := preload("res://sim/tuning.gd")
const RoomDriver := preload("res://tests/server/room_driver.gd")
const World := preload("res://sim/world.gd")

const LOBBY := RoomState.Phase.LOBBY
const MATCH := RoomState.Phase.MATCH
const RESULT := RoomState.Phase.RESULT
const NOT_READY := RoomState.Readiness.NOT_READY
const SPECTATING := RoomState.Readiness.SPECTATING

var d: RoomDriver


func before_test() -> void:
	d = RoomDriver.new()


func test_joining_the_lobby_gives_a_character() -> void:
	var a := d.join("a")
	assert_int(a.readiness).is_equal(NOT_READY)
	assert_bool(d.room.world.players.has(a.player_id)).is_true()


func test_the_match_puts_everyone_at_their_spawn_spot() -> void:
	var a := d.join("a")
	var spawn: Vector2 = d.room.world.players[a.player_id].pos
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	d.step(Protocol.TICK_RATE)
	assert_vector(d.room.world.players[a.player_id].pos).is_not_equal(spawn)
	d.set_ready(a, true)
	d.start_match()
	assert_vector(d.room.world.players[a.player_id].pos).is_equal(spawn)


func test_ticks_keep_counting_across_new_worlds() -> void:
	d.step(3)
	var before := d.room.world.tick
	d.start_with(["a"])
	assert_int(d.room.world.tick).is_equal(before)
	d.step()
	assert_int(d.room.snapshot().tick).is_greater(before)


func test_the_timer_runs_out_into_a_loss() -> void:
	d.start_with(["a"])
	d.step()
	assert_int(d.room.snapshot().match_ticks_left).is_equal(Tuning.match_ticks - 1)
	# Skip to the last tick.
	d.running_match().ticks_left = 1
	d.step()
	assert_int(d.room.state().phase).is_equal(RESULT)
	assert_int(d.room.state().outcome).is_equal(RoomState.Outcome.LOST)


func test_a_won_match_shows_the_result_then_the_lobby() -> void:
	d.start_with(["a"])
	d.end_match(RoomState.Outcome.WON)
	assert_int(d.room.state().phase).is_equal(RESULT)
	assert_int(d.room.state().outcome).is_equal(RoomState.Outcome.WON)
	d.step(Tuning.result_ticks - 1)
	assert_int(d.room.state().phase).is_equal(RESULT)
	d.step()
	assert_int(d.room.state().phase).is_equal(LOBBY)
	assert_int(d.room.state().outcome).is_equal(RoomState.Outcome.NONE)


func test_nobody_moves_during_the_result() -> void:
	var a := d.start_with(["a"])[0]
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	d.end_match(RoomState.Outcome.LOST)
	var pos: Vector2 = d.room.world.players[a.player_id].pos
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	d.step()
	assert_vector(d.room.world.players[a.player_id].pos).is_equal(pos)


func test_the_world_freezes_during_the_result_but_ticks_count_on() -> void:
	var a := d.start_with(["a"])[0]
	var p: World.Player = d.room.world.players[a.player_id]
	p.invulnerable_ticks = Tuning.player_invulnerable_ticks
	d.end_match(RoomState.Outcome.LOST)
	var tick := d.room.world.tick
	d.step(3)
	assert_int(p.invulnerable_ticks).is_equal(Tuning.player_invulnerable_ticks)
	assert_int(d.room.snapshot().tick).is_equal(tick + 3)


func test_the_match_is_lost_once_nobody_is_standing() -> void:
	var seats := d.start_with(["a", "b"])
	d.room.world.players[seats[0].player_id].health = 0
	d.step()
	assert_int(d.room.state().phase).is_equal(MATCH)
	d.room.world.players[seats[1].player_id].health = 0
	d.step()
	assert_int(d.room.state().phase).is_equal(RESULT)
	assert_int(d.room.state().outcome).is_equal(RoomState.Outcome.LOST)


func test_ready_resets_when_the_lobby_comes_back() -> void:
	var seats := d.start_with(["a", "b"])
	d.end_match(RoomState.Outcome.WON)
	d.finish_result()
	for seat in seats:
		assert_int(seat.readiness).is_equal(NOT_READY)


func test_a_mid_match_joiner_spectates_without_acting() -> void:
	d.start_with(["a"])
	var b := d.join("b")
	assert_int(b.readiness).is_equal(SPECTATING)
	assert_bool(d.room.world.players.has(b.player_id)).is_false()
	d.room.input(b, Vector2.RIGHT, 1, d.now)
	d.step()
	assert_bool(d.room.world.players.has(b.player_id)).is_false()


func test_a_joiner_during_the_result_spectates() -> void:
	d.start_with(["a"])
	d.end_match(RoomState.Outcome.LOST)
	assert_int(d.join("b").readiness).is_equal(SPECTATING)


func test_spectators_play_from_the_next_lobby() -> void:
	d.start_with(["a"])
	var b := d.join("b")
	d.end_match(RoomState.Outcome.LOST)
	d.finish_result()
	assert_int(b.readiness).is_equal(NOT_READY)
	assert_bool(d.room.world.players.has(b.player_id)).is_true()


func test_spectators_take_seats() -> void:
	d.start_with(["a"])
	for s in ["b", "c", "d"]:
		assert_int(d.join(s).readiness).is_equal(SPECTATING)
	assert_object(d.join("e")).is_null()


func test_the_match_swaps_the_lobby_dummies_for_an_enemy() -> void:
	d.start_with(["a"])
	var kinds := d.room.world.dummies.map(func(x: World.Dummy) -> World.Kind: return x.kind)
	assert_array(kinds).is_not_empty()
	assert_array(kinds).not_contains([World.Kind.READY, World.Kind.START])


func test_killing_every_enemy_wins() -> void:
	var a: Room.Seat = d.start_with(["a"])[0]
	for i in ceili(float(Tuning.dummy_stats("enemy").health) / Tuning.swing_damage):
		assert_bool(d.swing_at(a, World.Kind.ENEMY)).is_true()
	assert_int(d.room.state().phase).is_equal(RESULT)
	assert_int(d.room.state().outcome).is_equal(RoomState.Outcome.WON)


func test_the_lobby_brings_back_the_lobby_dummies() -> void:
	d.start_with(["a"])
	d.end_match(RoomState.Outcome.LOST)
	d.finish_result()
	var kinds := d.room.world.dummies.map(func(x: World.Dummy) -> World.Kind: return x.kind)
	assert_array(kinds).contains_exactly_in_any_order([World.Kind.READY, World.Kind.START])


func test_the_press_that_starts_the_match_doesnt_swing_in_it() -> void:
	var a := d.join("a")
	d.swing_at(a, World.Kind.READY)
	d.swing_at(a, World.Kind.START)
	assert_int(d.room.state().phase).is_equal(MATCH)
	var p: World.Player = d.room.world.players[a.player_id]
	d.room.input(a, Vector2.ZERO, p.attack_count, d.now)
	d.step()
	assert_int(p.phase).is_equal(World.Phase.READY)


func test_presses_during_the_result_dont_swing_in_the_lobby() -> void:
	var a: Room.Seat = d.start_with(["a"])[0]
	d.end_match(RoomState.Outcome.WON)
	d.room.input(a, Vector2.ZERO, 5, d.now)
	d.finish_result()
	assert_int(d.room.state().phase).is_equal(LOBBY)
	d.room.input(a, Vector2.ZERO, 5, d.now)
	d.step()
	assert_int(d.room.world.players[a.player_id].phase).is_equal(World.Phase.READY)


func test_each_new_world_gets_a_new_number() -> void:
	var before := d.room.snapshot().world_number
	d.start_with(["a"])
	assert_int(d.room.snapshot().world_number).is_not_equal(before)
