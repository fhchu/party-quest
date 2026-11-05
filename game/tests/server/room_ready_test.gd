extends GdUnitTestSuite
## Ready and start in the Room on a test clock: by call and by hitting the
## lobby's READY and START dummies.

const Room := preload("res://server/room.gd")
const RoomState := preload("res://net/room_state.gd")
const RoomDriver := preload("res://tests/server/room_driver.gd")
const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")

const LOBBY := RoomState.Phase.LOBBY
const MATCH := RoomState.Phase.MATCH

var d: RoomDriver


func before_test() -> void:
	d = RoomDriver.new()


func test_start_needs_everyone_ready() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.room.set_ready(a, true)
	assert_bool(d.room.start_match(a)).is_false()
	d.room.set_ready(b, true)
	assert_bool(d.room.start_match(b)).is_true()
	assert_int(d.room.phase).is_equal(MATCH)
	assert_int(d.room.match_ticks_left).is_equal(Tuning.match_ticks)


func test_an_empty_room_cant_start() -> void:
	var a := d.join("a")
	d.room.set_ready(a, false)
	assert_bool(d.room.start_match(a)).is_false()


func test_ready_can_be_taken_back() -> void:
	var a := d.join("a")
	assert_bool(d.room.set_ready(a, true)).is_true()
	assert_bool(d.room.set_ready(a, true)).is_false()
	assert_bool(d.room.set_ready(a, false)).is_true()
	assert_bool(d.room.start_match(a)).is_false()


func test_hitting_ready_toggles_the_hitters_ready() -> void:
	var a := d.join("a")
	var b := d.join("b")
	assert_bool(d.swing_at(a, World.Kind.READY)).is_true()
	assert_bool(a.ready).is_true()
	assert_bool(b.ready).is_false()
	d.swing_at(a, World.Kind.READY)
	assert_bool(a.ready).is_false()


func test_hitting_start_waits_for_everyone() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.swing_at(a, World.Kind.READY)
	d.swing_at(a, World.Kind.START)
	assert_int(d.room.phase).is_equal(LOBBY)
	d.swing_at(b, World.Kind.READY)
	d.swing_at(b, World.Kind.START)
	assert_int(d.room.phase).is_equal(MATCH)


func test_a_drop_clears_ready() -> void:
	var a := d.join("a")
	d.room.set_ready(a, true)
	d.room.drop(a, d.now)
	assert_bool(a.ready).is_false()
	assert_bool(d.room.state().seats[0].ready).is_false()


func test_a_dropped_player_doesnt_hold_up_the_start() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.room.drop(a, d.now)
	d.room.set_ready(b, true)
	assert_bool(d.room.state().all_ready()).is_true()
	assert_bool(d.room.start_match(b)).is_true()
	assert_bool(d.room.world.players[a.player_id].connected).is_false()
