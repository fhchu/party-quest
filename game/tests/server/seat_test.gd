extends GdUnitTestSuite

const Seat := preload("res://server/seat.gd")
const Protocol := preload("res://net/protocol.gd")


func test_presses_are_counted_across_a_counters_wrap() -> void:
	var seat := Seat.new()
	var counters := PackedByteArray()
	counters.resize(Protocol.INPUT_ACTION_COUNT)
	counters[0] = Protocol.PRESS_COUNTER_MODULUS - 1
	assert_int(seat.take_presses(counters)[0]).is_equal(Protocol.PRESS_COUNTER_MODULUS - 1)
	counters[0] = 1
	counters[1] = 2
	var presses := seat.take_presses(counters)
	assert_int(presses[0]).is_equal(2)
	assert_int(presses[1]).is_equal(2)


func test_the_same_counters_again_are_no_presses() -> void:
	var seat := Seat.new()
	var counters := PackedByteArray()
	counters.resize(Protocol.INPUT_ACTION_COUNT)
	counters[2] = 3
	seat.take_presses(counters)
	assert_int(seat.take_presses(counters)[2]).is_equal(0)
