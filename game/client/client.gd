extends Node
## Connects to the game server, sends input every tick, and hands the world
## to ArenaView and the UI to RoomHud and CenterNotice. Drawing happens
## between two snapshots, as far in the past as the Interpolator decides.
## While reconnecting, the last picture stays frozen. Options are listed in
## README.md.

## Connection handlers check the state, so a late or stale event is ignored.
## JOINING: hello sent, waiting for welcome or reject. AWAY: tab hidden, so
## no snapshots come. REJECTED is final.
enum State {
	CONNECTING,
	JOINING,
	PLAYING,
	AWAY,
	RETRY_WAIT,
	REJECTED,
	UNSUPPORTED,
}

const Protocol := preload("res://net/protocol.gd")
const Tuning := preload("res://sim/tuning.gd")
const ClientPeer := preload("res://net/client_peer.gd")
const TcpClientPeer := preload("res://net/tcp_client_peer.gd")
const WebTransportPeer := preload("res://net/web_transport_peer.gd")
const Snapshot := preload("res://net/snapshot.gd")
const RoomState := preload("res://net/room_state.gd")
const Options := preload("res://util/options.gd")
const Interpolator := preload("res://client/interpolator.gd")
const LagSimulator := preload("res://client/lag_simulator.gd")
const Hud := preload("res://client/hud.gd")
const Bot := preload("res://client/bot.gd")
const ArenaView := preload("res://client/arena_view.gd")
const HudState := preload("res://client/ui/hud_state.gd")
const RoomHud := preload("res://client/ui/room_hud.gd")
const CenterNotice := preload("res://client/ui/center_notice.gd")
const RoomHudScene := preload("res://client/ui/room_hud.tscn")
const CenterNoticeScene := preload("res://client/ui/center_notice.tscn")

# Reconnect waits double from the first to the max: a blip reconnects almost
# at once, and a down server isn't flooded.
const RETRY_FIRST_SEC := 0.5
const RETRY_MAX_SEC := 5.0
## Often enough to keep the HUD's rtt current.
const PING_EVERY_SEC := 1.0
## 128 random bits. The ID is all it takes to take over a seat, so it mustn't
## be guessable.
const SESSION_ID_BYTES := 16
const SESSION_KEY := "pq_session"
# DEBUG: with the dev option, these end a match, until players can die
# and lose.
const DEV_WIN_KEY := KEY_F8
const DEV_LOSE_KEY := KEY_F9

var net: Node
var options: Options

var _url: String
var _session_id: String
## Kept so the JavaScript listener stays alive.
var _visibility_cb: JavaScriptObject

var _state := State.CONNECTING
var _state_since := 0.0
var _status := ""
var _retry_delay := RETRY_FIRST_SEC
var _retry_at := 0.0
var _player_id := 0
var _reject_reason := ""
## Null until the server sends it. Kept while reconnecting, so the last
## picture stays up; cleared when turned away.
var _room: RoomState
var _attack_count := 0
## Since the last press.
var _hold_ticks := 0

var _lag: LagSimulator
var _interp := Interpolator.new()
## What's drawn: blended from two snapshots. Null before the first; frozen
## while reconnecting.
var _view: Snapshot
## When you last pressed anything, for the key prompts; -INF when you've
## just got control, so they show at once.
var _last_input_at := -INF
## Whether you could act last frame, and in which phase and world, to tell
## when you get control back.
var _could_act := false
var _acting_in := Vector2i(-1, -1)
var _last_snap_at := 0.0
## -1 until measured.
var _rtt_ms := -1.0
var _next_ping_at := 0.0
## Null unless the dev option is on.
var _hud: Hud

var _arena := ArenaView.new()
var _ui := CanvasLayer.new()
var _room_hud: RoomHud = RoomHudScene.instantiate()
var _notice: CenterNotice = CenterNoticeScene.instantiate()

## Null unless the bot option is on.
var _bot: Bot
var _quit_at := INF
var _drop_at := INF
var _snap_count := 0
var _max_players_seen := 0


func _ready() -> void:
	_url = options.url if options.url else _default_url()
	_session_id = _load_session_id()
	_lag = LagSimulator.new(options.lag_sec, options.jitter_sec)
	_interp.fixed = options.interp_fixed
	if options.interp_fixed:
		_interp.delay_sec = options.interp_sec
	if options.bot:
		_bot = Bot.new()
	_quit_at = _now() + options.quit_after_sec
	_drop_at = _now() + options.drop_after_sec
	if OS.has_feature("web"):
		_visibility_cb = JavaScriptBridge.create_callback(_on_visibility_change)
		JavaScriptBridge.get_interface("document").addEventListener(
				"visibilitychange", _visibility_cb)
	add_child(_arena)
	add_child(_ui)
	_ui.add_child(_room_hud)
	_ui.add_child(_notice)
	if options.dev:
		_hud = Hud.new()
		_hud.interp = _interp
		_hud.options = options
		_hud.url = _url
		add_child(_hud)

	# Queued like messages so a reject is handled before the disconnect that
	# follows it; the bound peer identifies events from a replaced connection.
	multiplayer.connected_to_server.connect(
			func() -> void: _incoming(_on_connected.bind(multiplayer.multiplayer_peer)))
	multiplayer.connection_failed.connect(
			func() -> void: _incoming(_on_lost.bind(multiplayer.multiplayer_peer)))
	multiplayer.server_disconnected.connect(
			func() -> void: _incoming(_on_lost.bind(multiplayer.multiplayer_peer)))
	net.welcomed.connect(func(id: int) -> void: _incoming(_on_welcomed.bind(id)))
	net.rejected.connect(func(reason: String) -> void: _incoming(_on_rejected.bind(reason)))
	net.snapshot_received.connect(
			func(snap: Snapshot) -> void: _incoming(_on_snapshot.bind(snap)))
	net.pong_received.connect(func(sent_at: float) -> void: _incoming(_on_pong.bind(sent_at)))
	net.room_state_received.connect(
			func(state: RoomState) -> void: _incoming(_on_room_state.bind(state)))
	_connect()


func _process(delta: float) -> void:
	var now := _now()
	_lag.flush(now, _online)
	_check_connection(now)

	if now >= _drop_at:
		_drop_at = INF
		_status = "dropped (test)"
		_schedule_retry()
	if _bot and _bot.tick(now, _view, _player_id, _room):
		_attack_count += 1
	_interp.update(now, delta)
	# Nothing new while reconnecting: the last picture stays.
	var latest := _interp.view(now)
	if latest:
		_view = latest
	_update_screens(now)

	if now >= _quit_at:
		print("SMOKE player=%d snapshots=%d max_players=%d rtt_ms=%d interp_ms=%d status=%s" % [
			_player_id, _snap_count, _max_players_seen, _rtt_ms, _interp.delay_ms(), _status])
		get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _state != State.PLAYING:
		return
	var move := _read_move()
	if move != Vector2.ZERO:
		_last_input_at = _now()
	_hold_repeat()
	var attacks := _attack_count
	_outgoing(func() -> void:
			net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, move, attacks))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and not event.is_echo():
		_attack_count += 1
		_hold_ticks = 0
		_last_input_at = _now()
	elif options.dev and event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key == DEV_WIN_KEY or key == DEV_LOSE_KEY:
			var won := key == DEV_WIN_KEY
			_outgoing(func() -> void:
					net.dev_end_match.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, won))


## On web the ID is kept in sessionStorage, so a reload rejoins as the same
## player while each tab is its own player.
func _load_session_id() -> String:
	var fresh := Crypto.new().generate_random_bytes(SESSION_ID_BYTES).hex_encode()
	if not OS.has_feature("web"):
		return fresh
	# Storage can throw; then every load gets a fresh ID.
	var stored := str(JavaScriptBridge.eval(
			("(() => { try { return sessionStorage.getItem('%s') || ''; }"
			+ " catch (e) { return ''; } })()") % SESSION_KEY, true))
	if stored != "":
		return stored
	JavaScriptBridge.eval(
			("(() => { try { sessionStorage.setItem('%s', '%s'); }"
			+ " catch (e) {} })()") % [SESSION_KEY, fresh], true)
	return fresh


func _default_url() -> String:
	if not OS.has_feature("web"):
		return "tcp://127.0.0.1:%d" % Protocol.GAME_PORT
	# An https page came from the relay itself, so the relay is at the page's
	# host and port. An http page is local testing, with the relay on its own
	# port.
	var location := JavaScriptBridge.get_interface("location")
	if location.protocol == "https:":
		return "https://%s%s" % [location.host, Protocol.MATCH_PATH]
	return "https://%s:%d%s" % [location.hostname, Protocol.RELAY_PORT, Protocol.MATCH_PATH]


## An http:// page means local testing, where the relay's certificate is
## self-signed and trusted by a hash fetched from it.
func _cert_hash_url() -> String:
	if JavaScriptBridge.get_interface("location").protocol == "https:":
		return ""
	var host := _url.trim_prefix("https://").get_slice("/", 0)
	return "http://%s/cert-hash" % host


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _tab_hidden() -> bool:
	return OS.has_feature("web") and JavaScriptBridge.get_interface("document").hidden


# Connection lifecycle

## Times out a connection that never got its welcome or stopped sending
## snapshots, retries when the wait is up, and pings for the round trip.
func _check_connection(now: float) -> void:
	match _state:
		State.CONNECTING, State.JOINING:
			if now - _state_since > Protocol.JOIN_TIMEOUT_SEC:
				_status = "no welcome, reconnecting"
				_schedule_retry()
		State.RETRY_WAIT:
			if now >= _retry_at:
				_connect()
		State.PLAYING:
			if now - _last_snap_at > Protocol.STALE_AFTER_SEC:
				_status = "no snapshots, reconnecting"
				_schedule_retry()
			elif now >= _next_ping_at:
				_next_ping_at = now + PING_EVERY_SEC
				_outgoing(func() -> void: net.ping.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, now))


func _set_state(state: State) -> void:
	_state = state
	_state_since = _now()


func _connect() -> void:
	_set_state(State.CONNECTING)
	_status = "connecting"
	var peer: ClientPeer
	var err: Error
	if OS.has_feature("web"):
		if not WebTransportPeer.is_supported():
			# Retrying can't help, so stop with a reason the player can read.
			_set_state(State.UNSUPPORTED)
			_status = HudState.UNSUPPORTED_BROWSER_TEXT
			return
		peer = WebTransportPeer.new()
		err = peer.connect_to(_url, _cert_hash_url())
	else:
		var address := _url.trim_prefix("tcp://")
		peer = TcpClientPeer.new()
		err = peer.connect_to(address.get_slice(":", 0), int(address.get_slice(":", 1)))
	if err != OK:
		_status = "connect error: %s" % error_string(err)
		_schedule_retry()
		return
	multiplayer.multiplayer_peer = peer


func _on_connected(peer: MultiplayerPeer) -> void:
	if peer != multiplayer.multiplayer_peer or _state != State.CONNECTING:
		return
	_set_state(State.JOINING)
	_status = "connected, waiting for welcome"
	_outgoing(func() -> void: net.hello.rpc_id(
			MultiplayerPeer.TARGET_PEER_SERVER, Protocol.PROTOCOL_VERSION, _session_id))


func _on_welcomed(player_id: int) -> void:
	if _state != State.JOINING:
		return
	_player_id = player_id
	_set_state(State.PLAYING)
	# The server counts presses from scratch per connection.
	_attack_count = 0
	_hold_ticks = 0
	_status = "player %d" % player_id
	if _hud:
		_hud.note_joined()
	# A good connection starts the backoff over.
	_retry_delay = RETRY_FIRST_SEC
	_last_snap_at = _now()
	# The server starts every connection as not away.
	if _tab_hidden():
		_go_away()


func _on_rejected(reason: String) -> void:
	if _state not in [State.JOINING, State.PLAYING, State.AWAY]:
		return
	_set_state(State.REJECTED)
	_reject_reason = reason
	_room = null
	_view = null
	_status = "rejected: %s" % reason


func _on_lost(peer: MultiplayerPeer) -> void:
	if peer != multiplayer.multiplayer_peer:
		return
	if _state == State.REJECTED or _state == State.RETRY_WAIT:
		return
	_status = "connection lost"
	_schedule_retry()


func _schedule_retry() -> void:
	_set_state(State.RETRY_WAIT)
	_retry_at = _now() + _retry_delay
	_retry_delay = minf(_retry_delay * 2, RETRY_MAX_SEC)
	_lag.clear()
	_interp.reset()
	_close_peer()


## Tells the server when the tab is hidden or shown. Chrome pauses the game
## loop in a hidden tab but JavaScript still calls this, so it sends directly
## instead of through the lag queue.
func _on_visibility_change(_args: Array) -> void:
	var tab_hidden := _tab_hidden()
	if tab_hidden and _state == State.PLAYING:
		_go_away()
	elif not tab_hidden and _state == State.AWAY:
		_set_state(State.PLAYING)
		# Don't let the stale check reconnect over the gap.
		_last_snap_at = _now()
		if _online():
			net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, false)


func _go_away() -> void:
	_set_state(State.AWAY)
	_lag.clear()
	net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, true)


func _close_peer() -> void:
	if multiplayer.multiplayer_peer is ClientPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (peer is ClientPeer
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)


# Messages both ways go through the lag simulator, so order is kept.

func _outgoing(f: Callable) -> void:
	_lag.outgoing(_now(), f)


func _incoming(f: Callable) -> void:
	_lag.incoming(_now(), f)


# Snapshots

func _on_snapshot(snap: Snapshot) -> void:
	var now := _now()
	if not _interp.add(snap, now):
		return
	_last_snap_at = now
	if _hud:
		_hud.note_snapshot(now, snap.packed_size)
	_snap_count += 1
	_max_players_seen = maxi(_max_players_seen, snap.players.size())


func _on_pong(sent_at: float) -> void:
	_rtt_ms = (_now() - sent_at) * 1000.0


# The room and its screens

func _on_room_state(state: RoomState) -> void:
	if _state != State.PLAYING and _state != State.AWAY:
		return
	_room = state
	# A freed lobby seat moves everyone after it down one.
	if state.you:
		_player_id = state.you


## Draws the arena and the UI from the current state, and updates the debug
## HUD if there is one.
func _update_screens(now: float) -> void:
	if _hud:
		_hud.update(now, _status, _view.players.size() if _view else 0, _rtt_ms)
	var welcomed := _state == State.PLAYING or _state == State.AWAY
	var reason := _reject_reason if _state == State.REJECTED else ""
	var state := (HudState.unsupported_browser() if _state == State.UNSUPPORTED
			else HudState.build(_room, _player_id, _view, welcomed, reason))
	_note_control(state)
	state.set_prompts(now, _last_input_at)
	_arena.show_view(_view, _player_id, _room != null and _room.all_ready())
	_room_hud.show_state(state)
	_notice.show_text(state.notice)


## Resets the key prompts' timer whenever you get control of a character
## back: on joining, after the result, into a new match, and (later) on
## revival.
func _note_control(state: HudState) -> void:
	var can_act := state.can_act()
	var where := Vector2i(state.room.phase if state.room else -1,
			_view.world_number if _view else -1)
	if can_act and (not _could_act or where != _acting_in):
		_last_input_at = -INF
	_could_act = can_act
	_acting_in = where


# Input

func _read_move() -> Vector2:
	if _bot:
		return _bot.move
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## While attack is held, adds a press every buffer window: the slowest rate
## that can't skip over the window, so held swings start as soon as they can.
func _hold_repeat() -> void:
	if not Tuning.swing_hold_repeats or Tuning.swing_buffer_ticks == 0 or _bot:
		return
	if not Input.is_action_pressed("attack"):
		return
	_hold_ticks += 1
	if _hold_ticks >= Tuning.swing_buffer_ticks:
		_hold_ticks = 0
		_attack_count += 1
