extends Node2D
## Connects to the game server, sends input every tick, and draws the world by
## interpolating between server snapshots. There is no client-side prediction
## yet (Phase 2), so your own movement lags by the round trip plus the
## interpolation delay. Options are listed in README.md.

enum State { CONNECTING, CONNECTED, RETRY_WAIT, REJECTED }

const Protocol := preload("res://net/protocol.gd")
const Tuning := preload("res://sim/tuning.gd")

const PLAYER_COLORS: Array[Color] = [
	Color(0.35, 0.65, 1.0), Color(1.0, 0.55, 0.3), Color(0.45, 0.85, 0.45), Color(0.85, 0.45, 0.9),
]

var net: Node
var args: Dictionary

var _url: String
var _lag_sec := 0.0  # simulated delay each way
var _interp_delay := 0.1
var _bot := false
var _session_id := Crypto.new().generate_random_bytes(16).hex_encode()

var _state := State.CONNECTING
var _status := ""
var _retry_delay := 0.5
var _retry_at := 0.0
var _player_id := 0
var _seq := 0
var _attack_count := 0
var _delayed: Array = []  # [release_time, Callable, outgoing], in release order

var _snaps: Array = []  # {time, players: {id: entry}, dummies}, oldest first
var _view := {}
var _clock_offset := 0.0  # server time minus local time
var _have_clock := false
var _last_snap_at := 0.0
var _snap_arrivals: Array[float] = []
var _rtt_ms := -1.0
var _next_ping_at := 0.0
var _next_hud_at := 0.0
var _load_ms := -1.0

var _camera := Camera2D.new()
var _hud := Label.new()

var _bot_move := Vector2.ZERO
var _bot_next_turn := 0.0
var _bot_next_attack := 0.0
var _quit_at := INF
var _drop_at := INF
var _snap_count := 0
var _max_players_seen := 0


func _ready() -> void:
	_url = args.get("url", _default_url())
	_lag_sec = float(args.get("lag", "0")) / 2000.0
	_interp_delay = float(args.get("interp", "100")) / 1000.0
	_bot = args.has("bot")
	if args.has("quit-after"):
		_quit_at = _now() + float(args["quit-after"])
	if args.has("drop-after"):
		_drop_at = _now() + float(args["drop-after"])
	if OS.has_feature("web"):
		_load_ms = float(JavaScriptBridge.eval("performance.now()", true))

	_setup_input()
	add_child(_camera)
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


func _process(_delta: float) -> void:
	var now := _now()
	_flush_delayed(now)
	match _state:
		State.RETRY_WAIT:
			if now >= _retry_at:
				_connect()
		State.CONNECTED:
			if now - _last_snap_at > Protocol.STALE_AFTER_SEC:
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
	_view = _interpolate(now)
	var me: Array = _view.get("players", {}).get(_player_id, [])
	if not me.is_empty():
		_camera.position = me[1]
	if now >= _next_hud_at:
		_next_hud_at = now + 0.25
		_update_hud(now)
	queue_redraw()

	if now >= _quit_at:
		print("SMOKE player=%d snapshots=%d max_players=%d rtt_ms=%d status=%s" % [
			_player_id, _snap_count, _max_players_seen, _rtt_ms, _status])
		get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _state != State.CONNECTED:
		return
	_seq += 1
	var seq := _seq
	var move := _read_move()
	var attacks := _attack_count
	_outgoing(func() -> void: net.send_input.rpc_id(1, seq, move, attacks))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and not event.is_echo():
		_attack_count += 1


## PLACEHOLDER (art): shapes until there are sprites.
func _draw() -> void:
	draw_rect(Tuning.ARENA, Color(0.35, 0.35, 0.4), false, 2.0)
	for d: Array in _view.get("dummies", []):
		draw_rect(Rect2(d[0] - Vector2(5, 5), Vector2(10, 10)), Color.RED if d[1] else Color(0.55, 0.55, 0.55))
	for p: Array in _view.get("players", {}).values():
		var pos: Vector2 = p[1]
		var facing: Vector2 = p[2]
		var color := PLAYER_COLORS[(p[0] - 1) % PLAYER_COLORS.size()]
		if not p[4]:
			color.a = 0.35
		if p[3] > 0:
			_draw_swing(pos, facing)
		draw_rect(Rect2(pos - Vector2(8, 8), Vector2(16, 16)), color)
		if p[0] == _player_id:
			draw_rect(Rect2(pos - Vector2(9, 9), Vector2(18, 18)), Color.WHITE, false, 1.0)
		draw_line(pos, pos + facing * 14, Color.WHITE, 2.0)


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


func _close_peer() -> void:
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer is WebSocketMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# Simulated latency: every message in either direction waits _lag_sec in one
# queue, so ordering is preserved.

func _outgoing(f: Callable) -> void:
	_delayed.append([_now() + _lag_sec, f, true])


func _incoming(f: Callable) -> void:
	_delayed.append([_now() + _lag_sec, f, false])


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
	if not _have_clock or absf(offset - _clock_offset) > 0.25:
		_clock_offset = offset
		_have_clock = true
	else:
		_clock_offset = lerpf(_clock_offset, offset, 0.05)

	_last_snap_at = now
	_snap_arrivals.append(now)
	_snap_count += 1
	_max_players_seen = maxi(_max_players_seen, snap.players.size())


func _interpolate(now: float) -> Dictionary:
	if _snaps.is_empty():
		return {}
	var render_time := now + _clock_offset - _interp_delay
	while _snaps.size() > 2 and _snaps[1].time <= render_time:
		_snaps.pop_front()
	var a: Dictionary = _snaps[0]
	if _snaps.size() == 1 or render_time <= a.time:
		return a
	var b: Dictionary = _snaps[1]
	var t := clampf((render_time - a.time) / (b.time - a.time), 0.0, 1.0)

	var players := {}
	for id: int in b.players:
		var pb: Array = b.players[id]
		var pa: Array = a.players.get(id, pb)
		players[id] = [id, pa[1].lerp(pb[1], t), pb[2], pa[3], pb[4]]
	var dummies := []
	for i in b.dummies.size():
		var db: Array = b.dummies[i]
		var da: Array = a.dummies[i] if i < a.dummies.size() else db
		dummies.append([da[0].lerp(db[0], t), db[1]])
	return {"players": players, "dummies": dummies}


func _on_pong(sent_at: float) -> void:
	_rtt_ms = (_now() - sent_at) * 1000.0


func _update_hud(now: float) -> void:
	while not _snap_arrivals.is_empty() and _snap_arrivals[0] < now - 1.0:
		_snap_arrivals.pop_front()
	var lines := [
		"%s  |  %d players" % [_status, _view.get("players", {}).size()],
		"fps %d  rtt %s  snaps %d/s  interp %d ms  sim lag %d ms" % [
			Engine.get_frames_per_second(),
			"%d ms" % _rtt_ms if _rtt_ms >= 0 else "-",
			_snap_arrivals.size(), _interp_delay * 1000, _lag_sec * 2000],
		"load %s  %s" % ["%.1f s" % (_load_ms / 1000.0) if _load_ms >= 0 else "-", _url],
	]
	_hud.text = "\n".join(lines)


# Input

func _read_move() -> Vector2:
	if _bot:
		return _bot_move
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _bot_tick(now: float) -> void:
	if now >= _bot_next_turn:
		_bot_next_turn = now + 1.0
		_bot_move = Vector2.from_angle(randi_range(0, 7) * PI / 4)
	if now >= _bot_next_attack:
		_bot_next_attack = now + 0.5
		_attack_count += 1


## PLACEHOLDER (design): bindings.
func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT], JOY_AXIS_LEFT_X, -1.0, JOY_BUTTON_DPAD_LEFT)
	_add_action("move_right", [KEY_D, KEY_RIGHT], JOY_AXIS_LEFT_X, 1.0, JOY_BUTTON_DPAD_RIGHT)
	_add_action("move_up", [KEY_W, KEY_UP], JOY_AXIS_LEFT_Y, -1.0, JOY_BUTTON_DPAD_UP)
	_add_action("move_down", [KEY_S, KEY_DOWN], JOY_AXIS_LEFT_Y, 1.0, JOY_BUTTON_DPAD_DOWN)
	_add_action("attack", [KEY_SPACE, KEY_J], JOY_AXIS_INVALID, 0.0, JOY_BUTTON_A)


func _add_action(action: StringName, keys: Array, axis: JoyAxis, axis_value: float, button: JoyButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.25)
	for key: Key in keys:
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(action, e)
	if axis != JOY_AXIS_INVALID:
		var e := InputEventJoypadMotion.new()
		e.axis = axis
		e.axis_value = axis_value
		InputMap.action_add_event(action, e)
	var b := InputEventJoypadButton.new()
	b.button_index = button
	InputMap.action_add_event(action, b)



# Drawing

func _draw_swing(pos: Vector2, facing: Vector2) -> void:
	var points := PackedVector2Array([pos])
	for i in 13:
		var angle := facing.angle() + lerpf(-Tuning.SWING_ARC / 2, Tuning.SWING_ARC / 2, i / 12.0)
		points.append(pos + Vector2.from_angle(angle) * Tuning.SWING_RADIUS)
	draw_colored_polygon(points, Color(1, 1, 1, 0.3))
