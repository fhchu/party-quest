extends GdUnitTestSuite
## The client peer's simulated lag, against a real game server.

const Protocol := preload("res://net/protocol.gd")
const LagSimulator := preload("res://client/lag_simulator.gd")
const ServerDriver := preload("res://tests/server/server_driver.gd")

## One way, well past the server's kick delay.
const LAG_SEC := ServerDriver.SETTLE_SEC * 3

var _d: ServerDriver


func before_test() -> void:
	_d = ServerDriver.new(get_tree())
	assert_int(_d.start_error()).is_equal(OK)


func after_test() -> void:
	_d.stop()


func test_reject_arrives_before_the_close() -> void:
	var c := _d.join("a", "other", LagSimulator.new(LAG_SEC, 0.0))
	var seen: Array[String] = []
	c.net.rejected.connect(func(_reason: Protocol.RejectReason) -> void: seen.append("rejected"))
	c.api.server_disconnected.connect(func() -> void: seen.append("closed"))
	assert_bool(await _d.until(func() -> bool: return "closed" in seen)).is_true()
	assert_array(seen).is_equal(["rejected", "closed"])


func test_lag_delays_both_ways() -> void:
	var started := Time.get_ticks_msec()
	var c := _d.join("a", Protocol.build_id(), LagSimulator.new(LAG_SEC, 0.0))
	assert_bool(await _d.until(func() -> bool: return c.player_id != 0)).is_true()
	# Connecting, hello and welcome each wait out the lag once.
	assert_float((Time.get_ticks_msec() - started) / 1000.0).is_greater_equal(LAG_SEC * 3)
