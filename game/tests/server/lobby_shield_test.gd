extends GdUnitTestSuite
## The shield toggle dummy in town: hitting it gives or takes a shield.

const Lobby := preload("res://server/lobby.gd")
const PlayerData := preload("res://server/player_data.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const Item := preload("res://shared/data/item.gd")
const Items := preload("res://shared/data/items.gd")

const SHIELD: Item = preload("res://shared/data/items/shield.tres")
const ITEMS: Items = preload("res://shared/data/items.tres")

var d: LobbyDriver


func before_test() -> void:
	d = LobbyDriver.new()


func test_hitting_it_gives_the_hitter_a_shield_in_its_slot() -> void:
	var a := d.join("a")
	var b := d.join("b")
	assert_int(a.player_data.quantity_of(SHIELD.id)).is_equal(0)
	assert_bool(d.swing_at(a, Lobby.TOGGLE_SHIELD)).is_true()
	assert_int(a.player_data.quantity_of(SHIELD.id)).is_equal(1)
	assert_str(a.player_data.slot_items[Lobby.TOGGLED_SHIELD_SLOT]).is_equal(SHIELD.id)
	assert_int(b.player_data.quantity_of(SHIELD.id)).is_equal(0)


func test_hitting_it_again_takes_the_shield_and_empties_its_slot() -> void:
	var a := d.join("a")
	d.swing_at(a, Lobby.TOGGLE_SHIELD)
	d.swing_at(a, Lobby.TOGGLE_SHIELD)
	assert_int(a.player_data.quantity_of(SHIELD.id)).is_equal(0)
	assert_str(a.player_data.slot_items[Lobby.TOGGLED_SHIELD_SLOT]).is_equal(
			PlayerData.EMPTY_SLOT)


func test_clients_see_the_shield_once_given() -> void:
	var a := d.join("a")
	d.swing_at(a, Lobby.TOGGLE_SHIELD)
	var seen := d.lobby.state().find_seat(a.player_id)
	var shield := ITEMS.index_of_id(SHIELD.id)
	assert_int(seen.inventory.get(shield, 0)).is_equal(1)
	assert_int(seen.slot_items[Lobby.TOGGLED_SHIELD_SLOT]).is_equal(shield)
