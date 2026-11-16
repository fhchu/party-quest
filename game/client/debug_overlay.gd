extends CanvasLayer
## The debug overlay, top left: status, players, fps, round trip, snapshots per
## second, measured jitter, the drawing delay, simulated lag and jitter,
## the latest snapshot's size, how long the page took to load
## and to join, and which server it's connected to.

const MARGIN := Vector2(4, 4)
const FONT_SIZE := 10
## Slow enough to read, fast enough to stay current.
const EVERY_SEC := 0.25

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


static func _seconds(ms: float) -> String:
	return "%.1f s" % (ms / 1000.0) if ms >= 0 else "-"


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


## [param bytes] is the snapshot's size on the wire.
func note_snapshot(now: float, bytes: int) -> void:
	_arrivals.append(now)
	_snap_bytes = bytes


## The drawing's measured jitter and delay; [param adapting] is whether the
## delay adapts.
func note_drawing(jitter_ms: int, delay_ms: int, adapting: bool) -> void:
	_jitter_ms = jitter_ms
	_delay_ms = delay_ms
	_adapting = adapting


## Redraws at most every [constant EVERY_SEC]. [param rtt_ms] is -1 until
## measured.
func update(now: float, status: String, players: int, rtt_ms: float) -> void:
	if now < _next_at:
		return
	_next_at = now + EVERY_SEC
	while not _arrivals.is_empty() and _arrivals[0] < now - 1.0:
		_arrivals.pop_front()
	var lines := [
		"%s  |  %d players" % [status, players],
		"fps %d  rtt %s  snaps %d/s  jitter %d ms  interp %d ms%s" % [
			Engine.get_frames_per_second(),
			"%d ms" % rtt_ms if rtt_ms >= 0 else "-",
			_arrivals.size(), _jitter_ms, _delay_ms, " auto" if _adapting else ""],
		"sim lag %d ms  sim jitter %d ms" % [sim_lag_ms, sim_jitter_ms],
		"snapshot %d B" % _snap_bytes,
		"load %s  joined %s  %s" % [_seconds(_load_ms), _seconds(_join_ms), server],
	]
	_label.text = "\n".join(lines)
