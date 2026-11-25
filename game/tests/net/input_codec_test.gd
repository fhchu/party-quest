extends GdUnitTestSuite

const InputCodec := preload("res://net/input_codec.gd")
const Protocol := preload("res://net/protocol.gd")


func test_every_input_action_has_a_held_bit_and_a_counter() -> void:
	assert_int(Protocol.INPUT_ACTIONS.size()).is_less_equal(Protocol.INPUT_ACTION_COUNT)
	# The held bits travel in one byte.
	assert_int(Protocol.INPUT_ACTION_COUNT).is_less_equal(8)


func test_an_input_comes_back_as_it_was_sent() -> void:
	var counters := PackedByteArray()
	for i in Protocol.INPUT_ACTION_COUNT:
		counters.append((i * 5 + 3) % Protocol.PRESS_COUNTER_MODULUS)
	counters[1] = Protocol.PRESS_COUNTER_MODULUS - 1
	var held := 0b10100101
	var back := InputCodec.unpack(InputCodec.pack(Vector2(0.5, -1.0), counters, held))
	assert_vector(back.move).is_equal_approx(
			Vector2(0.5, -1.0), Vector2.ONE / InputCodec.MOVE_SCALE)
	assert_array(Array(back.press_counters)).is_equal(Array(counters))
	assert_int(back.held_bits).is_equal(held)


func test_a_move_past_one_is_sent_as_one() -> void:
	var back := InputCodec.unpack(InputCodec.pack(Vector2(3.0, -3.0), PackedByteArray(), 0))
	assert_vector(back.move).is_equal(Vector2(1.0, -1.0))


func test_bytes_of_the_wrong_length_are_refused() -> void:
	var bytes := InputCodec.pack(Vector2.ZERO, PackedByteArray(), 0)
	bytes.append(0)
	assert_object(InputCodec.unpack(bytes)).is_null()
	assert_object(InputCodec.unpack(PackedByteArray())).is_null()
