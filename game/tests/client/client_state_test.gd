extends GdUnitTestSuite

const ClientState := preload("res://client/client_state.gd")
const ClientLoader := preload("res://client/client_loader.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const WorldView := preload("res://client/world_view.gd")
const GameView := preload("res://client/game_view.gd")


func _lobby(phase: LobbyState.Phase, seats: Array[LobbyState.Seat]) -> LobbyState:
	var state := LobbyState.new()
	state.phase = phase
	state.seats.assign(seats)
	return state


func _seat(id: int, participation := LobbyState.Participation.NOT_READY) -> LobbyState.Seat:
	var s := LobbyState.Seat.new()
	s.id = id
	s.participation = participation
	return s


func test_a_connected_seated_player_can_act_in_town_and_the_run() -> void:
	for phase: LobbyState.Phase in [LobbyState.Phase.TOWN, LobbyState.Phase.RUN]:
		assert_bool(ClientState.can_act(_lobby(phase, [_seat(1)]), 1, true)).is_true()


func test_nobody_can_act_without_a_lobby_a_connection_or_during_the_result() -> void:
	var town := _lobby(LobbyState.Phase.TOWN, [_seat(1)])
	assert_bool(ClientState.can_act(null, 1, true)).is_false()
	assert_bool(ClientState.can_act(town, 1, false)).is_false()
	var result := _lobby(LobbyState.Phase.RESULT, [_seat(1)])
	assert_bool(ClientState.can_act(result, 1, true)).is_false()


func test_a_spectator_or_someone_without_a_seat_cannot_act() -> void:
	var late := _seat(2, LobbyState.Participation.SPECTATING)
	var in_run := _lobby(LobbyState.Phase.RUN, [_seat(1), late])
	assert_bool(ClientState.can_act(in_run, 2, true)).is_false()
	assert_bool(ClientState.can_act(in_run, 3, true)).is_false()


func test_each_input_action_counts_its_own_presses() -> void:
	var known := ClientState.new(false, 0.0)
	known.input_action_pressed(1, 1.0)
	known.input_action_pressed(1, 1.0)
	known.input_action_pressed(0, 1.0)
	assert_int(known.press_counts[0]).is_equal(1)
	assert_int(known.press_counts[1]).is_equal(2)


func test_a_welcome_starts_the_press_counts_over() -> void:
	var known := ClientState.new(false, 0.0)
	known.input_action_pressed(1, 1.0)
	assert_int(known.press_counts[1]).is_equal(1)
	known.welcomed(2, 0.0)
	assert_int(known.press_counts[1]).is_equal(0)
	assert_int(known.player_id).is_equal(2)


func test_a_lobby_state_naming_your_seat_moves_you_there() -> void:
	var known := ClientState.new(false, 0.0)
	known.welcomed(3, 0.0)
	var state := _lobby(LobbyState.Phase.TOWN, [_seat(1), _seat(2)])
	state.you = 2
	known.lobby_received(state)
	assert_int(known.player_id).is_equal(2)


func _in_town() -> ClientState:
	var known := ClientState.new(false, 0.0)
	known.welcomed(1, 0.0)
	known.lobby_received(_lobby(LobbyState.Phase.TOWN, [_seat(1)]))
	return known


func test_move_keys_show_on_getting_control_and_hide_after_moving() -> void:
	var known := _in_town()
	assert_bool(known.view(1.0, true).prompts.show_move_keys).is_true()
	known.input_sent(1.0, Vector2.RIGHT)
	assert_bool(known.view(1.0, true).prompts.show_move_keys).is_false()


func test_a_zero_move_isnt_moving() -> void:
	var known := _in_town()
	known.input_sent(1.0, Vector2.ZERO)
	assert_bool(known.view(1.0, true).prompts.show_move_keys).is_true()


func test_a_new_run_brings_the_move_keys_back_at_once() -> void:
	var known := _in_town()
	known.input_sent(1.0, Vector2.RIGHT)
	known.view(1.0, true)
	known.lobby_received(_lobby(LobbyState.Phase.RUN, [_seat(1)]))
	assert_bool(known.view(1.0, true).prompts.show_move_keys).is_true()


func test_no_prompts_while_you_cannot_act() -> void:
	var known := ClientState.new(false, 0.0)
	known.welcomed(2, 0.0)
	known.lobby_received(_lobby(LobbyState.Phase.RUN,
			[_seat(1), _seat(2, LobbyState.Participation.SPECTATING)]))
	var prompts := known.view(1.0, true).prompts
	assert_bool(prompts.show_move_keys).is_false()
	assert_int(prompts.action_prompt).is_equal(GameView.ActionPrompt.NONE)


func test_turned_away_forgets_the_lobby() -> void:
	var known := ClientState.new(false, 0.0)
	known.lobby_received(_lobby(LobbyState.Phase.TOWN, [_seat(1)]))
	known.rejected()
	assert_object(known.lobby).is_null()


func test_a_snapshot_keeps_its_timer_or_lack_of_one_when_drawn() -> void:
	var snap := Snapshot.new()
	assert_int(ClientState.world_view_of(snap).run_ticks_left).is_equal(WorldView.NO_TIMER)
	snap.run_ticks_left = 90
	assert_int(ClientState.world_view_of(snap).run_ticks_left).is_equal(90)


func test_a_snapshot_keeps_its_graphics_seed_when_drawn() -> void:
	var snap := Snapshot.new()
	snap.graphics_seed = 1234
	assert_int(ClientState.world_view_of(snap).graphics_seed).is_equal(1234)


func test_the_gold_shown_is_your_seats() -> void:
	var mine := _seat(2)
	mine.inventory[ClientLoader.gold_index] = 5
	var theirs := _seat(1)
	theirs.inventory[ClientLoader.gold_index] = 9
	var view := ClientState.build_view(_lobby(LobbyState.Phase.TOWN, [theirs, mine]), 2, null, true)
	assert_str(view.gold_text).is_equal(GameView.GOLD_TEXT % 5)


func test_a_seat_with_no_gold_shows_0() -> void:
	var view := ClientState.build_view(_lobby(LobbyState.Phase.TOWN, [_seat(1)]), 1, null, true)
	assert_str(view.gold_text).is_equal(GameView.GOLD_TEXT % 0)


func _item_look(display_name: String) -> ClientLoader.ItemLook:
	var look := ClientLoader.ItemLook.new()
	look.display_name = display_name
	look.icon = PlaceholderTexture2D.new()
	return look


func test_your_slots_show_their_items_in_slot_order() -> void:
	var real_looks := ClientLoader.item_looks
	# The real icons are missing where the art is.
	var looks: Array[ClientLoader.ItemLook] = [
			_item_look("first"), _item_look("second"), _item_look("third")]
	ClientLoader.item_looks = looks
	var mine := _seat(2)
	mine.slot_items = PackedInt32Array([LobbyState.NO_ITEM, 2, 1])
	var theirs := _seat(1)
	theirs.slot_items = PackedInt32Array([0])
	var view := ClientState.build_view(_lobby(LobbyState.Phase.TOWN, [theirs, mine]), 2, null, true)
	ClientLoader.item_looks = real_looks
	assert_int(view.item_slots.size()).is_equal(3)
	assert_object(view.item_slots[0]).is_null()
	assert_str(view.item_slots[1].display_name).is_equal("third")
	assert_object(view.item_slots[1].icon).is_same(looks[2].icon)
	assert_str(view.item_slots[2].display_name).is_equal("second")
	assert_object(view.item_slots[2].icon).is_same(looks[1].icon)


func test_every_seats_slots_get_their_items_looks() -> void:
	var real_looks := ClientLoader.item_looks
	var looks: Array[ClientLoader.ItemLook] = [_item_look("first"), _item_look("second")]
	ClientLoader.item_looks = looks
	var mine := _seat(2)
	mine.slot_items = PackedInt32Array([1])
	var theirs := _seat(1)
	theirs.slot_items = PackedInt32Array([LobbyState.NO_ITEM, 0])
	var view := ClientState.build_view(_lobby(LobbyState.Phase.TOWN, [theirs, mine]), 2, null, true)
	ClientLoader.item_looks = real_looks
	assert_array(view.slot_looks[2]).is_equal([looks[1]])
	assert_array(view.slot_looks[1]).is_equal([null, looks[0]])


func test_a_notice_is_all_the_screen_shows() -> void:
	var known := ClientState.new(false, 0.0)
	known.welcomed(1, 0.0)
	known.lobby_received(_lobby(LobbyState.Phase.TOWN, [_seat(1)]))
	var view := known.view(1.0, true, "turned away")
	assert_str(view.notice).is_equal("turned away")
	assert_bool(view.in_lobby).is_false()
	assert_array(view.cards).is_empty()


func test_the_hud_shows_the_average_ping() -> void:
	var known := ClientState.new(false, 0.0)
	known.ping_measured(1.0, 30.0)
	known.ping_measured(2.0, 50.0)
	assert_str(known.view(2.0, true).ping_text).is_equal(GameView.PING_TEXT % 40)


func test_without_a_live_connection_the_hud_shows_no_ping() -> void:
	var known := ClientState.new(false, 0.0)
	known.ping_measured(1.0, 30.0)
	assert_str(known.view(1.0, false).ping_text).is_empty()
