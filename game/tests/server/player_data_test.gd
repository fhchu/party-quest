extends GdUnitTestSuite
## A player's inventory and item slots.

const PlayerData := preload("res://server/player_data.gd")
const Items := preload("res://shared/data/items.gd")
const EquipItem := preload("res://shared/data/items/equip_item.gd")

const STARTING: PlayerData = preload("res://server/data/starting_player_data.tres")
const ITEMS: Items = preload("res://shared/data/items.tres")


func _data_with(id: String, quantity: int) -> PlayerData:
	var data := PlayerData.new()
	data.add_item(id, quantity)
	data.slot_items.assign([PlayerData.EMPTY_SLOT, id])
	return data


func test_adding_an_item_adds_to_what_they_own() -> void:
	var data := _data_with("coin", 3)
	data.add_item("coin", 4)
	assert_int(data.quantity_of("coin")).is_equal(7)


func test_an_item_they_never_owned_counts_0() -> void:
	assert_int(PlayerData.new().quantity_of("coin")).is_equal(0)


func test_removing_some_keeps_the_rest_in_its_slot() -> void:
	var data := _data_with("coin", 3)
	data.remove_item("coin", 2)
	assert_int(data.quantity_of("coin")).is_equal(1)
	assert_str(data.slot_items[1]).is_equal("coin")


func test_removing_the_last_one_empties_its_slot() -> void:
	var data := _data_with("coin", 3)
	data.remove_item("coin", 3)
	assert_bool(data.inventory.has("coin")).is_false()
	assert_str(data.slot_items[1]).is_equal(PlayerData.EMPTY_SLOT)


func test_removing_the_last_one_leaves_other_slots() -> void:
	var data := _data_with("coin", 1)
	data.add_item("blade", 1)
	data.slot_items[0] = "blade"
	data.remove_item("coin", 1)
	assert_str(data.slot_items[0]).is_equal("blade")


func test_the_starting_data_owns_every_item_in_its_slots() -> void:
	for id in _starting_slotted():
		assert_int(STARTING.quantity_of(id)).override_failure_message(
				"%s isn't owned" % id).is_greater(0)


func test_the_starting_data_names_only_listed_items() -> void:
	for id in STARTING.inventory:
		assert_int(ITEMS.index_of_id(id)).override_failure_message(
				"%s isn't listed" % id).is_not_equal(-1)


func test_the_starting_data_slots_only_equip_items() -> void:
	for id in _starting_slotted():
		assert_object(ITEMS.items[ITEMS.index_of_id(id)]).override_failure_message(
				"%s can't be equipped" % id).is_instanceof(EquipItem)


## The items in the starting data's slots, skipping empty ones.
func _starting_slotted() -> Array[String]:
	var out: Array[String] = []
	out.assign(Array(STARTING.slot_items).filter(
			func(id: String) -> bool: return id != PlayerData.EMPTY_SLOT))
	return out
