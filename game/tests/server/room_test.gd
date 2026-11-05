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

var d: RoomDriver


func before_test() -> void:
	d = RoomDriver.new()


func test_joining_the_lobby_gives_a_character() -> void:
	var a := d.join("a")
	assert_bool(a.spectating).is_false()
	assert_bool(d.room.world.players.has(a.player_id)).is_true()


func test_ready_and_start_are_ignored_during_a_match() -> void:
	var a := d.start_with(["a"])[0]
	assert_bool(d.room.set_ready(a, false)).is_false()
	assert_bool(d.room.start_match(a)).is_false()


func test_the_match_puts_everyone_at_their_spawn_spot() -> void:
	var a := d.join("a")
	var spawn: Vector2 = d.room.world.players[a.player_id].pos
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	d.step(Protocol.TICK_RATE)
	assert_vector(d.room.world.players[a.player_id].pos).is_not_equal(spawn)
	d.room.set_ready(a, true)
	d.room.start_match(a)
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
	assert_int(d.room.match_ticks_left).is_equal(Tuning.match_ticks - 1)
	assert_int(d.room.snapshot().match_ticks_left).is_equal(d.room.match_ticks_left)
	# Skip to the last tick.
	d.room.match_ticks_left = 1
	d.step()
	assert_int(d.room.phase).is_equal(RESULT)
	assert_int(d.room.outcome).is_equal(RoomState.Outcome.LOST)
	assert_int(d.room.match_ticks_left).is_zero()


func test_a_won_match_shows_the_result_then_the_lobby() -> void:
	d.start_with(["a"])
	d.room.end_match(RoomState.Outcome.WON)
	assert_int(d.room.phase).is_equal(RESULT)
	assert_int(d.room.outcome).is_equal(RoomState.Outcome.WON)
	d.step(Tuning.result_ticks - 1)
	assert_int(d.room.phase).is_equal(RESULT)
	d.step()
	assert_int(d.room.phase).is_equal(LOBBY)
	assert_int(d.room.outcome).is_equal(RoomState.Outcome.NONE)


func test_end_match_is_ignored_outside_a_match() -> void:
	d.join("a")
	d.room.end_match(RoomState.Outcome.WON)
	assert_int(d.room.phase).is_equal(LOBBY)


func test_nobody_moves_during_the_result() -> void:
	var a := d.start_with(["a"])[0]
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	d.room.end_match(RoomState.Outcome.LOST)
	var pos: Vector2 = d.room.world.players[a.player_id].pos
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	d.step()
	assert_vector(d.room.world.players[a.player_id].pos).is_equal(pos)


func test_ready_resets_when_the_lobby_comes_back() -> void:
	var seats := d.start_with(["a", "b"])
	d.room.end_match(RoomState.Outcome.WON)
	d.finish_result()
	for seat in seats:
		assert_bool(seat.ready).is_false()


func test_a_mid_match_joiner_spectates_without_acting() -> void:
	d.start_with(["a"])
	var b := d.join("b")
	assert_bool(b.spectating).is_true()
	assert_bool(d.room.world.players.has(b.player_id)).is_false()
	d.room.input(b, Vector2.RIGHT, 1, d.now)
	d.step()
	assert_bool(d.room.world.players.has(b.player_id)).is_false()
	assert_bool(d.room.set_ready(b, true)).is_false()
	assert_bool(d.room.start_match(b)).is_false()


func test_a_joiner_during_the_result_spectates() -> void:
	d.start_with(["a"])
	d.room.end_match(RoomState.Outcome.LOST)
	assert_bool(d.join("b").spectating).is_true()


func test_spectators_play_from_the_next_lobby() -> void:
	d.start_with(["a"])
	var b := d.join("b")
	d.room.end_match(RoomState.Outcome.LOST)
	d.finish_result()
	assert_bool(b.spectating).is_false()
	assert_bool(d.room.world.players.has(b.player_id)).is_true()


func test_spectators_take_seats() -> void:
	d.start_with(["a"])
	for s in ["b", "c", "d"]:
		assert_bool(d.join(s).spectating).is_true()
	assert_object(d.join("e")).is_null()


func test_the_match_swaps_the_lobby_dummies_for_an_enemy() -> void:
	d.start_with(["a"])
	var kinds := d.room.world.dummies.map(func(x: World.Dummy) -> World.Kind: return x.kind)
	assert_array(kinds).is_equal([World.Kind.ENEMY])


func test_killing_every_enemy_wins() -> void:
	var a: Room.Seat = d.start_with(["a"])[0]
	for i in ceili(float(Tuning.dummy_stats("enemy").health) / Tuning.swing_damage):
		assert_bool(d.swing_at(a, World.Kind.ENEMY)).is_true()
	assert_int(d.room.phase).is_equal(RESULT)
	assert_int(d.room.outcome).is_equal(RoomState.Outcome.WON)


func test_the_lobby_brings_back_the_lobby_dummies() -> void:
	d.start_with(["a"])
	d.room.end_match(RoomState.Outcome.LOST)
	d.finish_result()
	var kinds := d.room.world.dummies.map(func(x: World.Dummy) -> World.Kind: return x.kind)
	assert_array(kinds).contains_exactly_in_any_order([World.Kind.READY, World.Kind.START])


func test_the_press_that_starts_the_match_doesnt_swing_in_it() -> void:
	var a := d.join("a")
	d.swing_at(a, World.Kind.READY)
	d.swing_at(a, World.Kind.START)
	assert_int(d.room.phase).is_equal(MATCH)
	var p: World.Player = d.room.world.players[a.player_id]
	d.room.input(a, Vector2.ZERO, p.attack_count, d.now)
	d.step()
	assert_int(p.phase).is_equal(World.Phase.READY)


func test_presses_during_the_result_dont_swing_in_the_lobby() -> void:
	var a: Room.Seat = d.start_with(["a"])[0]
	d.room.end_match(RoomState.Outcome.WON)
	d.room.input(a, Vector2.ZERO, 5, d.now)
	d.finish_result()
	assert_int(d.room.phase).is_equal(LOBBY)
	d.room.input(a, Vector2.ZERO, 5, d.now)
	d.step()
	assert_int(d.room.world.players[a.player_id].phase).is_equal(World.Phase.READY)


func test_each_new_world_gets_a_new_number() -> void:
	var before := d.room.snapshot().world_number
	d.start_with(["a"])
	assert_int(d.room.snapshot().world_number).is_not_equal(before)
