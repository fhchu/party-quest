extends GdUnitTestSuite
## The UI shows what the HudState says: cards, labels, prompts, the timer
## and the middle line.

const RoomState := preload("res://net/room_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Protocol := preload("res://net/protocol.gd")
const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")
const ArenaView := preload("res://client/arena_view.gd")
const HudState := preload("res://client/ui/hud_state.gd")
const RoomHud := preload("res://client/ui/room_hud.gd")
const PlayerCard := preload("res://client/ui/player_card.gd")
const KeyPrompts := preload("res://client/ui/key_prompts.gd")
const RoomHudScene := preload("res://client/ui/room_hud.tscn")
const CenterNoticeScene := preload("res://client/ui/center_notice.tscn")

const NOW := 100.0
const LONG_AGO := NOW - HudState.PROMPT_IDLE_SEC
const JUST_NOW := NOW - HudState.PROMPT_IDLE_SEC / 2

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


func _seat(id: int, readiness := RoomState.Readiness.NOT_READY) -> RoomState.Seat:
	var s := RoomState.Seat.new()
	s.id = id
	s.readiness = readiness
	return s


func _room(phase: RoomState.Phase, seats: Array) -> RoomState:
	var state := RoomState.new()
	state.phase = phase
	state.seats.assign(seats)
	return state


## Seat [param my_id] in [param room], connected as given, idle long enough
## for the prompts.
func _state(room: RoomState, my_id := 1, is_connected := true) -> HudState:
	var s := HudState.build(room, my_id, null, is_connected, "")
	s.set_prompts(NOW, LONG_AGO)
	return s


func _hud(state: HudState) -> RoomHud:
	var hud: RoomHud = auto_free(RoomHudScene.instantiate())
	add_child(hud)
	hud.show_state(state)
	return hud


func _card(hud: RoomHud, id: int) -> Node:
	return hud.get_node("%PartyBar").get_child(id - 1)


func test_only_occupied_seats_get_a_card_in_their_own_slot() -> void:
	var hud := _hud(_state(_room(RoomState.Phase.LOBBY, [_seat(1), _seat(3)])))
	var shown := []
	for id in range(1, Protocol.MAX_PLAYERS + 1):
		var card := _card(hud, id)
		assert_bool(card.visible).is_true()
		shown.append(card.get_node("%Card").visible)
	assert_array(shown).is_equal([true, false, true, false])


func test_the_bar_label_says_ready_waiting_or_nothing() -> void:
	var s := _seat(1, RoomState.Readiness.READY)
	assert_str(PlayerCard.status_text(s, RoomState.Phase.LOBBY)).is_equal(PlayerCard.READY_TEXT)
	s.readiness = RoomState.Readiness.NOT_READY
	assert_str(PlayerCard.status_text(s, RoomState.Phase.LOBBY)) \
			.is_equal(PlayerCard.NOT_READY_TEXT)
	assert_str(PlayerCard.status_text(s, RoomState.Phase.MATCH)).is_empty()
	s.readiness = RoomState.Readiness.SPECTATING
	assert_str(PlayerCard.status_text(s, RoomState.Phase.MATCH)).is_equal(PlayerCard.WAITING_TEXT)


func test_a_dropped_player_and_your_own_lost_connection_show_dc() -> void:
	var gone := _seat(2)
	gone.presence = RoomState.Presence.DROPPED
	var room := _room(RoomState.Phase.LOBBY, [_seat(1), gone, _seat(3)])
	var hud := _hud(_state(room, 1, false))
	var dc := []
	for id in range(1, 4):
		dc.append(_card(hud, id).get_node("%Disconnected").visible)
	assert_array(dc).is_equal([true, true, false])


func test_the_bar_shows_health_and_a_late_joiner_has_none() -> void:
	var late := _seat(2)
	late.readiness = RoomState.Readiness.SPECTATING
	var room := _room(RoomState.Phase.MATCH, [_seat(1), late])
	var view := Snapshot.new()
	var p := Snapshot.Player.new()
	p.id = 1
	p.health = Tuning.player_max_health - 1
	view.players.append(p)
	var state := HudState.build(room, 1, view, true, "")
	assert_int(RoomHud.health_of(room.seats[0], state)).is_equal(p.health)
	assert_int(RoomHud.health_of(late, state)).is_equal(0)


func test_prompts_hide_after_any_input_and_return_when_idle() -> void:
	var room := _room(RoomState.Phase.LOBBY, [_seat(1)])
	assert_bool(_state(room).show_prompts).is_true()
	var busy := HudState.build(room, 1, null, true, "")
	busy.set_prompts(NOW, JUST_NOW)
	assert_bool(busy.show_prompts).is_false()
	var prompts: KeyPrompts = _hud(busy).get_node("%Prompts")
	assert_bool(prompts.visible).is_false()
	var just_got_control := HudState.build(room, 1, null, true, "")
	just_got_control.set_prompts(NOW, -INF)
	assert_bool(just_got_control.show_prompts).is_true()


func test_only_someone_who_can_act_sees_prompts() -> void:
	var late := _seat(2)
	late.readiness = RoomState.Readiness.SPECTATING
	var in_match := _room(RoomState.Phase.MATCH, [_seat(1), late])
	assert_bool(_state(in_match, 2).show_prompts).is_false()
	assert_bool(_state(in_match, 1, false).show_prompts).is_false()
	var result := _room(RoomState.Phase.RESULT, [_seat(1)])
	assert_bool(_state(result).show_prompts).is_false()


func test_key_prompts_follow_the_input_map() -> void:
	var keys := {
		&"move_up": KEY_I, &"move_left": KEY_J, &"move_down": KEY_K, &"move_right": KEY_L,
		&"attack": KEY_U,
	}
	for action: StringName in keys:
		_bind(action, [_key(keys[action])])
	var hud := _hud(_state(_room(RoomState.Phase.LOBBY, [_seat(1)])))
	var caps := []
	for cap in ["%UpLabel", "%LeftLabel", "%DownLabel", "%RightLabel", "%SpaceLabel"]:
		caps.append(hud.get_node("%Prompts").get_node(cap).text)
	assert_array(caps).is_equal(["I", "J", "K", "L", "U"])


func test_key_prompts_name_the_first_key_and_mark_none() -> void:
	_bind(&"attack", [InputEventMouseButton.new(), _key(KEY_U), _key(KEY_J)])
	assert_str(KeyPrompts.key_name(&"attack")).is_equal("U")
	_bind(&"attack", [])
	assert_str(KeyPrompts.key_name(&"attack")).is_equal(KeyPrompts.UNBOUND)


func test_timer_rounds_up_to_whole_seconds() -> void:
	assert_str(RoomHud.format_time(300 * Protocol.TICK_RATE)).is_equal("5:00")
	assert_str(RoomHud.format_time(65 * Protocol.TICK_RATE - 1)).is_equal("1:05")
	assert_str(RoomHud.format_time(1)).is_equal("0:01")
	assert_str(RoomHud.format_time(0)).is_equal("0:00")


func test_the_middle_line_follows_the_connection_and_the_result() -> void:
	var lobby := _room(RoomState.Phase.LOBBY, [_seat(1)])
	var won := _room(RoomState.Phase.RESULT, [_seat(1)])
	won.outcome = RoomState.Outcome.WON
	var cases := [
		[HudState.build(null, 0, null, false, ""), HudState.CONNECTING_TEXT],
		[HudState.build(lobby, 1, null, false, ""), HudState.RECONNECTING_TEXT],
		[HudState.build(lobby, 1, null, false, "full"), HudState.REJECTED_TEXT % "full"],
		[HudState.unsupported_browser(), HudState.UNSUPPORTED_BROWSER_TEXT],
		[_state(won), HudState.WON_TEXT],
		[_state(lobby), ""],
	]
	var notice: Control = auto_free(CenterNoticeScene.instantiate())
	add_child(notice)
	for c: Array in cases:
		var state: HudState = c[0]
		assert_str(state.notice).is_equal(c[1])
		notice.show_text(state.notice)
		assert_bool(notice.visible).is_equal(c[1] != "")


func test_start_changes_its_look_once_everyone_is_ready() -> void:
	var waiting := ArenaView.dummy_look(World.Kind.START, false)
	var live := ArenaView.dummy_look(World.Kind.START, true)
	assert_str(live.label).is_not_equal(waiting.label)
	assert_object(live.color).is_not_equal(waiting.color)
	var ready_dummy := ArenaView.dummy_look(World.Kind.READY, false)
	assert_object(ArenaView.dummy_look(World.Kind.READY, true)).is_same(ready_dummy)
