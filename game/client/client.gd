extends Node2D
## Connects to the game server, sends input every tick, and draws the world.
##
## Nothing is predicted: everything, your own player included, is drawn
## between two snapshots, as far in the past as [method _update_render_offset]
## decides. Options are listed in README.md.

## Connection handlers check the state, so a late or stale event is ignored.
## JOINING: hello sent, waiting for welcome or reject. AWAY: tab hidden, so
## no snapshots come. REJECTED is final.
enum State { CONNECTING, JOINING, PLAYING, AWAY, RETRY_WAIT, REJECTED }

const Protocol := preload("res://net/protocol.gd")
const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")
const ClientPeer := preload("res://net/client_peer.gd")
const TcpClientPeer := preload("res://net/tcp_client_peer.gd")
const WebTransportPeer := preload("res://net/web_transport_peer.gd")
const Snapshot := preload("res://net/snapshot.gd")

## How far back arrival times count when sizing the delay. Untuned: longer
## remembers hiccups that are further apart, shorter recovers sooner once the
## link steadies.
const TRANSIT_WINDOW_SEC := 3.0
## Slack for frame timing.
const INTERP_MARGIN_SEC := 0.01
# How fast the delay grows and shrinks, in seconds per second: growing plays
# at 80% speed for a moment, shrinking at 102%, too little to notice.
const INTERP_RISE := 0.2
const INTERP_FALL := 0.02
## A hidden tab's frames stop, so one long frame mustn't move the delay all
## at once. This is a few normal frames.
const INTERP_MAX_STEP_SEC := 0.1
## The delay until snapshots have sized it. It adapts within seconds, so it
## only needs to be safe.
const START_INTERP_SEC := 0.1
## How far each snapshot moves the clock toward its own reading: a small step,
## so jitter averages out.
const CLOCK_SMOOTHING := 0.05
## A reading this far off resets the clock, since smoothing would take seconds
## to get there.
const CLOCK_RESET_SEC := 0.25

# Reconnect waits double from the first to the max: a blip reconnects almost
# at once, and a down server isn't flooded.
const RETRY_FIRST_SEC := 0.5
const RETRY_MAX_SEC := 5.0
## Often enough to keep the HUD's rtt current.
const PING_EVERY_SEC := 1.0
## Slow enough to read, fast enough to stay current.
const HUD_EVERY_SEC := 0.25
## About a couple of messages a second.
const JITTER_CHANCE := 1.0 / 30
## 128 random bits. The ID is all it takes to take over a seat, so it mustn't
## be guessable.
const SESSION_ID_BYTES := 16
const SESSION_KEY := "pq_session"
# Arbitrary: enough to keep a load test busy.
const BOT_TURN_SEC := 1.0
const BOT_ATTACK_SEC := 0.5

# PLACEHOLDER (art): shapes the size of their hurtboxes until there are
# sprites.
## One per seat: player IDs are seat numbers, 1 to MAX_PLAYERS.
const PLAYER_COLORS: Array[Color] = [
	Color(0.35, 0.65, 1.0),
	Color(1.0, 0.55, 0.3),
	Color(0.45, 0.85, 0.45),
	Color(0.85, 0.45, 0.9),
]
const TARGET_DUMMY_COLOR := Color(0.8, 0.65, 0.4)
const LOAD_DUMMY_COLOR := Color(0.55, 0.55, 0.55)
## White, not red, which reads as blood.
const HIT_FLASH_COLOR := Color.WHITE
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

# The debug HUD.
const HUD_MARGIN := Vector2(4, 4)
const HUD_FONT_SIZE := 10

var net: Node
var args: Dictionary

var _url: String
## Simulated delay each way.
var _lag_sec := 0.0
## Longest simulated hold-up.
var _jitter_sec := 0.0
## The interp option if given, else the start.
var _interp_delay := START_INTERP_SEC
var _interp_auto := true
var _bot := false
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
## In release order.
var _delayed: Array[Delayed] = []

## Oldest first.
var _snaps: Array[Snapshot] = []
## What's drawn: blended from two snapshots. Null before the first.
var _view: Snapshot
## Server time minus local time, smoothed.
var _clock_offset := 0.0
var _have_clock := false
## Added to local time to get the time drawn.
var _render_offset := 0.0
## Oldest first.
var _transits: Array[Transit] = []
var _last_snap_at := 0.0
var _snap_arrivals: Array[float] = []
## -1 until measured.
var _rtt_ms := -1.0
var _next_ping_at := 0.0
var _next_hud_at := 0.0
## -1 until measured.
var _load_ms := -1.0

var _hud := Label.new()

var _bot_move := Vector2.ZERO
var _bot_next_turn := 0.0
var _bot_next_attack := 0.0
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
	_url = args.get("url", _default_url())
	_session_id = _load_session_id()
	# Options are in ms; lag is a round trip.
	_lag_sec = float(args.get("lag", "0")) / 1000.0 / 2
	_jitter_sec = float(args.get("jitter", "0")) / 1000.0
	_interp_auto = not args.has("interp")
	if not _interp_auto:
		_interp_delay = float(args["interp"]) / 1000.0
	_bot = args.has("bot")
	if args.has("quit-after"):
		_quit_at = _now() + float(args["quit-after"])
	if args.has("drop-after"):
		_drop_at = _now() + float(args["drop-after"])
	if OS.has_feature("web"):
		_load_ms = float(JavaScriptBridge.eval("performance.now()", true))
		_visibility_cb = JavaScriptBridge.create_callback(_on_visibility_change)
		JavaScriptBridge.get_interface("document").addEventListener(
				"visibilitychange", _visibility_cb)

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud.position = HUD_MARGIN
	_hud.add_theme_font_size_override("font_size", HUD_FONT_SIZE)
	layer.add_child(_hud)

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
	_flush_delayed(now)
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
	if _bot:
		_bot_tick(now)
	_update_render_offset(now, delta)
	_view = _interpolate(now)
	if now >= _next_hud_at:
		_next_hud_at = now + HUD_EVERY_SEC
		_update_hud(now)
	queue_redraw()

	if now >= _quit_at:
		print("SMOKE player=%d snapshots=%d max_players=%d rtt_ms=%d interp_ms=%d status=%s" % [
			_player_id, _snap_count, _max_players_seen, _rtt_ms, _interp_ms(), _status])
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
		var size := Tuning.target_dummy_hurtbox if d.target else Tuning.DUMMY_HURTBOX
		var color := TARGET_DUMMY_COLOR if d.target else LOAD_DUMMY_COLOR
		if d.hit:
			color = HIT_FLASH_COLOR
		draw_rect(World.hurtbox(d.pos, size), color)
	for p in _view.players:
		var color := PLAYER_COLORS[p.id - 1]
		if not p.connected:
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
	# PLACEHOLDER (hosting): release builds will set the relay address.
	# relay/main.go serves /match and /cert-hash.
	var host := str(JavaScriptBridge.eval("window.location.hostname", true))
	return "https://%s:%d/match" % [host, Protocol.RELAY_PORT]


## An http:// page means local testing, where the relay's certificate is
## self-signed and trusted by a hash fetched from it.
func _cert_hash_url() -> String:
	if str(JavaScriptBridge.eval("window.location.protocol", true)) == "https:":
		return ""
	var host := _url.trim_prefix("https://").get_slice("/", 0)
	return "http://%s/cert-hash" % host


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _tab_hidden() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("document.hidden", true))


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
	_delayed.clear()
	_snaps.clear()
	_have_clock = false
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
	_delayed.clear()
	net.set_away.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, true)


func _close_peer() -> void:
	if multiplayer.multiplayer_peer is ClientPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (peer is ClientPeer
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)


# Simulated latency: messages both ways share one queue, so order is kept.

func _outgoing(f: Callable) -> void:
	_delayed.append(Delayed.new(_now() + _lag_sec + _jitter(), f, true))


func _incoming(f: Callable) -> void:
	_delayed.append(Delayed.new(_now() + _lag_sec + _jitter(), f, false))


## Holds up the odd message, delaying everything behind it like a Wi-Fi
## hiccup. A random delay on every message would just add the largest one to
## all of them, since order is kept.
func _jitter() -> float:
	return randf() * _jitter_sec if randf() < JITTER_CHANCE else 0.0


func _flush_delayed(now: float) -> void:
	while not _delayed.is_empty() and _delayed[0].release_at <= now:
		var item: Delayed = _delayed.pop_front()
		if not item.outgoing or _online():
			item.action.call()


# Snapshots and interpolation

func _on_snapshot(snap: Snapshot) -> void:
	var now := _now()
	if not _snaps.is_empty() and snap.tick <= _snaps[-1].tick:
		return
	_snaps.append(snap)

	var offset := _time_of(snap) - now
	_transits.append(Transit.new(now, offset))
	if not _have_clock or absf(offset - _clock_offset) > CLOCK_RESET_SEC:
		_clock_offset = offset
		if not _have_clock:
			_render_offset = _clock_offset - _interp_delay
		_have_clock = true
	else:
		_clock_offset = lerpf(_clock_offset, offset, CLOCK_SMOOTHING)

	_last_snap_at = now
	_snap_arrivals.append(now)
	_snap_count += 1
	_max_players_seen = maxi(_max_players_seen, snap.players.size())


## Picks how far in the past to draw: one snapshot interval plus a margin
## behind the latest-arriving snapshot of the last few seconds, so the next
## snapshot is there when needed. It drifts rather than jumps, so motion only
## speeds up or slows down a little.
func _update_render_offset(now: float, delta: float) -> void:
	while not _transits.is_empty() and _transits[0].arrival < now - TRANSIT_WINDOW_SEC:
		_transits.pop_front()
	if not _have_clock:
		return
	if not _interp_auto or _transits.is_empty():
		_render_offset = _clock_offset - _interp_delay
		return
	var latest: float = _transits.reduce(
			func(m: float, t: Transit) -> float: return minf(m, t.offset), INF)
	var target := latest - Protocol.SNAPSHOT_INTERVAL_SEC - INTERP_MARGIN_SEC
	var step := minf(delta, INTERP_MAX_STEP_SEC)
	if target < _render_offset:
		_render_offset = maxf(target, _render_offset - INTERP_RISE * step)
	else:
		_render_offset = minf(target, _render_offset + INTERP_FALL * step)


## How far behind the newest snapshots the drawing is.
func _interp_ms() -> int:
	return roundi((_clock_offset - _render_offset) * 1000.0)


func _interpolate(now: float) -> Snapshot:
	if _snaps.is_empty():
		return null
	var render_time := now + _render_offset
	# Keep two to blend between.
	while _snaps.size() > 2 and _time_of(_snaps[1]) <= render_time:
		_snaps.pop_front()
	var a := _snaps[0]
	if _snaps.size() == 1 or render_time <= _time_of(a):
		return a
	var b := _snaps[1]
	var t := clampf(inverse_lerp(_time_of(a), _time_of(b), render_time), 0.0, 1.0)

	# Positions blend. Everything else comes from the nearer snapshot, all from
	# the same one so they agree.
	var view := Snapshot.new()
	for pb in b.players:
		var pa := a.find_player(pb.id)
		if not pa:
			pa = pb
		var p := (pa if t < 0.5 else pb).copy()
		p.pos = pa.pos.lerp(pb.pos, t)
		view.players.append(p)
	for i in b.dummies.size():
		var db := b.dummies[i]
		var da := a.dummies[i] if i < a.dummies.size() else db
		var d := db.copy()
		d.pos = da.pos.lerp(db.pos, t)
		view.dummies.append(d)
	return view


func _time_of(snap: Snapshot) -> float:
	return float(snap.tick) / Protocol.TICK_RATE


func _on_pong(sent_at: float) -> void:
	_rtt_ms = (_now() - sent_at) * 1000.0


func _update_hud(now: float) -> void:
	while not _snap_arrivals.is_empty() and _snap_arrivals[0] < now - 1.0:
		_snap_arrivals.pop_front()
	var lines := [
		"%s  |  %d players" % [_status, _view.players.size() if _view else 0],
		"fps %d  rtt %s  snaps %d/s  interp %d ms%s  sim lag %d ms  jitter %d ms" % [
			Engine.get_frames_per_second(),
			"%d ms" % _rtt_ms if _rtt_ms >= 0 else "-",
			_snap_arrivals.size(), _interp_ms(), " auto" if _interp_auto else "",
			_lag_sec * 2 * 1000, _jitter_sec * 1000],
		"load %s  %s" % ["%.1f s" % (_load_ms / 1000.0) if _load_ms >= 0 else "-", _url],
	]
	_hud.text = "\n".join(lines)


# Input

func _read_move() -> Vector2:
	if _bot:
		return _bot_move
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


func _bot_tick(now: float) -> void:
	if now >= _bot_next_turn:
		_bot_next_turn = now + BOT_TURN_SEC
		_bot_move = Vector2.from_angle(randi_range(0, World.DIRECTIONS - 1) * World.DIRECTION_STEP)
	if now >= _bot_next_attack:
		_bot_next_attack = now + BOT_ATTACK_SEC
		_attack_count += 1


# Drawing

func _draw_swing(pos: Vector2, facing: Vector2) -> void:
	var points := PackedVector2Array([pos])
	for i in ARC_SEGMENTS + 1:
		var t := float(i) / ARC_SEGMENTS
		var angle := facing.angle() + lerpf(-Tuning.swing_arc / 2, Tuning.swing_arc / 2, t)
		points.append(pos + Vector2.from_angle(angle) * Tuning.swing_radius)
	draw_colored_polygon(points, SWING_COLOR)


class Delayed:
	var release_at: float
	var action: Callable
	## Sent rather than received, so dropped if the connection has gone.
	var outgoing: bool

	func _init(at: float, run: Callable, is_outgoing: bool) -> void:
		release_at = at
		action = run
		outgoing = is_outgoing


## When a snapshot arrived, and how far its server time was ahead of then.
class Transit:
	var arrival: float
	var offset: float

	func _init(at: float, ahead: float) -> void:
		arrival = at
		offset = ahead
