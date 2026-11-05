extends GdUnitTestSuite
## The Room's seats on a test clock: numbering, holds after a drop, rejoining,
## away and silence.

const Room := preload("res://server/room.gd")
const Protocol := preload("res://net/protocol.gd")
const RoomDriver := preload("res://tests/server/room_driver.gd")

const GRACE_MSEC := int(Protocol.RECONNECT_GRACE_SEC * 1000)

var d: RoomDriver


func before_test() -> void:
	d = RoomDriver.new()


func test_seats_are_numbered_from_one() -> void:
	var ids: Array[int] = []
	for s in ["a", "b", "c", "d"]:
		ids.append(d.join(s).player_id)
	assert_array(ids).contains_exactly([1, 2, 3, 4])


func test_a_fifth_person_finds_the_room_full() -> void:
	for s in ["a", "b", "c", "d"]:
		d.join(s)
	assert_object(d.join("e")).is_null()


func test_a_drop_holds_the_seat_for_a_while() -> void:
	var a := d.join("a")
	d.join("b")
	d.room.drop(a, d.now)
	d.step(Protocol.TICK_RATE)
	var back := d.join("a")
	assert_object(back).is_same(a)
	assert_int(back.state).is_equal(Room.State.SILENT)
	assert_bool(d.room.world.players[a.player_id].connected).is_true()


func test_a_drop_frees_the_seat_after_the_grace_period() -> void:
	var a := d.join("a")
	d.join("b")
	d.room.drop(a, d.now)
	d.now += GRACE_MSEC
	d.step()
	assert_object(d.room.seat_of_session("a")).is_null()
	assert_int(d.room.world.players.size()).is_equal(1)


func test_a_freed_seat_goes_to_the_next_newcomer() -> void:
	var a := d.join("a")
	d.join("b")
	d.room.drop(a, d.now)
	d.now += GRACE_MSEC
	d.step()
	assert_int(d.join("c").player_id).is_equal(1)


func test_a_held_seat_counts_toward_full() -> void:
	var seats: Array[Room.Seat] = []
	for s in ["a", "b", "c", "d"]:
		seats.append(d.join(s))
	d.room.drop(seats[0], d.now)
	assert_object(d.join("e")).is_null()


func test_away_ignores_input() -> void:
	var a := d.join("a")
	d.room.set_away(a, true)
	var pos: Vector2 = d.room.world.players[a.player_id].pos
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	d.step()
	assert_vector(d.room.world.players[a.player_id].pos).is_equal(pos)
	assert_int(a.state).is_equal(Room.State.AWAY)
	d.room.set_away(a, false)
	assert_int(a.state).is_equal(Room.State.SILENT)


func test_input_silence_stops_the_player() -> void:
	var a := d.join("a")
	d.room.input(a, Vector2.RIGHT, 0, d.now)
	assert_int(a.state).is_equal(Room.State.ACTIVE)
	d.step(ceili(Protocol.INPUT_SILENCE_SEC * Protocol.TICK_RATE) + 1)
	assert_int(a.state).is_equal(Room.State.SILENT)
	var pos: Vector2 = d.room.world.players[a.player_id].pos
	d.step()
	assert_vector(d.room.world.players[a.player_id].pos).is_equal(pos)
