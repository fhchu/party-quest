extends Node
## Connects to the game server, sends input every tick, and hands the world
## and the UI to GameRenderer. Drawing happens between two snapshots, as far in
## the past as the Interpolator decides. While reconnecting, the last picture
## stays frozen. Options are listed in README.md.

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

const Net := preload("res://net/net.gd")
const Protocol := preload("res://net/protocol.gd")
const ClientPeer := preload("res://client/client_peer.gd")
const TcpClientPeer := preload("res://client/tcp_client_peer.gd")
const WebTransportPeer := preload("res://client/web_transport_peer.gd")
const Snapshot := preload("res://net/snapshot.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Options := preload("res://client/options.gd")
const ClientState := preload("res://client/client_state.gd")
const LagSimulator := preload("res://client/lag_simulator.gd")
const DebugOverlay := preload("res://client/debug_overlay.gd")
const GameView := preload("res://client/game_view.gd")
const GameRenderer := preload("res://client/game_renderer.gd")
const GameRendererScene := preload("res://client/game_renderer.tscn")

# Reconnect waits double from the first to the max: a blip reconnects almost
# at once, and a down server isn't flooded.
const RETRY_FIRST_SEC := 0.5
const RETRY_MAX_SEC := 5.0
## Often enough to keep the debug overlay's rtt current.
const PING_EVERY_SEC := 1.0
## The client reconnects after this long without a snapshot, to catch sockets
## that died without closing. Many snapshot intervals, so a hiccup doesn't
## trip it, while a dead connection is still replaced quickly. Untuned.
const STALE_AFTER_SEC := 3.0
## The client starts over after this long connecting, or this long joining
## without a welcome. Leaves room for testing with ?lag=3000, where joining
## alone waits 3 s (hello and welcome each wait half a round trip).
const JOIN_TIMEOUT_SEC := 6.0
## 128 random bits. The ID is all it takes to take over a seat, so it mustn't
## be guessable.
const SESSION_ID_BYTES := 16
const SESSION_KEY := "pq_session"

var net: Net
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
## Set when the state becomes REJECTED.
var _reject_reason: Protocol.RejectReason
var _client_state: ClientState

var _lag: LagSimulator
var _last_snap_at := 0.0
## -1 until measured.
var _rtt_ms := -1.0
var _next_ping_at := 0.0
## Null unless the dev option is on.
var _debug_overlay: DebugOverlay

var _game_renderer: GameRenderer = GameRendererScene.instantiate()


func _ready() -> void:
	_url = options.url if options.url else _default_url()
	_session_id = _load_session_id()
	# Simulated lag is for local testing: a release build, like the hosted
	# one, never delays messages, and its queue only keeps their order.
	if OS.is_debug_build():
		_lag = LagSimulator.new(options.lag_sec, options.jitter_sec)
	else:
		_lag = LagSimulator.new(0.0, 0.0)
	_client_state = ClientState.new(options.interp_fixed, options.interp_sec)
	if OS.has_feature("web"):
		_visibility_cb = JavaScriptBridge.create_callback(_on_visibility_change)
		JavaScriptBridge.get_interface("document").addEventListener(
				"visibilitychange", _visibility_cb)
	add_child(_game_renderer)
	if options.dev:
		_debug_overlay = DebugOverlay.new()
		_debug_overlay.interp = _client_state.interpolator
		_debug_overlay.lag = _lag
		# Without the game path, which testers took for a page to visit.
		_debug_overlay.server = _url.trim_suffix(Protocol.GAME_PATH)
		add_child(_debug_overlay)

	# Queued like messages so a reject is handled before the disconnect that
	# follows it; the bound peer identifies events from a replaced connection.
	multiplayer.connected_to_server.connect(
			func() -> void: _incoming(_on_connected.bind(multiplayer.multiplayer_peer)))
	multiplayer.connection_failed.connect(
			func() -> void: _incoming(_on_lost.bind(multiplayer.multiplayer_peer)))
	multiplayer.server_disconnected.connect(
			func() -> void: _incoming(_on_lost.bind(multiplayer.multiplayer_peer)))
	net.welcomed.connect(func(id: int) -> void: _incoming(_on_welcomed.bind(id)))
	net.rejected.connect(
			func(reason: Protocol.RejectReason) -> void: _incoming(_on_rejected.bind(reason)))
	net.snapshot_received.connect(
			func(snap: Snapshot) -> void: _incoming(_on_snapshot.bind(snap)))
	net.pong_received.connect(func(sent_at: float) -> void: _incoming(_on_pong.bind(sent_at)))
	net.lobby_state_received.connect(
			func(state: LobbyState) -> void: _incoming(_on_lobby_state.bind(state)))
	_connect()


func _process(delta: float) -> void:
	var now := _now()
	_lag.flush(now, _online)
	_check_connection(now)
	_client_state.update(now, delta)
	_update_screens(now)


func _physics_process(_delta: float) -> void:
	if _state != State.PLAYING:
		return
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move != Vector2.ZERO:
		_client_state.moved(_now())
	var attacks := _client_state.attack_count
	_outgoing(func() -> void:
			net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, move, attacks))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and not event.is_echo():
		_client_state.attack_pressed(_now())


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
		return "https://%s%s" % [location.host, Protocol.GAME_PATH]
	return "https://%s:%d%s" % [location.hostname, Protocol.RELAY_PORT, Protocol.GAME_PATH]


## An http:// page means local testing, where the relay's certificate is
## self-signed and trusted by a hash fetched from it.
func _cert_hash_url() -> String:
	if JavaScriptBridge.get_interface("location").protocol == "https:":
		return ""
	var host := _url.trim_prefix("https://").get_slice("/", 0)
	return "http://%s/cert-hash" % host


func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


func _tab_hidden() -> bool:
	return OS.has_feature("web") and JavaScriptBridge.get_interface("document").hidden


# Connection lifecycle

## Times out a connection that never got its welcome or stopped sending
## snapshots, retries when the wait is up, and pings for the round trip.
func _check_connection(now: float) -> void:
	match _state:
		State.CONNECTING, State.JOINING:
			if now - _state_since > JOIN_TIMEOUT_SEC:
				_status = "no welcome, reconnecting"
				_schedule_retry()
		State.RETRY_WAIT:
			if now >= _retry_at:
				_connect()
		State.PLAYING:
			if now - _last_snap_at > STALE_AFTER_SEC:
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
			_status = GameView.UNSUPPORTED_BROWSER_TEXT
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
	_client_state.welcomed(player_id)
	_set_state(State.PLAYING)
	_status = "player %d" % player_id
	if _debug_overlay:
		_debug_overlay.note_joined()
	# A good connection starts the backoff over.
	_retry_delay = RETRY_FIRST_SEC
	_last_snap_at = _now()
	# The server starts every connection as not away.
	if _tab_hidden():
		_go_away()


func _on_rejected(reason: Protocol.RejectReason) -> void:
	if _state not in [State.JOINING, State.PLAYING, State.AWAY]:
		return
	_set_state(State.REJECTED)
	_reject_reason = reason
	_client_state.rejected()
	_status = "rejected: %s" % Protocol.RejectReason.find_key(reason)


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
	_client_state.connection_lost()
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
	if not _client_state.snapshot_received(snap, now):
		return
	_last_snap_at = now
	if _debug_overlay:
		_debug_overlay.note_snapshot(now, snap.packed_size)


func _on_pong(sent_at: float) -> void:
	_rtt_ms = (_now() - sent_at) * 1000.0


# The lobby and its screens

func _on_lobby_state(state: LobbyState) -> void:
	if _state != State.PLAYING and _state != State.AWAY:
		return
	_client_state.lobby_received(state)


## Draws the screen from what the client knows, or the reason it can't
## play, and updates the debug overlay if there is one.
func _update_screens(now: float) -> void:
	if _debug_overlay:
		var drawn := _client_state.drawn
		_debug_overlay.update(now, _status, drawn.players.size() if drawn else 0, _rtt_ms)
	var welcomed := _state == State.PLAYING or _state == State.AWAY
	var view := _client_state.view(now, welcomed)
	match _state:
		State.UNSUPPORTED:
			view = GameView.unsupported_browser()
		State.REJECTED:
			view = GameView.rejected(_reject_reason)
	_game_renderer.render(view)
