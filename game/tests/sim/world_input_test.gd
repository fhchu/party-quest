extends "res://tests/sim/world_fixture.gd"
## Input actions: which item slot a press uses, and what is held.


func test_only_the_input_action_whose_slot_holds_a_sword_swings() -> void:
	var sword := _sword()
	var shield := ItemShield.new()
	shield.action = EquipItem.Action.GUARD
	var items: Array[EquipItem] = [shield, null, sword]
	WorldSimulator.set_slot_items(world, PLAYER_ID, items)
	var sword_action := _player().slot_actions[2]
	_press(Vector2.ZERO, 0)
	_press(Vector2.ZERO, 1)
	WorldSimulator.step(world)
	assert_bool(sword_action.is_busy()).is_false()
	_press(Vector2.ZERO, 2)
	WorldSimulator.step(world)
	assert_bool(sword_action.is_busy()).is_true()


func test_an_input_action_is_held_until_an_input_lets_go() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, PackedByteArray([0, 0]), 0b10)
	assert_bool(_player().input_actions[1].held).is_true()
	assert_bool(_player().input_actions[0].held).is_false()
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.ZERO, PackedByteArray([0, 0]), 0)
	assert_bool(_player().input_actions[1].held).is_false()


func test_stopping_a_player_lets_go_of_its_input_actions() -> void:
	WorldSimulator.set_input(world, PLAYER_ID, Vector2.RIGHT, PackedByteArray([0]), 1)
	assert_bool(_player().input_actions[0].held).is_true()
	WorldSimulator.stop_player(world, PLAYER_ID)
	assert_bool(_player().input_actions[0].held).is_false()
	assert_vector(_player().move).is_equal(Vector2.ZERO)


func test_a_press_on_the_tick_a_swing_ends_starts_the_next() -> void:
	_press()
	_advance(SWING_TICKS)
	_press()
	WorldSimulator.step(world)
	assert_int(_player().slot_actions[SWORD_INPUT].slot_ticks()).is_equal(1)


func test_a_press_mid_swing_is_dropped() -> void:
	_press()
	_advance(SWING_TICKS - 1)
	_press()
	_advance(2)
	assert_bool(_is_swinging()).is_false()


func test_a_press_while_pushed_is_dropped() -> void:
	_player().push(Vector2(10, 0), 3)
	_press()
	_advance(4)
	assert_bool(_player().is_pushed()).is_false()
	assert_bool(_is_swinging()).is_false()
