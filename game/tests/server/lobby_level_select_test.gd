extends GdUnitTestSuite
## The level select over town: its shared cursor, choosing a level, backing
## out, and who can close it.

const Lobby := preload("res://server/lobby.gd")
const Seat := preload("res://server/seat.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const Protocol := preload("res://net/protocol.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const Player := preload("res://sim/player.gd")
const Run := preload("res://server/run.gd")
const WorldState := preload("res://sim/world_state.gd")
const DataRecords := preload("res://tests/data_records.gd")

const SELECT := Protocol.InputAction.USE_ITEM_1
const BACK := Protocol.InputAction.USE_ITEM_2
const UP := Protocol.InputAction.MOVE_UP
const LEFT := Protocol.InputAction.MOVE_LEFT
const RIGHT := Protocol.InputAction.MOVE_RIGHT
## Each test level's run starts with its number of turrets, from 1, so
## which one started shows; three, so wrapping can't land on the default.
const TURRETS_BY_LEVEL: Array[int] = [1, 2, 3]

var d: LobbyDriver
var a: Seat
var b: Seat


func before_test() -> void:
	WorldLoader.levels = DataRecords.levels(TURRETS_BY_LEVEL)
	d = LobbyDriver.new()
	a = d.join("a")
	b = d.join("b")
	d.lobby.set_ready(a, true)
	d.lobby.set_ready(b, true)
	assert_bool(d.walk_through_town_door(a)).is_true()


func after_test() -> void:
	WorldLoader.levels = WorldLoader.LEVELS


func test_each_right_press_moves_the_cursor_one_level() -> void:
	d.press_many(a, { RIGHT: 1 })
	assert_int(d.lobby.state().cursor).is_equal(1)


func test_any_seat_moves_the_shared_cursor() -> void:
	d.press_many(a, { RIGHT: 1 })
	d.press_many(b, { RIGHT: 1 })
	assert_int(d.lobby.state().cursor).is_equal(2)


func test_left_from_the_first_level_wraps_to_the_last() -> void:
	d.press_many(a, { LEFT: 1 })
	# The last of TURRETS_BY_LEVEL's three.
	assert_int(d.lobby.state().cursor).is_equal(2)


func test_a_diagonal_moves_the_cursor_along_the_row() -> void:
	d.press_many(a, { UP: 1, RIGHT: 1 })
	assert_int(d.lobby.state().cursor).is_equal(1)


func test_select_starts_the_cursors_level() -> void:
	d.press_many(a, { RIGHT: 1 })
	d.press_many(a, { SELECT: 1 })
	d.step(LobbyDriver.TO_A_CHOSEN_LEVEL)
	assert_object(d.lobby.phase).is_instanceof(Run)
	# TURRETS_BY_LEVEL[1].
	assert_int(d.lobby.world.dummies.size()).is_equal(2)


func test_choosing_a_level_by_number_starts_it() -> void:
	d.lobby.choose_level(2)
	d.step(LobbyDriver.TO_A_CHOSEN_LEVEL)
	assert_object(d.lobby.phase).is_instanceof(Run)
	# TURRETS_BY_LEVEL[2].
	assert_int(d.lobby.world.dummies.size()).is_equal(3)


func test_choosing_a_level_that_doesnt_exist_does_nothing() -> void:
	d.press_many(a, { RIGHT: 1 })
	# One past the last of TURRETS_BY_LEVEL's three.
	d.lobby.choose_level(3)
	d.step(LobbyDriver.TO_A_CHOSEN_LEVEL)
	assert_bool(d.lobby.state().level_select_open).is_true()
	assert_int(d.lobby.state().cursor).is_equal(1)


func test_back_shuts_the_level_select_and_un_readies_only_the_presser() -> void:
	d.press_many(b, { BACK: 1 })
	d.step()
	assert_bool(d.lobby.state().level_select_open).is_false()
	assert_int(a.participation).is_equal(Seat.Participation.READY)
	assert_int(b.participation).is_equal(Seat.Participation.NOT_READY)
	assert_bool(d.lobby.snapshot().room_cleared).is_false()


func test_back_leaves_everyone_outside_the_doorway_where_they_were() -> void:
	var where := _positions()
	assert_bool(d.door().wall.gap.has_point(where[b.player_id])).is_false()
	d.press_many(b, { BACK: 1 })
	d.step()
	assert_vector(d.lobby.world.players[b.player_id].pos).is_equal(where[b.player_id])


func test_back_pushes_whoever_is_in_the_doorway_straight_back_out_of_it() -> void:
	var gap := d.door().wall.gap
	var in_doorway: Vector2 = _positions()[a.player_id]
	assert_bool(gap.has_point(in_doorway)).is_true()
	d.press_many(b, { BACK: 1 })
	d.step()
	var pushed_to: Vector2 = d.lobby.world.players[a.player_id].pos
	assert_bool(gap.has_point(pushed_to)).is_false()
	assert_float(pushed_to.x).is_equal(in_doorway.x)


func test_back_beats_a_select_in_the_same_tick() -> void:
	d.press_many(a, { SELECT: 1 })
	d.press_many(b, { BACK: 1 })
	d.step(LobbyDriver.TO_A_CHOSEN_LEVEL)
	assert_object(d.lobby.phase).is_not_instanceof(Run)
	assert_bool(d.lobby.state().level_select_open).is_false()


func test_the_cursor_stays_where_it_was_after_backing_out() -> void:
	d.press_many(a, { RIGHT: 1 })
	d.press_many(b, { BACK: 1 })
	d.step()
	d.lobby.set_ready(b, true)
	assert_bool(d.walk_through_town_door(a)).is_true()
	assert_int(d.lobby.state().cursor).is_equal(1)


func test_the_cursor_stays_where_it_was_after_a_run() -> void:
	d.press_many(a, { RIGHT: 1, SELECT: 1 })
	d.step(LobbyDriver.TO_A_CHOSEN_LEVEL)
	assert_object(d.lobby.phase).is_instanceof(Run)
	d.lobby.end_run(WorldState.Outcome.LOST)
	d.finish_result()
	d.lobby.set_ready(a, true)
	d.lobby.set_ready(b, true)
	assert_bool(d.walk_through_town_door(a)).is_true()
	assert_int(d.lobby.state().cursor).is_equal(1)


func test_moves_while_the_level_select_is_shut_dont_move_its_cursor() -> void:
	d.press_many(a, { RIGHT: 1 })
	d.press_many(b, { BACK: 1 })
	d.step()
	assert_bool(d.lobby.state().level_select_open).is_false()
	d.press_many(a, { RIGHT: 1 })
	assert_int(d.lobby.state().cursor).is_equal(1)


func test_the_world_stays_frozen_while_the_level_select_shows() -> void:
	var where := _positions()
	d.steer(a, Vector2.DOWN)
	d.step(3)
	assert_vector(d.lobby.world.players[a.player_id].pos).is_equal(where[a.player_id])


func test_a_newcomer_shuts_the_level_select() -> void:
	d.join("c")
	assert_bool(d.lobby.state().level_select_open).is_false()
	assert_int(a.participation).is_equal(Seat.Participation.READY)


func test_a_drop_frees_the_seat_and_leaves_the_level_select_open() -> void:
	d.lobby.drop(b)
	d.step()
	assert_int(d.lobby.seats().size()).is_equal(1)
	assert_bool(d.lobby.state().level_select_open).is_true()


func _positions() -> Dictionary[int, Vector2]:
	var out: Dictionary[int, Vector2] = {}
	for id: int in d.lobby.world.players:
		out[id] = d.lobby.world.players[id].pos
	return out
