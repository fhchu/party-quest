extends GdUnitTestSuite
## Turning the press counters a client sends back into presses.

const Server := preload("res://server/server.gd")
const Protocol := preload("res://net/protocol.gd")


func test_presses_are_counted_across_a_counters_wrap() -> void:
	var last := PackedByteArray([Protocol.PRESS_COUNTER_MODULUS - 1, 0])
	var presses := Server.presses_between(last, PackedByteArray([1, 2]))
	assert_int(presses[0]).is_equal(2)
	assert_int(presses[1]).is_equal(2)


func test_the_same_counters_again_are_no_presses() -> void:
	var counters := PackedByteArray([0, 0, 3])
	assert_int(Server.presses_between(counters, counters)[2]).is_equal(0)


func test_a_new_connection_counts_from_zero() -> void:
	var presses := Server.presses_between(PackedByteArray(), PackedByteArray([0, 3]))
	assert_int(presses[1]).is_equal(3)
