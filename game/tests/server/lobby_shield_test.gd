extends GdUnitTestSuite
## The shield toggle dummy in town: hitting it gives or removes a shield.

const Lobby := preload("res://server/lobby.gd")
const PlayerData := preload("res://server/player_data.gd")
const Seat := preload("res://server/seat.gd")
const LobbyDriver := preload("res://tests/server/lobby_driver.gd")
const Item := preload("res://shared/data/item.gd")
const Items := preload("res://shared/data/items.gd")
const Player := preload("res://sim/player.gd")
const Action := preload("res://sim/action.gd")
const ActionGuard := preload("res://sim/action_guard.gd")

const SHIELD: Item = preload("res://shared/data/items/item_shield.tres")
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


func test_hitting_it_again_removes_the_shield_and_empties_its_slot() -> void:
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
	var shield := ITEMS.items.find(SHIELD)
	assert_int(seen.inventory.get(shield, 0)).is_equal(1)
	assert_int(seen.slot_items[Lobby.TOGGLED_SHIELD_SLOT]).is_equal(shield)


func test_hitting_it_gives_the_hitters_character_a_guard_in_that_slot() -> void:
	var a := d.join("a")
	d.swing_at(a, Lobby.TOGGLE_SHIELD)
	assert_object(_slot_action(a)).is_instanceof(ActionGuard)


func test_hitting_it_again_leaves_the_characters_slot_empty() -> void:
	var a := d.join("a")
	d.swing_at(a, Lobby.TOGGLE_SHIELD)
	d.swing_at(a, Lobby.TOGGLE_SHIELD)
	assert_object(_slot_action(a)).is_null()


func test_the_guard_comes_along_into_the_run() -> void:
	var a := d.join("a")
	d.swing_at(a, Lobby.TOGGLE_SHIELD)
	d.lobby.set_ready(a, true)
	assert_bool(d.lobby.start_run()).is_true()
	assert_object(_slot_action(a)).is_instanceof(ActionGuard)


func test_a_swing_that_toggles_the_shield_plays_out() -> void:
	var a := d.join("a")
	d.press_at(a, d.dummy_on_hit(Lobby.TOGGLE_SHIELD))
	var p: Player = d.lobby.world.players[a.player_id]
	for i in LobbyDriver.swing_ticks():
		if a.player_data.quantity_of(SHIELD.id) > 0:
			break
		d.step()
	assert_int(a.player_data.quantity_of(SHIELD.id)).is_equal(1)
	assert_bool(LobbyDriver.is_swinging(p)).is_true()


func _slot_action(seat: Seat) -> Action:
	var p: Player = d.lobby.world.players[seat.player_id]
	return p.slot_actions[Lobby.TOGGLED_SHIELD_SLOT]
