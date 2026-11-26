extends GdUnitTestSuite
## Input actions over real connections; see ServerDriver.

const Player := preload("res://sim/player.gd")
const ServerDriver := preload("res://tests/server/server_driver.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")

var _d: ServerDriver


func before_test() -> void:
	_d = ServerDriver.new(get_tree())
	assert_int(_d.start_error()).is_equal(OK)


func after_test() -> void:
	_d.stop()


func test_resending_the_same_press_count_swings_once() -> void:
	var a := _d.join("a")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	var p: Player = _d.server.lobby.world.players[a.player_id]
	var one_press := PackedInt32Array([1])
	var swinging := func() -> bool:
		a.net.send_input(Vector2.ZERO, one_press, 0)
		return LobbyDriver.is_swinging(p)
	assert_bool(await _d.until(swinging)).is_true()
	var idle := func() -> bool:
		a.net.send_input(Vector2.ZERO, one_press, 0)
		return not LobbyDriver.is_swinging(p)
	assert_bool(await _d.until(idle)).is_true()
	# Long enough for every input already sent to have reached the world.
	var swing_over_by := _d.server.lobby.world.tick + LobbyDriver.swing_ticks()
	var later := func() -> bool:
		a.net.send_input(Vector2.ZERO, one_press, 0)
		return _d.server.lobby.world.tick >= swing_over_by
	assert_bool(await _d.until(later)).is_true()
	assert_bool(LobbyDriver.is_swinging(p)).is_false()


func test_a_held_input_action_reaches_the_player() -> void:
	var a := _d.join("a")
	assert_bool(await _d.until(func() -> bool: return a.player_id != 0)).is_true()
	var p: Player = _d.server.lobby.world.players[a.player_id]
	var held := func() -> bool:
		a.net.send_input(Vector2.ZERO, PackedInt32Array(), 0b10)
		return p.input_actions.size() > 1 and p.input_actions[1].held
	assert_bool(await _d.until(held)).is_true()
	assert_bool(p.input_actions[0].held).is_false()
