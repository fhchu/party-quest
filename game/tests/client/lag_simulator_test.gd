extends GdUnitTestSuite

const LagSimulator := preload("res://client/lag_simulator.gd")

const LAG_SEC := 0.1


func test_messages_wait_out_the_lag_in_order() -> void:
	var lag := LagSimulator.new(LAG_SEC, 0.0)
	var seen: Array[String] = []
	lag.outgoing(0.0, func() -> void: seen.append("sent"))
	lag.incoming(0.0, func() -> void: seen.append("received"))
	lag.flush(LAG_SEC / 2, func() -> bool: return true)
	assert_array(seen).is_empty()
	lag.flush(LAG_SEC, func() -> bool: return true)
	assert_array(seen).is_equal(["sent", "received"])


func test_sends_are_dropped_once_offline() -> void:
	var lag := LagSimulator.new(LAG_SEC, 0.0)
	var seen: Array[String] = []
	lag.outgoing(0.0, func() -> void: seen.append("sent"))
	lag.incoming(0.0, func() -> void: seen.append("received"))
	lag.flush(LAG_SEC, func() -> bool: return false)
	assert_array(seen).is_equal(["received"])
