extends GdUnitTestSuite
## Input actions through the Lobby: press counters per connection.

const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const Player := preload("res://sim/player.gd")

var d: LobbyDriver


func before_test() -> void:
	d = LobbyDriver.new()


func test_a_rejoin_counts_presses_from_zero() -> void:
	var a := d.start_with(["a"])[0]
	d.press(a)
	d.lobby.drop(a)
	d.join("a")
	# The client's first press after its welcome sends a counter of 1.
	var counters := PackedByteArray()
	counters.resize(a.press_counters.size())
	counters[0] = 1
	d.lobby.input(a, Vector2.ZERO, counters, 0, d.now)
	d.step()
	assert_int(d.lobby.world.players[a.player_id].state).is_equal(Player.State.SWINGING)
