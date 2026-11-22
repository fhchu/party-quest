extends CanvasLayer
## The debug overlay, top left: status, players, fps, ping, RTT, snapshots
## per second, measured jitter, the drawing delay (IND), simulated lag and
## jitter, the latest snapshot's size, how long the page took to load and to
## join, and which server it's connected to.
##
## It learns all of this from the client's signals, which the client
## connects to the note_ methods and [method update].
##
## Ping is a ping message's round trip. RTT is from an input change (starting
## to move, or an attack) to the first snapshot showing it on your own
## character, so it adds the server's tick wait to the network. IND is how
## far behind the newest snapshot the drawing is. All three read "-" without
## a live connection, since the last values would be stale.

const MARGIN := Vector2(4, 4)
const FONT_SIZE := 10
## Slow enough to read, fast enough to stay current.
const EVERY_SEC := 0.25
## Ping and RTT are averaged over this long: short enough that a brief spike
## shows, as in Overwatch's latency figure.
const AVERAGE_SEC := 3.0

# Set before the overlay enters the tree.
## The simulated round trip added, in ms.
var sim_lag_ms := 0
var sim_jitter_ms := 0
## Where the client connects, as shown.
var server: String

var _label := Label.new()
var _next_at := 0.0
## Snapshot arrival times over the last second, for the per-second count.
var _arrivals: Array[float] = []
## -1 until measured.
var _load_ms := -1.0
## Bytes of the latest snapshot.
var _snap_bytes := 0
## Since the page started loading, until the first welcome; -1 until then.
var _join_ms := -1.0
var _jitter_ms := 0
var _delay_ms := 0
var _adapting := false
## Oldest first.
var _pings: Array[Sample] = []
## Oldest first.
var _rtts: Array[Sample] = []
## RTT is measured only when you act, so the last average stays up while you
## don't; -1 until the first.
var _rtt_average_ms := -1.0
## When an input change went out that no snapshot has shown yet; -1 when
## none is waiting.
var _rtt_since := -1.0
## The last input sent, to tell when one changes.
var _sent_move := Vector2.ZERO
var _sent_attacks := 0
## Your own character in the last snapshot; [member _own_seen] is false
## before one or when it wasn't in it.
var _own_seen := false
var _own_pos := Vector2.ZERO
var _own_swing_ticks := 0


static func _seconds(ms: float) -> String:
	return "%.1f s" % (ms / 1000.0) if ms >= 0 else "-"


static func _ms(ms: float) -> String:
	return "%d ms" % roundi(ms) if ms >= 0 else "-"


## The mean of [param samples] after dropping those older than
## [constant AVERAGE_SEC] before [param now]; -1 if none are left.
static func _recent_average(samples: Array[Sample], now: float) -> float:
	while not samples.is_empty() and samples[0].at < now - AVERAGE_SEC:
		samples.pop_front()
	if samples.is_empty():
		return -1.0
	var total := 0.0
	for s in samples:
		total += s.ms
	return total / samples.size()


func _ready() -> void:
	_label.position = MARGIN
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(_label)
	if OS.has_feature("web"):
		# Since the page started loading.
		_load_ms = JavaScriptBridge.get_interface("performance").now()


## The server welcomed this client. Only the first time counts.
func note_joined() -> void:
	if _join_ms < 0 and OS.has_feature("web"):
		_join_ms = JavaScriptBridge.get_interface("performance").now()


## The connection is gone, so no snapshot can answer an input sent on it.
## The next one counts presses from zero.
func note_connection_ended() -> void:
	_rtt_since = -1.0
	_own_seen = false
	_sent_move = Vector2.ZERO
	_sent_attacks = 0


## Input went to the server. Starting to move or a new attack starts timing
## the RTT, unless one is already timed.
func note_input(now: float, move: Vector2, attack_count: int) -> void:
	var started_moving := move != Vector2.ZERO and _sent_move == Vector2.ZERO
	if (started_moving or attack_count > _sent_attacks) and _rtt_since < 0:
		_rtt_since = now
	_sent_move = move
	_sent_attacks = attack_count


## A snapshot was taken. [param bytes] is its size on the wire; the rest is
## your own character in it, if [param own_seen]. It ends the RTT timing if
## your character answers: moving, or starting a swing.
func note_snapshot(now: float, bytes: int, own_seen: bool, own_pos: Vector2,
		own_swing_ticks: int) -> void:
	_arrivals.append(now)
	_snap_bytes = bytes
	var answered := (own_seen and _own_seen
			and (own_pos != _own_pos or (own_swing_ticks > 0 and _own_swing_ticks == 0)))
	if _rtt_since >= 0 and answered:
		_rtts.append(Sample.new(now, (now - _rtt_since) * 1000.0))
		_rtt_since = -1.0
	_own_seen = own_seen
	_own_pos = own_pos
	_own_swing_ticks = own_swing_ticks


func note_ping(now: float, ms: float) -> void:
	_pings.append(Sample.new(now, ms))


## The drawing's measured jitter and delay; [param adapting] is whether the
## delay adapts.
func note_drawing(jitter_ms: int, delay_ms: int, adapting: bool) -> void:
	_jitter_ms = jitter_ms
	_delay_ms = delay_ms
	_adapting = adapting


## Redraws at most every [constant EVERY_SEC]. [param connected] is whether
## the client holds a live connection the server has welcomed.
func update(now: float, status: String, players: int, connected: bool) -> void:
	if not connected:
		_pings.clear()
		_rtts.clear()
		_rtt_average_ms = -1.0
	if now < _next_at:
		return
	_next_at = now + EVERY_SEC
	while not _arrivals.is_empty() and _arrivals[0] < now - 1.0:
		_arrivals.pop_front()
	var rtt := _recent_average(_rtts, now)
	if rtt >= 0:
		_rtt_average_ms = rtt
	var ind := _ms(_delay_ms) if connected else "-"
	var lines := [
		"%s  |  %d players" % [status, players],
		"fps %d  ping %s  RTT %s  snaps %d/s  jitter %d ms  IND %s%s" % [
			Engine.get_frames_per_second(), _ms(_recent_average(_pings, now)),
			_ms(_rtt_average_ms), _arrivals.size(), _jitter_ms, ind,
			" auto" if _adapting else ""],
		"sim lag %d ms  sim jitter %d ms" % [sim_lag_ms, sim_jitter_ms],
		"snapshot %d B" % _snap_bytes,
		"load %s  joined %s  %s" % [_seconds(_load_ms), _seconds(_join_ms), server],
	]
	_label.text = "\n".join(lines)


## One measurement, in ms, taken at [member at] seconds.
class Sample:
	var at: float
	var ms: float

	func _init(taken_at: float, measured_ms: float) -> void:
		at = taken_at
		ms = measured_ms
