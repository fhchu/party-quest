extends GdUnitTestSuite
## Which prompts show, from how you've been playing.

const InputState := preload("res://client/input_state.gd")
const GameView := preload("res://client/game_view.gd")

## Long after the last move, so the move keys are back; soon after.
const LATER_SEC := InputState.PROMPT_IDLE_SEC * 2
const SOON_SEC := InputState.PROMPT_IDLE_SEC / 2


func test_move_keys_hide_after_moving_and_return_once_idle() -> void:
	var input := InputState.new()
	input.moved(0.0)
	assert_bool(input.prompts(SOON_SEC, true).show_move_keys).is_false()
	assert_bool(input.prompts(LATER_SEC, true).show_move_keys).is_true()


func test_getting_control_back_brings_the_move_keys_back_at_once() -> void:
	var input := InputState.new()
	input.moved(0.0)
	input.control_regained()
	assert_bool(input.prompts(SOON_SEC, true).show_move_keys).is_true()


func test_attacking_by_key_leaves_the_move_keys_up() -> void:
	var input := InputState.new()
	input.key_pressed(false)
	assert_bool(input.prompts(LATER_SEC, true).show_move_keys).is_true()


func test_a_touch_in_the_move_area_hides_the_move_keys_until_a_move_key() -> void:
	var input := InputState.new()
	input.screen_touched(true)
	assert_bool(input.prompts(LATER_SEC, true).show_move_keys).is_false()
	input.key_pressed(false)
	assert_bool(input.prompts(LATER_SEC, true).show_move_keys).is_false()
	input.key_pressed(true)
	assert_bool(input.prompts(LATER_SEC, true).show_move_keys).is_true()


func test_action_keys_show_until_a_touch() -> void:
	var input := InputState.new()
	assert_int(input.prompts(LATER_SEC, true).action_prompt).is_equal(GameView.ActionPrompt.KEYS)
	input.screen_touched(false)
	assert_int(input.prompts(LATER_SEC, true).action_prompt) \
			.is_equal(GameView.ActionPrompt.BUTTONS)


func test_a_joystick_touch_also_brings_up_the_touch_buttons() -> void:
	var input := InputState.new()
	input.screen_touched(true)
	assert_int(input.prompts(LATER_SEC, true).action_prompt) \
			.is_equal(GameView.ActionPrompt.BUTTONS)


func test_only_a_key_other_than_a_move_key_brings_back_the_action_keys() -> void:
	var input := InputState.new()
	input.screen_touched(false)
	input.key_pressed(true)
	assert_int(input.prompts(LATER_SEC, true).action_prompt) \
			.is_equal(GameView.ActionPrompt.BUTTONS)
	input.key_pressed(false)
	assert_int(input.prompts(LATER_SEC, true).action_prompt).is_equal(GameView.ActionPrompt.KEYS)


func test_nothing_shows_while_you_cannot_act() -> void:
	var input := InputState.new()
	input.screen_touched(false)
	var prompts := input.prompts(LATER_SEC, false)
	assert_bool(prompts.show_move_keys).is_false()
	assert_int(prompts.action_prompt).is_equal(GameView.ActionPrompt.NONE)
