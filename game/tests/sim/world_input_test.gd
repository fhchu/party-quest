extends "res://tests/sim/world_fixture.gd"
## Input actions: which item slot a press uses, and what is held.


func test_only_the_input_action_whose_slot_holds_a_sword_swings() -> void:
	var sword := EquipItem.new()
	sword.action = EquipItem.Action.SWING
	var shield := EquipItem.new()
	shield.action = EquipItem.Action.GUARD
	var items: Array[EquipItem] = [shield, null, sword]
	WorldSimulator.set_slot_items(world, PLAYER_ID, items)
	_press(Vector2.ZERO, 0)
	_press(Vector2.ZERO, 1)
	WorldSimulator.step(world)
	assert_int(_player().state).is_equal(Player.State.IDLE)
	_press(Vector2.ZERO, 2)
	WorldSimulator.step(world)
	assert_int(_player().state).is_equal(Player.State.SWINGING)


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
