extends CanvasLayer
## The debug HUD, top left: status, players, fps, round trip, snapshots per
## second, the drawing delay, simulated lag and jitter, load time, URL.

const Interpolator := preload("res://client/interpolator.gd")
const Options := preload("res://util/options.gd")

const MARGIN := Vector2(4, 4)
const FONT_SIZE := 10
## Slow enough to read, fast enough to stay current.
const EVERY_SEC := 0.25

var _label := Label.new()
var _next_at := 0.0
## Snapshot arrival times over the last second, for the per-second count.
var _arrivals: Array[float] = []
## -1 until measured.
var _load_ms := -1.0


func _ready() -> void:
	_label.position = MARGIN
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(_label)
	if OS.has_feature("web"):
		# Since the page started loading.
		_load_ms = JavaScriptBridge.get_interface("performance").now()


func note_snapshot(now: float) -> void:
	_arrivals.append(now)


## Redraws at most every [constant EVERY_SEC]. [param rtt_ms] is -1 until
## measured.
func update(now: float, status: String, players: int, rtt_ms: float,
		interp: Interpolator, options: Options, url: String) -> void:
	if now < _next_at:
		return
	_next_at = now + EVERY_SEC
	while not _arrivals.is_empty() and _arrivals[0] < now - 1.0:
		_arrivals.pop_front()
	var lines := [
		"%s  |  %d players" % [status, players],
		"fps %d  rtt %s  snaps %d/s  interp %d ms%s  sim lag %d ms  jitter %d ms" % [
			Engine.get_frames_per_second(),
			"%d ms" % rtt_ms if rtt_ms >= 0 else "-",
			_arrivals.size(), interp.delay_ms(), "" if interp.fixed else " auto",
			options.lag_sec * 2 * 1000, options.jitter_sec * 1000],
		"load %s  %s" % ["%.1f s" % (_load_ms / 1000.0) if _load_ms >= 0 else "-", url],
	]
	_label.text = "\n".join(lines)
