extends GdUnitTestSuite
## The UI shows what the GameView says: cards, labels, prompts, the timer
## and the middle line.

const LobbyState := preload("res://net/lobby_state.gd")
const WorldView := preload("res://client/world_view.gd")
const Protocol := preload("res://net/protocol.gd")
const Lobby := preload("res://server/lobby.gd")
const BALANCE := preload("res://shared/data/balance.tres")
const DummyKinds := preload("res://tests/dummy_kinds.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const GameView := preload("res://client/game_view.gd")
const ClientState := preload("res://client/client_state.gd")
const Client := preload("res://client/client.gd")
const LobbyUI := preload("res://client/ui/lobby_ui.gd")
const PlayerCard := preload("res://client/ui/player_card.gd")
const KeyPrompts := preload("res://client/ui/key_prompts.gd")
const LobbyUIScene := preload("res://client/ui/lobby_ui.tscn")
const CenterNoticeScene := preload("res://client/ui/center_notice.tscn")

## The project's bindings for each action a test rebound, put back after it.
var _saved_events := {}


func after_test() -> void:
	for action: StringName in _saved_events:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved_events[action]:
			InputMap.action_add_event(action, event)
	_saved_events.clear()


## Binds [param action] to [param events] only, until the test ends.
func _bind(action: StringName, events: Array[InputEvent]) -> void:
	if action not in _saved_events:
		_saved_events[action] = InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	for event in events:
		InputMap.action_add_event(action, event)


func _key(physical_keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	return event


func _seat(id: int, participation := LobbyState.Participation.NOT_READY) -> LobbyState.Seat:
	var s := LobbyState.Seat.new()
	s.id = id
	s.participation = participation
	return s


func _lobby(phase: LobbyState.Phase, seats: Array) -> LobbyState:
	var state := LobbyState.new()
	state.phase = phase
	state.seats.assign(seats)
	return state


## Seat [param my_id] in [param lobby], connected as given, without the
## prompts.
func _state(lobby: LobbyState, my_id := 1, connected := true) -> GameView:
	return ClientState.build_view(lobby, my_id, null, connected)


func _lobby_ui(state: GameView) -> LobbyUI:
	var lobby_ui: LobbyUI = auto_free(LobbyUIScene.instantiate())
	add_child(lobby_ui)
	lobby_ui.show_state(state)
	return lobby_ui


func _card(lobby_ui: LobbyUI, id: int) -> Node:
	return lobby_ui.get_node("%PartyBar").get_child(id - 1)


func test_only_occupied_seats_get_a_card_in_their_own_slot() -> void:
	var lobby_ui := _lobby_ui(_state(_lobby(LobbyState.Phase.TOWN, [_seat(1), _seat(3)])))
	var shown := []
	for id in range(1, Lobby.MAX_PLAYERS + 1):
		var card := _card(lobby_ui, id)
		assert_bool(card.visible).is_true()
		shown.append(card.get_node("%Card").visible)
	assert_array(shown).is_equal([true, false, true, false])


func test_the_bar_label_says_ready_spectating_or_nothing() -> void:
	var s := _seat(1, LobbyState.Participation.READY)
	assert_str(ClientState.status_text(s, LobbyState.Phase.TOWN)).is_equal(GameView.READY_TEXT)
	s.participation = LobbyState.Participation.NOT_READY
	assert_str(ClientState.status_text(s, LobbyState.Phase.TOWN)) \
			.is_equal(GameView.NOT_READY_TEXT)
	assert_str(ClientState.status_text(s, LobbyState.Phase.RUN)).is_empty()
	s.participation = LobbyState.Participation.SPECTATING
	assert_str(ClientState.status_text(s, LobbyState.Phase.RUN)).is_equal(GameView.SPECTATING_TEXT)


func test_a_dropped_player_and_your_own_lost_connection_show_dc() -> void:
	var gone := _seat(2)
	gone.connection = LobbyState.Connection.DROPPED
	var lobby := _lobby(LobbyState.Phase.TOWN, [_seat(1), gone, _seat(3)])
	var lobby_ui := _lobby_ui(_state(lobby, 1, false))
	var dc := []
	for id in range(1, 4):
		dc.append(_card(lobby_ui, id).get_node("%Disconnected").visible)
	assert_array(dc).is_equal([true, true, false])


func test_the_bar_shows_health_and_a_late_joiners_is_full() -> void:
	var late := _seat(2)
	late.participation = LobbyState.Participation.SPECTATING
	var lobby := _lobby(LobbyState.Phase.RUN, [_seat(1), late])
	var view := WorldView.new()
	var p := WorldView.Player.new()
	p.id = 1
	p.health = 1
	view.players.append(p)
	assert_int(ClientState.health_of(lobby.seats[0], view)).is_equal(1)
	assert_int(ClientState.health_of(late, view)).is_equal(BALANCE.player_max_health)


func test_only_a_ready_seats_bar_is_green() -> void:
	var lobby := _lobby(LobbyState.Phase.TOWN, [
		_seat(1, LobbyState.Participation.READY),
		_seat(2, LobbyState.Participation.NOT_READY),
		_seat(3, LobbyState.Participation.SPECTATING),
	])
	var lobby_ui := _lobby_ui(_state(lobby, 1, true))
	var looks := []
	for id in range(1, 4):
		looks.append(_card(lobby_ui, id).get_node("%Bar").theme_type_variation)
	assert_array(looks).is_equal([PlayerCard.READY_BAR, &"", &""])


## A view of town showing [param show_move_keys] and [param action_prompt].
func _prompting(show_move_keys: bool, action_prompt: GameView.ActionPrompt) -> GameView:
	var view := _state(_lobby(LobbyState.Phase.TOWN, [_seat(1)]))
	view.prompts.show_move_keys = show_move_keys
	view.prompts.action_prompt = action_prompt
	return view


## Whether the keys at [param path] show: they turn transparent rather than
## hide, so they keep their places.
func _keys_shown(lobby_ui: LobbyUI, path: NodePath) -> bool:
	var keys: Control = lobby_ui.get_node(path)
	return keys.is_visible_in_tree() and not is_zero_approx(keys.modulate.a)


func test_move_keys_and_action_keys_show_on_their_own() -> void:
	var lobby_ui := _lobby_ui(_prompting(false, GameView.ActionPrompt.KEYS))
	assert_bool(_keys_shown(lobby_ui, ^"%Prompts/%Move")).is_false()
	assert_bool(_keys_shown(lobby_ui, ^"%Prompts/%Slot1")).is_true()
	lobby_ui.show_state(_prompting(true, GameView.ActionPrompt.NONE))
	assert_bool(_keys_shown(lobby_ui, ^"%Prompts/%Move")).is_true()
	assert_bool(_keys_shown(lobby_ui, ^"%Prompts/%Slot1")).is_false()


func test_touch_buttons_replace_the_slot_keys() -> void:
	var lobby_ui := _lobby_ui(_prompting(false, GameView.ActionPrompt.BUTTONS))
	assert_bool(_keys_shown(lobby_ui, ^"%Prompts/%Slot1")).is_false()
	assert_bool(_keys_shown(lobby_ui, ^"%Prompts/%Slot2")).is_false()
	assert_bool(lobby_ui.get_node("%TouchControls/%AttackButton").visible).is_true()
	assert_bool(lobby_ui.get_node("%TouchControls/%Slot2Button").visible).is_true()
	lobby_ui.show_state(_prompting(false, GameView.ActionPrompt.KEYS))
	assert_bool(lobby_ui.get_node("%TouchControls/%AttackButton").visible).is_false()
	assert_bool(lobby_ui.get_node("%TouchControls/%Slot2Button").visible).is_false()


func test_the_attack_button_shows_slot_1s_icon_as_it_changes() -> void:
	var view := _prompting(false, GameView.ActionPrompt.BUTTONS)
	var slot := GameView.ItemSlot.new()
	slot.icon = PlaceholderTexture2D.new()
	var other := GameView.ItemSlot.new()
	other.icon = PlaceholderTexture2D.new()
	view.item_slots = [slot, other]
	var lobby_ui := _lobby_ui(view)
	var drawn: Sprite2D = lobby_ui.get_node("%TouchControls/%AttackButton/%Icon")
	assert_object(drawn.texture).is_same(slot.icon)
	view.item_slots = [other, slot]
	lobby_ui.show_state(view)
	assert_object(drawn.texture).is_same(other.icon)
	view.item_slots = [null, slot]
	lobby_ui.show_state(view)
	assert_object(drawn.texture).is_null()


## An item named [param display_name] with an icon of its own.
func _item(display_name: String) -> GameView.ItemSlot:
	var slot := GameView.ItemSlot.new()
	slot.display_name = display_name
	slot.icon = PlaceholderTexture2D.new()
	return slot


func test_an_empty_slots_button_shows_without_an_icon() -> void:
	var view := _prompting(false, GameView.ActionPrompt.BUTTONS)
	view.item_slots = [_item("Blade"), _item("Buckler")]
	var lobby_ui := _lobby_ui(view)
	view.item_slots = [null, null]
	lobby_ui.show_state(view)
	for button in ["%AttackButton", "%Slot2Button"]:
		var shown: Control = lobby_ui.get_node("%TouchControls").get_node(button)
		assert_bool(shown.visible).is_true()
		assert_object((shown.get_node("%Icon") as Sprite2D).texture).is_null()


func test_slot_2s_button_shows_slot_2s_icon_as_it_changes() -> void:
	var view := _prompting(false, GameView.ActionPrompt.BUTTONS)
	var first := _item("Blade")
	var second := _item("Buckler")
	view.item_slots = [first, second]
	var lobby_ui := _lobby_ui(view)
	var drawn: Sprite2D = lobby_ui.get_node("%TouchControls/%Slot2Button/%Icon")
	assert_object(drawn.texture).is_same(second.icon)
	view.item_slots = [second, first]
	lobby_ui.show_state(view)
	assert_object(drawn.texture).is_same(first.icon)


func test_key_prompts_follow_the_input_map() -> void:
	var keys := {
		&"move_up": KEY_I, &"move_left": KEY_J, &"move_down": KEY_K, &"move_right": KEY_L,
		&"use_item_1": KEY_U, &"use_item_2": KEY_O,
	}
	for action: StringName in keys:
		_bind(action, [_key(keys[action])])
	var lobby_ui := _lobby_ui(_state(_lobby(LobbyState.Phase.TOWN, [_seat(1)])))
	var caps := []
	for cap in ["%UpLabel", "%LeftLabel", "%DownLabel", "%RightLabel", "%UseItem1KeyLabel",
			"%UseItem2KeyLabel"]:
		caps.append(lobby_ui.get_node("%Prompts").get_node(cap).text)
	assert_array(caps).is_equal(["I", "J", "K", "L", "U", "O"])


func test_key_prompts_name_the_first_key_and_mark_none() -> void:
	_bind(&"use_item_1", [InputEventMouseButton.new(), _key(KEY_U), _key(KEY_J)])
	assert_str(KeyPrompts.key_name(&"use_item_1")).is_equal("U")
	_bind(&"use_item_1", [])
	assert_str(KeyPrompts.key_name(&"use_item_1")).is_equal(KeyPrompts.UNBOUND)


func test_timer_rounds_up_to_whole_seconds() -> void:
	assert_str(ClientState.format_time(300 * GameTime.TICK_RATE)).is_equal("5:00")
	assert_str(ClientState.format_time(65 * GameTime.TICK_RATE - 1)).is_equal("1:05")
	assert_str(ClientState.format_time(1)).is_equal("0:01")
	assert_str(ClientState.format_time(0)).is_equal("0:00")


func test_every_server_reject_has_its_own_line() -> void:
	for reason: int in Protocol.RejectReason.values():
		assert_bool(Client.REJECTED_TEXTS.has(reason)).is_true()


func test_the_middle_line_follows_the_connection_and_the_result() -> void:
	var town := _lobby(LobbyState.Phase.TOWN, [_seat(1)])
	var won := _lobby(LobbyState.Phase.RESULT, [_seat(1)])
	won.outcome = LobbyState.Outcome.WON
	var cases := [
		[_state(null, 0, false), GameView.CONNECTING_TEXT],
		[_state(town, 1, false), GameView.RECONNECTING_TEXT],
		[GameView.only_notice(Client.REJECTED_TEXTS[Protocol.RejectReason.FULL]),
				Client.REJECTED_TEXTS[Protocol.RejectReason.FULL]],
		[GameView.only_notice(Client.UNSUPPORTED_BROWSER_TEXT),
				Client.UNSUPPORTED_BROWSER_TEXT],
		[_state(won), GameView.WON_TEXT],
		[_state(town), ""],
	]
	var notice: Control = auto_free(CenterNoticeScene.instantiate())
	add_child(notice)
	for c: Array in cases:
		var state: GameView = c[0]
		assert_str(state.notice).is_equal(c[1])
		notice.show_text(state.notice)
		assert_bool(notice.visible).is_equal(c[1] != "")


func test_town_waits_for_ready_until_everyone_is() -> void:
	var lobby := _lobby(LobbyState.Phase.TOWN, [_seat(1)])
	assert_bool(_state(lobby).waiting_for_ready).is_true()
	lobby.all_ready = true
	assert_bool(_state(lobby).waiting_for_ready).is_false()
	lobby.phase = LobbyState.Phase.RUN
	lobby.all_ready = false
	assert_bool(_state(lobby).waiting_for_ready).is_false()
