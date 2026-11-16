extends RefCounted
## What the client knows of the game, apart from its connection: the lobby,
## the world it draws, your seat and your input. It never touches the
## network or the clock; client.gd hands it each message once it's decoded
## and queued, with the time.

const Snapshot := preload("res://net/snapshot.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Interpolator := preload("res://client/interpolator.gd")
const GameView := preload("res://client/game_view.gd")

## Your seat; 0 before the server names it.
var player_id := 0
## Presses of attack since the welcome: the server counts from scratch per
## connection.
var attack_count := 0
var interpolator := Interpolator.new()
## Null until the server sends it. Kept while reconnecting, so the last
## picture stays up; cleared when turned away.
var lobby: LobbyState
## What's drawn: blended from two snapshots. Null before the first; frozen
## while reconnecting.
var drawn: Snapshot

## When you last pressed anything, for the key prompts; -INF when you've
## just got control, so they show at once.
var _last_input_at := -INF
## Whether you could act last frame, and in which phase and world, to tell
## when you get control back.
var _could_act := false
var _acting_in := Vector2i(-1, -1)


## Whether seat [param my_id] has a character it can move right now: in the
## lobby, connected, not spectating, and not in the result. Death will join
## these.
static func can_act(in_lobby: LobbyState, my_id: int, connected: bool) -> bool:
	if not in_lobby or not connected or in_lobby.phase == LobbyState.Phase.RESULT:
		return false
	var mine := in_lobby.find_seat(my_id)
	return mine != null and mine.readiness != LobbyState.Readiness.SPECTATING


## [param interp_fixed] gives a fixed drawing delay of [param interp_sec]
## instead of one that adapts.
func _init(interp_fixed: bool, interp_sec: float) -> void:
	interpolator.fixed = interp_fixed
	if interp_fixed:
		interpolator.delay_sec = interp_sec


func welcomed(id: int) -> void:
	player_id = id
	attack_count = 0


func lobby_received(state: LobbyState) -> void:
	lobby = state
	# A freed lobby seat moves everyone after it down one.
	if state.you:
		player_id = state.you


## Returns whether [param snap] was taken: false for one older than what's
## already in.
func snapshot_received(snap: Snapshot, now: float) -> bool:
	return interpolator.add(snap, now)


## The server turned this client away for good.
func rejected() -> void:
	lobby = null
	drawn = null


## The connection is gone and a new one is coming; the last picture stays.
func connection_lost() -> void:
	interpolator.reset()


func attack_pressed(now: float) -> void:
	attack_count += 1
	_last_input_at = now


func moved(now: float) -> void:
	_last_input_at = now


func update(now: float, delta: float) -> void:
	interpolator.update(now, delta)
	# Nothing new while reconnecting: the last picture stays.
	var latest := interpolator.view(now)
	if latest:
		drawn = latest


## The screen for this frame. [param connected] is whether the client holds
## a live connection that the server has welcomed. Call it every frame: it
## also notices when you get control back.
func view(now: float, connected: bool) -> GameView:
	var can_act_now := can_act(lobby, player_id, connected)
	_note_control(can_act_now)
	var idle_sec := now - _last_input_at if can_act_now else 0.0
	return GameView.build(lobby, player_id, drawn, connected, idle_sec)


## Resets the key prompts' timer whenever you get control of a character
## back: on joining, after the result, into a new run, and (later) on
## revival. [param can_act_now] is [method can_act] for this frame.
func _note_control(can_act_now: bool) -> void:
	var where := Vector2i(lobby.phase if lobby else -1, drawn.layout_number if drawn else -1)
	if can_act_now and (not _could_act or where != _acting_in):
		_last_input_at = -INF
	_could_act = can_act_now
	_acting_in = where
