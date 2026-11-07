extends Node2D
## Connects to the game server, sends input every tick, and draws the world.
## Drawing happens between two snapshots, as far in the past as the
## Interpolator decides. Options are listed in README.md.

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
const World := preload("res://sim/world.gd")
const ClientPeer := preload("res://net/client_peer.gd")
const TcpClientPeer := preload("res://net/tcp_client_peer.gd")
const WebTransportPeer := preload("res://net/web_transport_peer.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Options := preload("res://util/options.gd")
const Interpolator := preload("res://client/interpolator.gd")
const LagSimulator := preload("res://client/lag_simulator.gd")
const Hud := preload("res://client/hud.gd")
const Bot := preload("res://client/bot.gd")

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

# PLACEHOLDER (art): shapes the size of their hurtboxes until there are
# sprites.
## One per seat: player IDs are seat numbers, 1 to MAX_PLAYERS.
const PLAYER_COLORS: Array[Color] = [
	Color(0.35, 0.65, 1.0),
	Color(1.0, 0.55, 0.3),
	Color(0.45, 0.85, 0.45),
	Color(0.85, 0.45, 0.9),
]
const DUMMY_COLOR := Color(0.8, 0.65, 0.4)
## A struck dummy's flash and an invulnerable player's blink. White, not red,
## which reads as blood.
const FLASH_COLOR := Color.WHITE
## How long each on and off of an invulnerable player's blink lasts.
const INVULNERABLE_BLINK_SEC := 0.1
const SWING_COLOR := Color(1, 1, 1, 0.3)
const WALL_COLOR := Color(0.35, 0.35, 0.4)
const WALL_WIDTH := 2.0
## Facing line and your own player's outline.
const MARKING_COLOR := Color.WHITE
const FACING_WIDTH := 2.0
const OUTLINE_WIDTH := 1.0
## DEBUG: how faint a disconnected player is drawn, until there's real UI.
const DISCONNECTED_ALPHA := 0.35
## Enough straight pieces that the swing's edge looks round.
const ARC_SEGMENTS := 12

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
var _attack_count := 0
## Since the last press.
var _hold_ticks := 0

var _lag: LagSimulator
var _interp := Interpolator.new()
## What's drawn: blended from two snapshots. Null before the first.
var _view: Snapshot
var _last_snap_at := 0.0
## -1 until measured.
var _rtt_ms := -1.0
var _next_ping_at := 0.0
var _hud := Hud.new()

## Null unless the bot option is on.
var _bot: Bot
var _quit_at := INF
var _drop_at := INF
var _snap_count := 0
var _max_players_seen := 0


## Distance from a box's center to its edge in direction [param dir].
static func _to_box_edge(dir: Vector2, half: Vector2) -> float:
	var x := half.x / absf(dir.x) if not is_zero_approx(dir.x) else INF
	var y := half.y / absf(dir.y) if not is_zero_approx(dir.y) else INF
	return minf(x, y)


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
	_connect()


func _process(delta: float) -> void:
	var now := _now()
	_lag.flush(now, _online)
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

	if now >= _drop_at:
		_drop_at = INF
		_status = "dropped (test)"
		_schedule_retry()
	if _bot and _bot.tick(now):
		_attack_count += 1
	_interp.update(now, delta)
	_view = _interp.view(now)
	_hud.update(now, _status, _view.players.size() if _view else 0, _rtt_ms)
	queue_redraw()

	if now >= _quit_at:
		print("SMOKE player=%d snapshots=%d max_players=%d rtt_ms=%d interp_ms=%d status=%s" % [
			_player_id, _snap_count, _max_players_seen, _rtt_ms, _interp.delay_ms(), _status])
		get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _state != State.PLAYING:
		return
	var move := _read_move()
	_hold_repeat()
	var attacks := _attack_count
	_outgoing(func() -> void:
			net.send_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, move, attacks))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and not event.is_echo():
		_attack_count += 1
		_hold_ticks = 0


func _draw() -> void:
	draw_rect(Tuning.arena, WALL_COLOR, false, WALL_WIDTH)
	if not _view:
		return
	for d in _view.dummies:
		var color := FLASH_COLOR if d.flashing else DUMMY_COLOR
		draw_rect(World.hurtbox(d.pos, Tuning.dummy_hurtbox), color)
	# Blinks by the snapshot's tick, so every client blinks in step.
	var blink_on := floori(_view.tick / float(Tuning.ticks(INVULNERABLE_BLINK_SEC))) % 2 == 0
	for p in _view.players:
		var color := PLAYER_COLORS[p.id - 1]
		if p.invulnerable and blink_on:
			color = FLASH_COLOR
		elif not p.connected:
			color.a = DISCONNECTED_ALPHA
		if p.swing_ticks > 0:
			_draw_swing(p.pos, p.facing)
		# Only the swing may leave the hurtbox, so a player at a wall stays on screen.
		var box := World.hurtbox(p.pos, Tuning.player_hurtbox)
		draw_rect(box, color)
		if p.id == _player_id:
			# Inset by half its width, so it's drawn inside the box.
			draw_rect(box.grow(-OUTLINE_WIDTH / 2), MARKING_COLOR, false, OUTLINE_WIDTH)
		var edge := p.pos + p.facing * _to_box_edge(p.facing, box.size / 2)
		draw_line(p.pos, edge, MARKING_COLOR, FACING_WIDTH)


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
	# relay/main.go serves /match. An https page came from the relay itself,
	# so the relay is at the page's host and port. An http page is local
	# testing, with the relay on its own port.
	var location := JavaScriptBridge.get_interface("location")
	if location.protocol == "https:":
		return "https://%s/match" % location.host
	return "https://%s:%d/match" % [location.hostname, Protocol.RELAY_PORT]


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
			_status = "this browser doesn't support WebTransport"
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
	_outgoing(func() -> void: net.hello.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, _session_id))


func _on_welcomed(player_id: int) -> void:
	if _state != State.JOINING:
		return
	_player_id = player_id
	_set_state(State.PLAYING)
	# The server counts presses from scratch per connection.
	_attack_count = 0
	_hold_ticks = 0
	_status = "player %d" % player_id
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
	_hud.note_snapshot(now)
	_snap_count += 1
	_max_players_seen = maxi(_max_players_seen, snap.players.size())


func _on_pong(sent_at: float) -> void:
	_rtt_ms = (_now() - sent_at) * 1000.0


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


# Drawing

func _draw_swing(pos: Vector2, facing: Vector2) -> void:
	var points := PackedVector2Array([pos])
	for i in ARC_SEGMENTS + 1:
		var t := float(i) / ARC_SEGMENTS
		var angle := facing.angle() + lerpf(-Tuning.swing_arc / 2, Tuning.swing_arc / 2, t)
		points.append(pos + Vector2.from_angle(angle) * Tuning.swing_radius)
	draw_colored_polygon(points, SWING_COLOR)
