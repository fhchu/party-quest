extends GdUnitTestSuite
## Ready and start in the Lobby on a test clock: by call and by hitting the
## town's READY and START dummies.

const Run := preload("res://server/run.gd")
const Player := preload("res://sim/player.gd")
const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const World := preload("res://sim/world.gd")
const DummyKinds := preload("res://tests/dummy_kinds.gd")

const TOWN := LobbyState.Phase.TOWN
const RUN := LobbyState.Phase.RUN
const READY := LobbyState.Readiness.READY
const NOT_READY := LobbyState.Readiness.NOT_READY

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
	assert_int(d.lobby.snapshot().run_ticks_left).is_equal(Run.duration_ticks)


func test_an_empty_lobby_cant_start() -> void:
	var a := d.join("a")
	d.lobby.set_ready(a, false)
	assert_bool(d.lobby.start_run()).is_false()


func test_ready_can_be_taken_back() -> void:
	var a := d.join("a")
	assert_bool(d.lobby.set_ready(a, true)).is_true()
	assert_bool(d.lobby.set_ready(a, true)).is_false()
	assert_bool(d.lobby.set_ready(a, false)).is_true()
	assert_bool(d.lobby.start_run()).is_false()


func test_hitting_ready_toggles_the_hitters_ready() -> void:
	var a := d.join("a")
	var b := d.join("b")
	assert_bool(d.swing_at(a, DummyKinds.ready_kind)).is_true()
	assert_int(a.readiness).is_equal(READY)
	assert_int(b.readiness).is_equal(NOT_READY)
	d.swing_at(a, DummyKinds.ready_kind)
	assert_int(a.readiness).is_equal(NOT_READY)


func test_hitting_start_waits_for_everyone() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.swing_at(a, DummyKinds.ready_kind)
	d.swing_at(a, DummyKinds.start_kind)
	assert_int(d.lobby.state().phase).is_equal(TOWN)
	d.swing_at(b, DummyKinds.ready_kind)
	d.swing_at(b, DummyKinds.start_kind)
	assert_int(d.lobby.state().phase).is_equal(RUN)


func test_a_drop_clears_ready() -> void:
	var a := d.join("a")
	d.lobby.set_ready(a, true)
	d.lobby.drop(a)
	assert_int(a.readiness).is_equal(NOT_READY)
	assert_int(d.lobby.state().seats[0].readiness).is_equal(NOT_READY)


func test_a_town_drop_leaves_the_rest_free_to_start() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.lobby.drop(a)
	d.lobby.set_ready(b, true)
	d.step()
	assert_bool(d.lobby.start_run()).is_true()


func test_two_hits_on_start_in_one_tick_start_one_run() -> void:
	var seats: Array[Seat] = [d.join("a"), d.join("b")]
	var start: World.Dummy = d.lobby.world.dummies.filter(
			func(x: World.Dummy) -> bool: return x.kind == DummyKinds.start_kind)[0]
	for seat in seats:
		d.lobby.set_ready(seat, true)
		var p: World.Player = d.lobby.world.players[seat.player_id]
		p.pos = start.pos - Vector2(World.swing_radius / 2, 0)
		p.facing = Vector2.RIGHT
		d.lobby.input(seat, Vector2.ZERO, p.attack_count + 1, d.now)
	var before := d.lobby.snapshot().world_number
	d.step(Player.swing_ticks + 1)
	assert_int(d.lobby.state().phase).is_equal(RUN)
	assert_int(d.lobby.snapshot().world_number).is_equal(before + 1)
