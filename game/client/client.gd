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
const GameRenderer := preload("res://client/game_renderer.gd")
const GameRendererScene := preload("res://client/game_renderer.tscn")

# Reconnect waits double from the first to the max: a blip reconnects almost
# at once, and a down server isn't flooded.
const RETRY_FIRST_SEC := 0.5
const RETRY_MAX_SEC := 5.0
## Often enough to keep the debug overlay's ping current.
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
## The middle line once the server turns this client away, one per
## [enum Protocol.RejectReason]. PLACEHOLDER (design): the wording.
const REJECTED_TEXTS := {
	Protocol.RejectReason.VERSION: "The game was updated. Reload the page.",
	Protocol.RejectReason.FULL: "Can't join: lobby is full",
	Protocol.RejectReason.DUPLICATE_SESSION: "You're playing in another tab.",
}
## The middle line when this browser can't run the game. Must match
## noBrotliText in relay/static.go, so players get one message whichever
## check fails.
const UNSUPPORTED_BROWSER_TEXT := (
		"Your browser is incompatible. Try using an updated version of Google Chrome.")

var net: Net
var options: Options

var _url: String
var _session_id: String
## Kept so the JavaScript listener stays alive.
var _visibility_cb: JavaScriptObject

var _state := State.CONNECTING
var _state_since := 0.0
var _retry_delay := RETRY_FIRST_SEC
var _retry_at := 0.0
## Set when the state becomes REJECTED.
var _reject_reason: Protocol.RejectReason
var _client_state: ClientState

var _last_snap_at := 0.0
var _next_ping_at := 0.0
## The move last sent to the server, to send a change the frame it happens.
var _sent_move := Vector2.ZERO

var _game_renderer: GameRenderer = GameRendererScene.instantiate()


func _ready() -> void:
	_url = options.url if options.url else _default_url()
	_session_id = _load_session_id()
	_client_state = ClientState.new(options.interp_fixed, options.interp_sec)
	if OS.has_feature("web"):
		_visibility_cb = JavaScriptBridge.create_callback(_on_visibility_change)
		JavaScriptBridge.get_interface("document").addEventListener(
				"visibilitychange", _visibility_cb)
	add_child(_game_renderer)
	if options.dev:
		_show_debug()

	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_lost)
	multiplayer.server_disconnected.connect(_on_lost)
	net.welcomed.connect(_on_welcomed)
	net.rejected.connect(_on_rejected)
	net.snapshot_received.connect(_on_snapshot)
	net.pong_received.connect(_on_pong)
	net.lobby_state_received.connect(_on_lobby_state)
	_connect()


func _process(delta: float) -> void:
	var now := _now()
	# A change goes out at once instead of waiting up to a tick.
	if _state == State.PLAYING and _read_move() != _sent_move:
		_send_input()
	_check_connection(now)
	_client_state.update(now, delta)
	_update_screens(now)


## Every tick as well as on each change, since the server stops a player
## whose input goes silent (INPUT_SILENCE_SEC in server/lobby.gd).
func _physics_process(_delta: float) -> void:
	if _state == State.PLAYING:
		_send_input()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and not event.is_echo():
		_client_state.attack_pressed(_now())
		if _state == State.PLAYING:
			_send_input()


## Turns on the debug overlay and gives it what only the client knows.
func _show_debug() -> void:
	_client_state.show_debug = true
	var stats := _client_state.stats
	var lag := _new_lag()
	if lag:
		stats.sim_lag_ms = int(lag.lag_sec * 2 * 1000)
		stats.sim_jitter_ms = int(lag.jitter_sec * 1000)
	# Without the game path, which testers took for a page to visit.
	stats.server = _url.trim_suffix(Protocol.GAME_PATH)
	if OS.has_feature("web"):
		stats.page_loaded(_now(), JavaScriptBridge.get_interface("performance").now())


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
				_client_state.stats.status = "no welcome, reconnecting"
				_schedule_retry()
		State.RETRY_WAIT:
			if now >= _retry_at:
				_connect()
		State.PLAYING:
			if now - _last_snap_at > STALE_AFTER_SEC:
				_client_state.stats.status = "no snapshots, reconnecting"
				_schedule_retry()
			elif now >= _next_ping_at:
				_next_ping_at = now + PING_EVERY_SEC
				net.ping.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, now)


func _set_state(state: State) -> void:
	_state = state
	_state_since = _now()


func _connect() -> void:
	_set_state(State.CONNECTING)
	_client_state.stats.status = "connecting"
	var peer: ClientPeer
	var err: Error
	if OS.has_feature("web"):
		if not WebTransportPeer.is_supported():
			# Retrying can't help, so stop with a reason the player can read.
			_set_state(State.UNSUPPORTED)
			_client_state.stats.status = UNSUPPORTED_BROWSER_TEXT
			return
		peer = WebTransportPeer.new()
		err = peer.connect_to(_url, _cert_hash_url())
	else:
		var address := _url.trim_prefix("tcp://")
		peer = TcpClientPeer.new()
		err = peer.connect_to(address.get_slice(":", 0), int(address.get_slice(":", 1)))
	if err != OK:
		_client_state.stats.status = "connect error: %s" % error_string(err)
		_schedule_retry()
		return
	peer.lag = _new_lag()
	multiplayer.multiplayer_peer = peer


func _on_connected() -> void:
	if _state != State.CONNECTING:
		return
	_set_state(State.JOINING)
	_client_state.stats.status = "connected, waiting for welcome"
	net.hello.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, Protocol.build_id(), _session_id)


func _on_welcomed(player_id: int) -> void:
	if _state != State.JOINING:
		return
	_client_state.welcomed(player_id, _now())
	_set_state(State.PLAYING)
	_client_state.stats.status = "player %d" % player_id
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
	_client_state.stats.status = "rejected: %s" % Protocol.RejectReason.find_key(reason)


func _on_lost() -> void:
	if _state == State.REJECTED or _state == State.RETRY_WAIT:
		return
	_client_state.stats.status = "connection lost"
	_schedule_retry()


func _schedule_retry() -> void:
	_set_state(State.RETRY_WAIT)
	_retry_at = _now() + _retry_delay
	_retry_delay = minf(_retry_delay * 2, RETRY_MAX_SEC)
	_client_state.connection_lost()
	_close_peer()


## Tells the server when the tab is hidden or shown. JavaScript calls this
## even while Chrome pauses the game loop in a hidden tab. Under simulated
## lag the message waits in the queue, which only drains while the loop runs.
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
	(multiplayer.multiplayer_peer as ClientPeer).drop_delayed()
	net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, true)


func _close_peer() -> void:
	if multiplayer.multiplayer_peer is ClientPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (peer is ClientPeer
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)


## Simulated lag is for local testing: a release build, like the hosted
## one, never delays messages. Null for none.
func _new_lag() -> LagSimulator:
	if not OS.is_debug_build() or (options.lag_sec == 0.0 and options.jitter_sec == 0.0):
		return null
	return LagSimulator.new(options.lag_sec, options.jitter_sec)


# Snapshots

func _on_snapshot(snap: Snapshot) -> void:
	var now := _now()
	var peer := multiplayer.multiplayer_peer as ClientPeer
	_client_state.frames_counted(
			now, peer.frames_taken(), peer.frames_missed(), peer.frames_late())
	if not _client_state.snapshot_received(snap, now):
		return
	_last_snap_at = now


func _on_pong(sent_at: float) -> void:
	var now := _now()
	_client_state.ping_measured(now, (now - sent_at) * 1000.0)


func _read_move() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _send_input() -> void:
	var move := _read_move()
	_client_state.input_sent(_now(), move)
	_sent_move = move
	net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, move, _client_state.attack_count)


# The lobby and its screens

func _on_lobby_state(state: LobbyState) -> void:
	if _state != State.PLAYING and _state != State.AWAY:
		return
	_client_state.lobby_received(state)


## Draws the screen from what the client knows, or the reason it can't
## play.
func _update_screens(now: float) -> void:
	var welcomed := _state == State.PLAYING or _state == State.AWAY
	var notice := ""
	match _state:
		State.UNSUPPORTED:
			notice = UNSUPPORTED_BROWSER_TEXT
		State.REJECTED:
			notice = REJECTED_TEXTS[_reject_reason]
	_game_renderer.render(_client_state.view(now, welcomed, notice))
