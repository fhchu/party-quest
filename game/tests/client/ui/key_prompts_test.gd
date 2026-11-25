extends GdUnitTestSuite
## The key prompts caption each slot's key with its item's name, and keep
## every key in its place whatever the slots hold and whether they show.

const GameView := preload("res://client/game_view.gd")
const ClientLoader := preload("res://client/client_loader.gd")
const KeyPrompts := preload("res://client/ui/key_prompts.gd")
const KeyPromptsScene := preload("res://client/ui/key_prompts.tscn")

var _prompts: KeyPrompts


func before_test() -> void:
	_prompts = auto_free(KeyPromptsScene.instantiate())
	add_child(_prompts)


## An item named [param display_name].
func _item(display_name: String) -> GameView.ItemSlot:
	var slot := GameView.ItemSlot.new()
	slot.display_name = display_name
	return slot


func _caption(slot: int) -> String:
	return (_prompts.get_node("%%Slot%dCaption" % slot) as Label).text


## Where the move keys and each slot's keys are, once laid out.
func _key_places() -> Array:
	await await_idle_frame()
	var places := []
	for path in ["%Move", "%Slot1", "%Slot2"]:
		places.append((_prompts.get_node(path) as Control).global_position)
	return places


func test_each_slots_key_is_captioned_with_its_items_name() -> void:
	_prompts.show_prompts(false, true, _item("Blade"), _item("Buckler"))
	assert_array([_caption(1), _caption(2)]).is_equal(["Blade", "Buckler"])
	_prompts.show_prompts(false, true, _item("Buckler"), _item("Blade"))
	assert_array([_caption(1), _caption(2)]).is_equal(["Buckler", "Blade"])


func test_an_empty_slots_key_shows_without_a_caption() -> void:
	_prompts.show_prompts(false, true, _item("Blade"), _item("Buckler"))
	_prompts.show_prompts(false, true, null, null)
	assert_array([_caption(1), _caption(2)]).is_equal(["", ""])
	for path in ["%Slot1", "%Slot2"]:
		var keys: Control = _prompts.get_node(path)
		assert_bool(keys.is_visible_in_tree() and not is_zero_approx(keys.modulate.a)).is_true()


func test_the_keys_keep_their_places_whatever_item_the_slots_hold() -> void:
	_prompts.show_prompts(true, true, null, null)
	var empty := await _key_places()
	for look in ClientLoader.item_looks:
		var held := _item(look.display_name)
		_prompts.show_prompts(true, true, held, held)
		assert_array(await _key_places()) \
				.override_failure_message("moved for " + look.display_name).is_equal(empty)


func test_the_move_keys_keep_their_place_when_the_slot_keys_go() -> void:
	_prompts.show_prompts(true, true, null, null)
	var with_slot_keys := await _key_places()
	_prompts.show_prompts(true, false, null, null)
	var slot_1: Control = _prompts.get_node("%Slot1")
	assert_float(slot_1.modulate.a).is_zero()
	assert_array(await _key_places()).is_equal(with_slot_keys)
