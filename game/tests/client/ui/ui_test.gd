extends GdUnitTestSuite
## The UI shows what the GameView says: cards, labels, prompts, the timer
## and the middle line.

const GameTime := preload("res://shared/game_time.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Protocol := preload("res://net/protocol.gd")
const Lobby := preload("res://server/lobby.gd")
const World := preload("res://sim/world.gd")
const DummyKinds := preload("res://tests/dummy_kinds.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const GameView := preload("res://client/game_view.gd")
const LobbyUI := preload("res://client/ui/lobby_ui.gd")
const PlayerCard := preload("res://client/ui/player_card.gd")
const KeyPrompts := preload("res://client/ui/key_prompts.gd")
const LobbyUIScene := preload("res://client/ui/lobby_ui.tscn")
const CenterNoticeScene := preload("res://client/ui/center_notice.tscn")

## Idle long enough for the key prompts; not long enough.
const IDLE_SEC := GameView.PROMPT_IDLE_SEC
const BUSY_SEC := GameView.PROMPT_IDLE_SEC / 2

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


func _seat(id: int, readiness := LobbyState.Readiness.NOT_READY) -> LobbyState.Seat:
	var s := LobbyState.Seat.new()
	s.id = id
	s.readiness = readiness
	return s


func _lobby(phase: LobbyState.Phase, seats: Array) -> LobbyState:
	var state := LobbyState.new()
	state.phase = phase
	state.seats.assign(seats)
	return state


## Seat [param my_id] in [param lobby], connected as given, without the
## prompts.
func _state(lobby: LobbyState, my_id := 1, connected := true) -> GameView:
	return GameView.build(lobby, my_id, null, connected, BUSY_SEC)


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
	var s := _seat(1, LobbyState.Readiness.READY)
	assert_str(PlayerCard.status_text(s, LobbyState.Phase.TOWN)).is_equal(PlayerCard.READY_TEXT)
	s.readiness = LobbyState.Readiness.NOT_READY
	assert_str(PlayerCard.status_text(s, LobbyState.Phase.TOWN)) \
			.is_equal(PlayerCard.NOT_READY_TEXT)
	assert_str(PlayerCard.status_text(s, LobbyState.Phase.RUN)).is_empty()
	s.readiness = LobbyState.Readiness.SPECTATING
	assert_str(PlayerCard.status_text(s, LobbyState.Phase.RUN)).is_equal(PlayerCard.SPECTATING_TEXT)


func test_a_dropped_player_and_your_own_lost_connection_show_dc() -> void:
	var gone := _seat(2)
	gone.presence = LobbyState.Presence.DROPPED
	var lobby := _lobby(LobbyState.Phase.TOWN, [_seat(1), gone, _seat(3)])
	var lobby_ui := _lobby_ui(_state(lobby, 1, false))
	var dc := []
	for id in range(1, 4):
		dc.append(_card(lobby_ui, id).get_node("%Disconnected").visible)
	assert_array(dc).is_equal([true, true, false])


func test_the_bar_shows_health_and_a_late_joiners_is_full() -> void:
	var late := _seat(2)
	late.readiness = LobbyState.Readiness.SPECTATING
	var lobby := _lobby(LobbyState.Phase.RUN, [_seat(1), late])
	var view := Snapshot.new()
	var p := Snapshot.Player.new()
	p.id = 1
	p.health = World.player_max_health - 1
	view.players.append(p)
	var state := GameView.build(lobby, 1, view, true, BUSY_SEC)
	assert_int(LobbyUI.health_of(lobby.seats[0], state)).is_equal(p.health)
	assert_int(LobbyUI.health_of(late, state)).is_equal(World.player_max_health)


func test_only_a_ready_seats_bar_is_green() -> void:
	var lobby := _lobby(LobbyState.Phase.TOWN, [
		_seat(1, LobbyState.Readiness.READY),
		_seat(2, LobbyState.Readiness.NOT_READY),
		_seat(3, LobbyState.Readiness.SPECTATING),
	])
	var lobby_ui := _lobby_ui(_state(lobby, 1, true))
	var looks := []
	for id in range(1, 4):
		looks.append(_card(lobby_ui, id).get_node("%Bar").theme_type_variation)
	assert_array(looks).is_equal([PlayerCard.READY_BAR, &"", &""])


func test_prompts_hide_after_any_input_and_return_when_idle() -> void:
	var lobby := _lobby(LobbyState.Phase.TOWN, [_seat(1)])
	assert_bool(GameView.build(lobby, 1, null, true, IDLE_SEC).show_prompts).is_true()
	var busy := GameView.build(lobby, 1, null, true, BUSY_SEC)
	assert_bool(busy.show_prompts).is_false()
	var prompts: KeyPrompts = _lobby_ui(busy).get_node("%Prompts")
	assert_bool(prompts.visible).is_false()
	# The client's idle time when you've just got control back.
	var just_got_control := GameView.build(lobby, 1, null, true, INF)
	assert_bool(just_got_control.show_prompts).is_true()


func test_key_prompts_follow_the_input_map() -> void:
	var keys := {
		&"move_up": KEY_I, &"move_left": KEY_J, &"move_down": KEY_K, &"move_right": KEY_L,
		&"attack": KEY_U,
	}
	for action: StringName in keys:
		_bind(action, [_key(keys[action])])
	var lobby_ui := _lobby_ui(_state(_lobby(LobbyState.Phase.TOWN, [_seat(1)])))
	var caps := []
	for cap in ["%UpLabel", "%LeftLabel", "%DownLabel", "%RightLabel", "%SpaceLabel"]:
		caps.append(lobby_ui.get_node("%Prompts").get_node(cap).text)
	assert_array(caps).is_equal(["I", "J", "K", "L", "U"])


func test_key_prompts_name_the_first_key_and_mark_none() -> void:
	_bind(&"attack", [InputEventMouseButton.new(), _key(KEY_U), _key(KEY_J)])
	assert_str(KeyPrompts.key_name(&"attack")).is_equal("U")
	_bind(&"attack", [])
	assert_str(KeyPrompts.key_name(&"attack")).is_equal(KeyPrompts.UNBOUND)


func test_timer_rounds_up_to_whole_seconds() -> void:
	assert_str(LobbyUI.format_time(300 * GameTime.TICK_RATE)).is_equal("5:00")
	assert_str(LobbyUI.format_time(65 * GameTime.TICK_RATE - 1)).is_equal("1:05")
	assert_str(LobbyUI.format_time(1)).is_equal("0:01")
	assert_str(LobbyUI.format_time(0)).is_equal("0:00")


func test_every_server_reject_has_its_own_line() -> void:
	for reason: int in Protocol.RejectReason.values():
		assert_bool(GameView.REJECTED_TEXTS.has(reason)).is_true()


func test_the_middle_line_follows_the_connection_and_the_result() -> void:
	var town := _lobby(LobbyState.Phase.TOWN, [_seat(1)])
	var won := _lobby(LobbyState.Phase.RESULT, [_seat(1)])
	won.outcome = LobbyState.Outcome.WON
	var cases := [
		[_state(null, 0, false), GameView.CONNECTING_TEXT],
		[_state(town, 1, false), GameView.RECONNECTING_TEXT],
		[GameView.rejected(Protocol.RejectReason.FULL),
				GameView.REJECTED_TEXTS[Protocol.RejectReason.FULL]],
		[GameView.unsupported_browser(), GameView.UNSUPPORTED_BROWSER_TEXT],
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
