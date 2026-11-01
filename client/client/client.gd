extends Node2D
## Connects to the game server, sends input every tick, and draws the world.
##
## Nothing is predicted: everything, your own player included, is drawn
## between two snapshots, as far in the past as [method _update_render_offset]
## decides. Options are listed in README.md.

enum State { CONNECTING, CONNECTED, RETRY_WAIT, REJECTED }

const Protocol := preload("res://net/protocol.gd")
const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")

const SNAP_INTERVAL := float(Protocol.SNAPSHOT_EVERY) / Protocol.TICK_RATE
## How far back snapshot arrival times are remembered to size the delay.
const TRANSIT_WINDOW_SEC := 3.0
## Extra delay beyond the latest arrival in the window.
const INTERP_MARGIN_SEC := 0.01
## How fast the delay grows and shrinks, in seconds per second: growing plays
## at 80% speed for a moment, shrinking at 102%, too little to notice.
const INTERP_RISE := 0.2
const INTERP_FALL := 0.02

const PLAYER_COLORS: Array[Color] = [
	Color(0.35, 0.65, 1.0),
	Color(1.0, 0.55, 0.3),
	Color(0.45, 0.85, 0.45),
	Color(0.85, 0.45, 0.9),
]

var net: Node
var args: Dictionary

var _url: String
var _lag_sec := 0.0  # Simulated delay each way.
var _jitter_sec := 0.0  # Longest simulated hold-up.
var _interp_delay := 0.1  # The interp option; also the starting delay.
var _interp_auto := true
var _bot := false
var _session_id: String
var _visibility_cb: JavaScriptObject  # Kept so the JS listener stays alive.
var _away_sent := false

var _state := State.CONNECTING
var _status := ""
var _retry_delay := 0.5
var _retry_at := 0.0
var _player_id := 0
var _seq := 0
var _attack_count := 0
var _hold_ticks := 0  # Since the last press.
var _delayed: Array = []  # [release_time, Callable, outgoing], in release order.

var _snaps: Array = []  # {time, players: {id: entry}, dummies}, oldest first.
var _view := {}
var _clock_offset := 0.0  # Server time minus local time, smoothed.
var _have_clock := false
var _render_offset := 0.0  # Added to local time to get the time drawn.
var _transits: Array = []  # [arrival, snapshot time minus arrival], oldest first.
var _last_snap_at := 0.0
var _snap_arrivals: Array[float] = []
var _rtt_ms := -1.0
var _next_ping_at := 0.0
var _next_hud_at := 0.0
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
	var x := half.x / absf(dir.x) if absf(dir.x) > 0.001 else INF
	var y := half.y / absf(dir.y) if absf(dir.y) > 0.001 else INF
	return minf(x, y)


func _ready() -> void:
	_url = args.get("url", _default_url())
	_session_id = _load_session_id()
	_lag_sec = float(args.get("lag", "0")) / 2000.0
	_jitter_sec = float(args.get("jitter", "0")) / 1000.0
	_interp_auto = not args.has("interp")
	_interp_delay = float(args.get("interp", "100")) / 1000.0
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
	_hud.position = Vector2(4, 4)
	_hud.add_theme_font_size_override("font_size", 10)
	layer.add_child(_hud)

	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_lost)
	multiplayer.server_disconnected.connect(_on_lost)
	net.welcomed.connect(func(id: int) -> void: _incoming(_on_welcomed.bind(id)))
	net.rejected.connect(func(reason: String) -> void: _incoming(_on_rejected.bind(reason)))
	net.snapshot_received.connect(func(data: Array) -> void: _incoming(_on_snapshot.bind(data)))
	net.pong_received.connect(func(sent_at: float) -> void: _incoming(_on_pong.bind(sent_at)))
	_connect()


func _process(delta: float) -> void:
	var now := _now()
	_flush_delayed(now)
	match _state:
		State.RETRY_WAIT:
			if now >= _retry_at:
				_connect()
		State.CONNECTED:
			# No snapshots come while away.
			if not _away_sent and now - _last_snap_at > Protocol.STALE_AFTER_SEC:
				_status = "no snapshots, reconnecting"
				_schedule_retry()
			elif now >= _next_ping_at:
				_next_ping_at = now + 1.0
				_outgoing(func() -> void: net.ping.rpc_id(1, now))

	if now >= _drop_at:
		_drop_at = INF
		_status = "dropped (test)"
		_schedule_retry()
	if _bot:
		_bot_tick(now)
	_update_render_offset(now, delta)
	_view = _interpolate(now)
	if now >= _next_hud_at:
		_next_hud_at = now + 0.25
		_update_hud(now)
	queue_redraw()

	if now >= _quit_at:
		print("SMOKE player=%d snapshots=%d max_players=%d rtt_ms=%d interp_ms=%d status=%s" % [
			_player_id, _snap_count, _max_players_seen, _rtt_ms, _interp_ms(), _status])
		get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _state != State.CONNECTED:
		return
	_seq += 1
	var seq := _seq
	var move := _read_move()
	_hold_repeat()
	var attacks := _attack_count
	_outgoing(func() -> void: net.send_input.rpc_id(1, seq, move, attacks))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and not event.is_echo():
		_attack_count += 1
		_hold_ticks = 0


## PLACEHOLDER (art): shapes the size of their hurtboxes until there are sprites.
func _draw() -> void:
	draw_rect(Tuning.arena, Color(0.35, 0.35, 0.4), false, 2.0)
	for d: Array in _view.get("dummies", []):
		var size := Tuning.target_dummy_hurtbox if d[2] else Tuning.DUMMY_HURTBOX
		var dummy_color := Color(0.8, 0.65, 0.4) if d[2] else Color(0.55, 0.55, 0.55)
		if d[1]:
			dummy_color = Color.WHITE
		draw_rect(World.hurtbox(d[0], size), dummy_color)
	for p: Array in _view.get("players", {}).values():
		var pos: Vector2 = p[1]
		var facing: Vector2 = p[2]
		var color := PLAYER_COLORS[(p[0] - 1) % PLAYER_COLORS.size()]
		# DEBUG: fade disconnected players; remove with the real UI.
		if not p[4]:
			color.a = 0.35
		if p[3] > 0:
			_draw_swing(pos, facing)
		# Only the swing may leave the hurtbox, so a player at a wall stays on screen.
		var box := World.hurtbox(pos, Tuning.player_hurtbox)
		draw_rect(box, color)
		if p[0] == _player_id:
			draw_rect(box.grow(-0.5), Color.WHITE, false, 1.0)
		draw_line(pos, pos + facing * _to_box_edge(facing, box.size / 2), Color.WHITE, 2.0)


## On web the ID is kept in sessionStorage, so a reload rejoins as the same
## player while each tab is its own player.
func _load_session_id() -> String:
	var fresh := Crypto.new().generate_random_bytes(16).hex_encode()
	if not OS.has_feature("web"):
		return fresh
	# Storage can throw; then every load gets a fresh ID.
	var stored := str(JavaScriptBridge.eval(
			"(() => { try { return sessionStorage.getItem('pq_session') || ''; }"
			+ " catch (e) { return ''; } })()", true))
	if stored != "":
		return stored
	JavaScriptBridge.eval(
			"(() => { try { sessionStorage.setItem('pq_session', '%s'); }"
			% fresh + " catch (e) {} })()", true)
	return fresh


func _default_url() -> String:
	if not OS.has_feature("web"):
		return "ws://127.0.0.1:%d" % Protocol.DEFAULT_PORT
	var host := str(JavaScriptBridge.eval("window.location.hostname", true))
	if str(JavaScriptBridge.eval("window.location.protocol", true)) == "https:":
		# PLACEHOLDER (hosting): assumes a TLS proxy routes /ws to the game server.
		return "wss://%s/ws" % host
	return "ws://%s:%d" % [host, Protocol.DEFAULT_PORT]


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# Connection lifecycle

func _connect() -> void:
	_state = State.CONNECTING
	_status = "connecting"
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(_url)
	if err != OK:
		_status = "connect error: %s" % error_string(err)
		_schedule_retry()
		return
	multiplayer.multiplayer_peer = peer


func _on_connected() -> void:
	_status = "connected, waiting for welcome"
	_outgoing(func() -> void: net.hello.rpc_id(1, _session_id))


func _on_welcomed(player_id: int) -> void:
	_player_id = player_id
	_state = State.CONNECTED
	# The server counts presses from scratch per connection.
	_attack_count = 0
	_hold_ticks = 0
	_status = "player %d" % player_id
	_retry_delay = 0.5
	_last_snap_at = _now()


func _on_rejected(reason: String) -> void:
	_state = State.REJECTED
	_status = "rejected: %s" % reason


func _on_lost() -> void:
	if _state == State.REJECTED:
		return
	_status = "connection lost"
	_schedule_retry()


func _schedule_retry() -> void:
	_state = State.RETRY_WAIT
	_retry_at = _now() + _retry_delay
	_retry_delay = minf(_retry_delay * 2, 5.0)
	_delayed.clear()
	_snaps.clear()
	_have_clock = false
	_close_peer.call_deferred()


## Tells the server when the tab is hidden or shown. Chrome pauses the game
## loop in a hidden tab but JavaScript still calls this, so it sends directly
## instead of through the lag queue.
func _on_visibility_change(_args: Array) -> void:
	var hidden := bool(JavaScriptBridge.eval("document.hidden", true))
	if hidden and not _away_sent and _state == State.CONNECTED:
		_away_sent = true
		_delayed.clear()
		net.set_away.rpc_id(1, true)
	elif not hidden and _away_sent:
		_away_sent = false
		# Don't let the stale check reconnect over the gap.
		_last_snap_at = _now()
		if _online():
			net.set_away.rpc_id(1, false)


func _close_peer() -> void:
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (peer is WebSocketMultiplayerPeer
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)


# Simulated latency: messages both ways share one queue, so order is kept, as
# with TCP.

func _outgoing(f: Callable) -> void:
	_delayed.append([_now() + _lag_sec + _jitter(), f, true])


func _incoming(f: Callable) -> void:
	_delayed.append([_now() + _lag_sec + _jitter(), f, false])


## Holds up 1 message in 30 (a couple a second), delaying everything behind it
## like a Wi-Fi hiccup. A random delay on every message would just add the
## largest one to all of them, since order is kept.
func _jitter() -> float:
	return randf() * _jitter_sec if randf() < 1.0 / 30.0 else 0.0


func _flush_delayed(now: float) -> void:
	while not _delayed.is_empty() and _delayed[0][0] <= now:
		var item: Array = _delayed.pop_front()
		if not item[2] or _online():
			item[1].call()


# Snapshots and interpolation

func _on_snapshot(data: Array) -> void:
	var now := _now()
	var snap := {"time": float(data[0]) / Protocol.TICK_RATE, "players": {}, "dummies": data[2]}
	for p: Array in data[1]:
		snap.players[p[0]] = p
	if not _snaps.is_empty() and snap.time <= _snaps[-1].time:
		return
	_snaps.append(snap)

	var offset: float = snap.time - now
	_transits.append([now, offset])
	if not _have_clock or absf(offset - _clock_offset) > 0.25:
		_clock_offset = offset
		if not _have_clock:
			_render_offset = _clock_offset - _interp_delay
		_have_clock = true
	else:
		_clock_offset = lerpf(_clock_offset, offset, 0.05)

	_last_snap_at = now
	_snap_arrivals.append(now)
	_snap_count += 1
	_max_players_seen = maxi(_max_players_seen, snap.players.size())


## Picks how far in the past to draw: one snapshot interval plus a margin
## behind the latest-arriving snapshot of the last few seconds, so the next
## snapshot is there when needed. It drifts rather than jumps, so motion only
## speeds up or slows down a little.
func _update_render_offset(now: float, delta: float) -> void:
	while not _transits.is_empty() and _transits[0][0] < now - TRANSIT_WINDOW_SEC:
		_transits.pop_front()
	if not _have_clock:
		return
	if not _interp_auto or _transits.is_empty():
		_render_offset = _clock_offset - _interp_delay
		return
	var latest: float = _transits.reduce(
			func(m: float, t: Array) -> float: return minf(m, t[1]), INF)
	var target := latest - SNAP_INTERVAL - INTERP_MARGIN_SEC
	# A hidden tab's frames stop, so a long delta mustn't move it all at once.
	var step := minf(delta, 0.1)
	if target < _render_offset:
		_render_offset = maxf(target, _render_offset - INTERP_RISE * step)
	else:
		_render_offset = minf(target, _render_offset + INTERP_FALL * step)


## How far behind the newest snapshots the drawing is.
func _interp_ms() -> int:
	return roundi((_clock_offset - _render_offset) * 1000.0)


func _interpolate(now: float) -> Dictionary:
	if _snaps.is_empty():
		return {}
	var render_time := now + _render_offset
	while _snaps.size() > 2 and _snaps[1].time <= render_time:
		_snaps.pop_front()
	var a: Dictionary = _snaps[0]
	if _snaps.size() == 1 or render_time <= a.time:
		return a
	var b: Dictionary = _snaps[1]
	var t := clampf((render_time - a.time) / (b.time - a.time), 0.0, 1.0)

	# Positions blend. Everything else comes from the nearer snapshot, all from
	# the same one so they agree.
	var players := {}
	for id: int in b.players:
		var pb: Array = b.players[id]
		var pa: Array = a.players.get(id, pb)
		var near: Array = pa if t < 0.5 else pb
		players[id] = [id, pa[1].lerp(pb[1], t), near[2], near[3], near[4]]
	var dummies := []
	for i in b.dummies.size():
		var db: Array = b.dummies[i]
		var da: Array = a.dummies[i] if i < a.dummies.size() else db
		dummies.append([da[0].lerp(db[0], t), db[1], db[2]])
	return {"players": players, "dummies": dummies}


func _on_pong(sent_at: float) -> void:
	_rtt_ms = (_now() - sent_at) * 1000.0


func _update_hud(now: float) -> void:
	while not _snap_arrivals.is_empty() and _snap_arrivals[0] < now - 1.0:
		_snap_arrivals.pop_front()
	var lines := [
		"%s  |  %d players" % [_status, _view.get("players", {}).size()],
		"fps %d  rtt %s  snaps %d/s  interp %d ms%s  sim lag %d ms  jitter %d ms" % [
			Engine.get_frames_per_second(),
			"%d ms" % _rtt_ms if _rtt_ms >= 0 else "-",
			_snap_arrivals.size(), _interp_ms(), " auto" if _interp_auto else "",
			_lag_sec * 2000, _jitter_sec * 1000],
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
		_bot_next_turn = now + 1.0
		_bot_move = Vector2.from_angle(randi_range(0, 7) * PI / 4)
	if now >= _bot_next_attack:
		_bot_next_attack = now + 0.5
		_attack_count += 1


# Drawing

func _draw_swing(pos: Vector2, facing: Vector2) -> void:
	var points := PackedVector2Array([pos])
	for i in 13:
		var t := i / 12.0
		var angle := facing.angle() + lerpf(-Tuning.swing_arc / 2, Tuning.swing_arc / 2, t)
		points.append(pos + Vector2.from_angle(angle) * Tuning.swing_radius)
	draw_colored_polygon(points, Color(1, 1, 1, 0.3))
