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


func test_menu_presses_read_each_input_action_by_its_number() -> void:
	var presses := PackedByteArray()
	presses.resize(Protocol.INPUT_ACTION_COUNT)
	# A different count for each, so a swapped pair shows.
	for action: int in Protocol.InputAction.values():
		presses[action] = action + 1
	var menu := Server.menu_presses_of(presses)
	assert_int(menu.select).is_equal(Protocol.InputAction.USE_ITEM_1 + 1)
	assert_int(menu.back).is_equal(Protocol.InputAction.USE_ITEM_2 + 1)
	assert_int(menu.up).is_equal(Protocol.InputAction.MOVE_UP + 1)
	assert_int(menu.left).is_equal(Protocol.InputAction.MOVE_LEFT + 1)
	assert_int(menu.down).is_equal(Protocol.InputAction.MOVE_DOWN + 1)
	assert_int(menu.right).is_equal(Protocol.InputAction.MOVE_RIGHT + 1)
