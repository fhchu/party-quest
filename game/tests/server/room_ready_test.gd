extends GdUnitTestSuite
## Ready and start in the Room on a test clock: by call and by hitting the
## lobby's READY and START dummies.

const Room := preload("res://server/room.gd")
const RoomState := preload("res://net/room_state.gd")
const Protocol := preload("res://net/protocol.gd")
const RoomDriver := preload("res://tests/server/room_driver.gd")
const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")

const LOBBY := RoomState.Phase.LOBBY
const MATCH := RoomState.Phase.MATCH
const READY := RoomState.Standing.READY
const NOT_READY := RoomState.Standing.NOT_READY

var d: RoomDriver


func before_test() -> void:
	d = RoomDriver.new()


func test_start_needs_everyone_ready() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.set_ready(a, true)
	assert_bool(d.start_match()).is_false()
	d.set_ready(b, true)
	assert_bool(d.start_match()).is_true()
	assert_int(d.room.state().phase).is_equal(MATCH)
	assert_int(d.room.snapshot().match_ticks_left).is_equal(Tuning.match_ticks)


func test_an_empty_room_cant_start() -> void:
	var a := d.join("a")
	d.set_ready(a, false)
	assert_bool(d.start_match()).is_false()


func test_ready_can_be_taken_back() -> void:
	var a := d.join("a")
	assert_bool(d.set_ready(a, true)).is_true()
	assert_bool(d.set_ready(a, true)).is_false()
	assert_bool(d.set_ready(a, false)).is_true()
	assert_bool(d.start_match()).is_false()


func test_hitting_ready_toggles_the_hitters_ready() -> void:
	var a := d.join("a")
	var b := d.join("b")
	assert_bool(d.swing_at(a, World.Kind.READY)).is_true()
	assert_int(a.standing).is_equal(READY)
	assert_int(b.standing).is_equal(NOT_READY)
	d.swing_at(a, World.Kind.READY)
	assert_int(a.standing).is_equal(NOT_READY)


func test_hitting_start_waits_for_everyone() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.swing_at(a, World.Kind.READY)
	d.swing_at(a, World.Kind.START)
	assert_int(d.room.state().phase).is_equal(LOBBY)
	d.swing_at(b, World.Kind.READY)
	d.swing_at(b, World.Kind.START)
	assert_int(d.room.state().phase).is_equal(MATCH)


func test_a_drop_clears_ready() -> void:
	var a := d.join("a")
	d.set_ready(a, true)
	d.room.drop(a, d.now)
	assert_int(a.standing).is_equal(NOT_READY)
	assert_int(d.room.state().seats[0].standing).is_equal(NOT_READY)


func test_a_dropped_player_holds_up_the_start_until_their_seat_is_freed() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.room.drop(a, d.now)
	d.set_ready(b, true)
	assert_bool(d.start_match()).is_false()
	d.now += int(Protocol.LOBBY_SEAT_HOLD_SEC * 1000)
	d.step()
	assert_bool(d.start_match()).is_true()


func test_two_hits_on_start_in_one_tick_start_one_match() -> void:
	var seats: Array[Room.Seat] = [d.join("a"), d.join("b")]
	var start: World.Dummy = d.room.world.dummies.filter(
			func(x: World.Dummy) -> bool: return x.kind == World.Kind.START)[0]
	for seat in seats:
		d.set_ready(seat, true)
		var p: World.Player = d.room.world.players[seat.player_id]
		p.pos = start.pos - Vector2(Tuning.swing_radius / 2, 0)
		p.facing = Vector2.RIGHT
		d.room.input(seat, Vector2.ZERO, p.attack_count + 1, d.now)
	var before := d.room.snapshot().world_number
	d.step(Tuning.swing_ticks + 1)
	assert_int(d.room.state().phase).is_equal(MATCH)
	assert_int(d.room.snapshot().world_number).is_equal(before + 1)
