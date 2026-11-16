extends GdUnitTestSuite
## Ready and start in the Lobby on a test clock: by call, by hitting the
## town's READY dummy and by walking through town's door.

const Run := preload("res://server/run.gd")
const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const World := preload("res://sim/world.gd")
const DummyKinds := preload("res://tests/dummy_kinds.gd")

const TOWN := LobbyState.Phase.TOWN
const RUN := LobbyState.Phase.RUN
const READY := Seat.Readiness.READY
const NOT_READY := Seat.Readiness.NOT_READY

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
	var world := d.lobby.world
	assert_int(d.lobby.snapshot().run_ticks_left).is_equal(world.time_up_tick - world.tick)


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
	assert_int(p.health).is_equal(World.player_max_health - 1)
	assert_int(p.invulnerable_ticks).is_equal(0)


func test_a_drop_clears_ready() -> void:
	var a := d.join("a")
	d.lobby.set_ready(a, true)
	d.lobby.drop(a)
	assert_int(a.readiness).is_equal(NOT_READY)
	assert_int(d.lobby.state().seats[0].readiness).is_equal(LobbyState.Readiness.NOT_READY)


func test_a_town_drop_leaves_the_rest_free_to_start() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.lobby.drop(a)
	d.lobby.set_ready(b, true)
	d.step()
	assert_bool(d.lobby.start_run()).is_true()


func test_un_readying_as_the_party_walks_out_still_starts_the_run() -> void:
	var a := d.join("a")
	var b := d.join("b")
	d.lobby.set_ready(a, true)
	d.lobby.set_ready(b, true)
	var ready_dummy: World.Dummy = d.lobby.world.dummies[0]
	var pb: World.Player = d.lobby.world.players[b.player_id]
	pb.pos = ready_dummy.pos - Vector2(World.swing_radius / 2, 0)
	pb.facing = Vector2.RIGHT
	d.lobby.input(b, Vector2.ZERO, pb.attack_count + 1, d.now)
	var pa: World.Player = d.lobby.world.players[a.player_id]
	var gap: Rect2 = World.walls.filter(
			func(w: World.WallPlan) -> bool: return w.inward == Vector2.DOWN)[0].gap
	pa.pos = Vector2(gap.get_center().x, gap.end.y + pa.walk_step / 2)
	d.lobby.input(a, Vector2.UP, pa.attack_count, d.now)
	d.step()
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
