extends GdUnitTestSuite
## Ready and start in the Lobby on a test clock: by call, by hitting the
## town's READY dummy and by walking through town's door.

const Run := preload("res://server/run.gd")
const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const World := preload("res://sim/world.gd")

const TOWN := LobbyState.Phase.TOWN
const RUN := LobbyState.Phase.RUN
const READY := Seat.Participation.READY
const NOT_READY := Seat.Participation.NOT_READY

var d: LobbyDriver


func before_test() -> void:
	d = LobbyDriver.new()


func test_start_needs_everyone_ready() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.lobby.set_ready(a, true)
	assert_bool(d.lobby.start_run()).is_false()
	d.lobby.set_ready(b, true)
	assert_bool(d.lobby.start_run()).is_true()
	assert_int(d.lobby.state().phase).is_equal(RUN)


func test_an_empty_lobby_cant_start() -> void:
	assert_bool(d.lobby.start_run()).is_false()
	assert_int(d.lobby.state().phase).is_equal(TOWN)


func test_ready_can_be_taken_back() -> void:
	var a := d.join("a")
	assert_bool(d.lobby.set_ready(a, true)).is_true()
	assert_bool(d.lobby.set_ready(a, true)).is_false()
	assert_bool(d.lobby.set_ready(a, false)).is_true()
	assert_bool(d.lobby.start_run()).is_false()


func test_hitting_ready_toggles_the_hitters_ready() -> void:
	var a := d.join("a")
	var b := d.join("b")
	assert_bool(d.swing_at_ready(a)).is_true()
	assert_int(a.participation).is_equal(READY)
	assert_int(b.participation).is_equal(NOT_READY)
	d.swing_at_ready(a)
	assert_int(a.participation).is_equal(NOT_READY)


func test_the_town_door_opens_only_while_everyone_is_ready() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.step()
	assert_bool(d.lobby.snapshot().room_cleared).is_false()
	assert_bool(d.walk_through_town_door(a)).is_false()
	d.lobby.set_ready(a, true)
	d.lobby.set_ready(b, true)
	d.step()
	assert_bool(d.lobby.snapshot().room_cleared).is_true()
	d.lobby.set_ready(b, false)
	d.step()
	assert_bool(d.lobby.snapshot().room_cleared).is_false()


func test_walking_through_the_open_town_door_starts_the_run() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.lobby.set_ready(a, true)
	d.lobby.set_ready(b, true)
	assert_bool(d.walk_through_town_door(a)).is_true()
	assert_int(d.lobby.state().phase).is_equal(RUN)


func test_the_town_door_never_heals() -> void:
	var a := d.join("a")
	var p: World.Player = d.lobby.world.players[a.player_id]
	p.health -= 1
	for i in 3:
		d.lobby.set_ready(a, true)
		d.step()
		d.lobby.set_ready(a, false)
		d.step()
	assert_int(p.health).is_equal(World.data.player_max_health - 1)
	assert_int(p.invulnerable_ticks).is_equal(0)


func test_a_drop_clears_ready() -> void:
	var a := d.join("a")
	d.lobby.set_ready(a, true)
	d.lobby.drop(a)
	assert_int(a.participation).is_equal(NOT_READY)
	assert_int(d.lobby.state().seats[0].participation).is_equal(LobbyState.Participation.NOT_READY)


func test_a_town_drop_leaves_the_rest_free_to_start() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.lobby.drop(a)
	d.lobby.set_ready(b, true)
	d.step()
	assert_bool(d.lobby.start_run()).is_true()


func test_un_readying_as_the_party_walks_out_still_starts_the_run() -> void:
	var hit_after := _ticks_until_a_swing_touches_ready()
	assert_int(hit_after).is_greater(0)
	var a := d.join("a")
	var b := d.join("b")
	d.lobby.set_ready(a, true)
	d.lobby.set_ready(b, true)
	d.press_at(b, d.ready_dummy())
	# A starts outside the door's gap by half a step more than it walks
	# before b's swing lands, so it crosses on that very tick.
	var pa: World.Player = d.lobby.world.players[a.player_id]
	var wall := d.door().wall
	var gap_depth := absf(wall.gap.size.dot(wall.inward))
	pa.pos = (wall.gap.get_center()
			+ wall.inward * (gap_depth / 2 + pa.walk_step * (hit_after - 0.5)))
	var town := d.lobby.world
	for i in hit_after:
		d.lobby.input(a, -wall.inward, pa.attack_count, d.now)
		d.step()
	assert_array(town.swing_contacts).is_not_empty()
	assert_int(d.lobby.state().phase).is_equal(RUN)


func test_all_ready_needs_someone_seated_and_shows_in_the_state() -> void:
	assert_bool(d.lobby.all_ready()).is_false()
	var a := d.join("a")
	assert_bool(d.lobby.all_ready()).is_false()
	d.lobby.set_ready(a, true)
	assert_bool(d.lobby.all_ready()).is_true()
	assert_bool(d.lobby.state().all_ready).is_true()


func test_all_ready_needs_every_seat() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.lobby.set_ready(a, true)
	assert_bool(d.lobby.all_ready()).is_false()
	d.lobby.set_ready(b, true)
	assert_bool(d.lobby.all_ready()).is_true()


## How many ticks after a press a swing first touches the READY dummy, in
## a lobby of its own.
func _ticks_until_a_swing_touches_ready() -> int:
	var probe := LobbyDriver.new()
	var seat := probe.join("probe")
	probe.press_at(seat, probe.ready_dummy())
	for i in World.data.swing_ticks:
		probe.step()
		if not probe.lobby.world.swing_contacts.is_empty():
			return i + 1
	return -1
