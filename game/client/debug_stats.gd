extends RefCounted
## The debug overlay's numbers: status, RTT, snapshots per second, measured
## jitter, the drawing delay (IND), simulated lag and jitter, the latest
## snapshot's size, snapshot loss, how long the page took to load and to join, and which
## server it's connected to. [method text] writes them out. It also averages
## the ping, which the HUD shows.
##
## Ping is a ping message's round trip. RTT is from an input change (starting
## to move, or an attack) to the first snapshot showing it on your own
## character, so it adds the server's tick wait to the network. IND is how
## far behind the newest snapshot the drawing is. RTT and IND read "-"
## without a live connection, since the last values would be stale. Loss is
## the share of snapshots that never arrived, and late those that arrived
## after a newer one and were dropped, both over the last few seconds.

const Interpolator := preload("res://client/interpolator.gd")

## Ping and RTT are averaged over this long: short enough that a brief spike
## shows, as in Overwatch's latency figure.
const AVERAGE_SEC := 3.0

# Set once by the client.
## The simulated round trip added, in ms.
var sim_lag_ms := 0
var sim_jitter_ms := 0
## Where the client connects, as shown.
var server := ""

## Snapshot arrival times over the last second, for the per-second count.
var _arrivals: Array[float] = []
## -1 until measured.
var _load_ms := -1.0
## Bytes of the latest snapshot.
var _snap_bytes := 0
## Since the page started loading, until the first welcome; -1 until then.
var _join_ms := -1.0
## The client's clock when the page finished loading.
var _loaded_at := 0.0
## Oldest first.
var _pings: Array[Sample] = []
## Oldest first.
var _rtts: Array[Sample] = []
## Running frame totals, oldest first.
var _frame_counts: Array[FrameCount] = []
## RTT is measured only when you act, so the last average stays up while you
## don't; -1 until the first.
var _rtt_average_ms := -1.0
## When an input change went out that no snapshot has shown yet; -1 when
## none is waiting.
var _rtt_since := -1.0
## Whether the last input sent was a move.
var _moving := false
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


## The page finished loading at [param now], [param page_ms] after it
## started.
func page_loaded(now: float, page_ms: float) -> void:
	_loaded_at = now
	_load_ms = page_ms


## The server welcomed this client. Only the first time counts.
func note_joined(now: float) -> void:
	if _join_ms < 0 and _load_ms >= 0:
		_join_ms = _load_ms + (now - _loaded_at) * 1000.0


## The connection is gone: what was measured on it is stale, and no snapshot
## can answer an input sent on it.
func note_connection_lost() -> void:
	_pings.clear()
	_rtts.clear()
	_frame_counts.clear()
	_rtt_average_ms = -1.0
	_rtt_since = -1.0
	_moving = false
	_own_seen = false


## An attack press starts timing the RTT, unless one is already timed.
func note_attack(now: float) -> void:
	_start_rtt(now)


## Input went to the server; starting to move starts timing the RTT.
func note_input(now: float, move: Vector2) -> void:
	if move != Vector2.ZERO and not _moving:
		_start_rtt(now)
	_moving = move != Vector2.ZERO


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


## The connection's running totals of ordered frames: taken, skipped over
## (late ones included) and late.
func note_frames(now: float, received: int, missed: int, late: int) -> void:
	_frame_counts.append(FrameCount.new(now, received, missed, late))


## The average ping at [param now]; -1 if none is recent or since the
## connection was lost.
func ping_ms(now: float) -> float:
	return _recent_average(_pings, now)


## The overlay's lines at [param now]. [param connected] is whether the
## client holds a live connection the server has welcomed;
## [param interpolator] is the drawing's.
func text(now: float, status: String, connected: bool, interpolator: Interpolator) -> String:
	while not _arrivals.is_empty() and _arrivals[0] < now - 1.0:
		_arrivals.pop_front()
	var rtt := _recent_average(_rtts, now)
	if rtt >= 0:
		_rtt_average_ms = rtt
	var rtt_shown := _rtt_average_ms if connected else -1.0
	var ind := _ms(interpolator.delay_ms()) if connected else "-"
	var lines := [
		status,
		"RTT %s  snaps %d/s  jitter %d ms  IND %s%s" % [
			_ms(rtt_shown), _arrivals.size(), interpolator.jitter_ms(), ind,
			"" if interpolator.fixed else " auto"],
		"sim lag %d ms  sim jitter %d ms" % [sim_lag_ms, sim_jitter_ms],
		"snapshot %d B  %s" % [_snap_bytes, _recent_loss(now)],
		"load %s  joined %s  %s" % [_seconds(_load_ms), _seconds(_join_ms), server],
	]
	return "\n".join(lines)


## Loss and late over the last [constant AVERAGE_SEC] before [param now],
## as shown; "-" without two totals to compare.
func _recent_loss(now: float) -> String:
	while _frame_counts.size() > 2 and _frame_counts[1].at < now - AVERAGE_SEC:
		_frame_counts.pop_front()
	if _frame_counts.size() < 2:
		return "loss -  late -"
	var first: FrameCount = _frame_counts[0]
	var last: FrameCount = _frame_counts[-1]
	var missed := last.missed - first.missed
	var late := last.late - first.late
	var expected := last.received - first.received + missed
	if expected == 0:
		return "loss -  late -"
	# A late frame left a gap that it then filled, so it isn't lost.
	var lost := maxi(missed - late, 0)
	return "loss %.1f%%  late %d" % [100.0 * lost / expected, late]


func _start_rtt(now: float) -> void:
	if _rtt_since < 0:
		_rtt_since = now


## A connection's running frame totals, read at [member at] seconds.
class FrameCount:
	var at: float
	var received: int
	var missed: int
	var late: int

	func _init(read_at: float, total_received: int, total_missed: int, total_late: int) -> void:
		at = read_at
		received = total_received
		missed = total_missed
		late = total_late


## One measurement, in ms, taken at [member at] seconds.
class Sample:
	var at: float
	var ms: float

	func _init(taken_at: float, measured_ms: float) -> void:
		at = taken_at
		ms = measured_ms
