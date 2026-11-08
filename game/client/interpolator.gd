extends RefCounted
## Decides how far in the past to draw, and blends two snapshots for that
## moment. Nothing is predicted: everything, your own player included, is
## drawn between snapshots that have already arrived.

const Protocol := preload("res://net/protocol.gd")
const Snapshot := preload("res://net/snapshot.gd")

## How far back arrival times count when sizing the delay. Untuned: longer
## remembers hiccups that are further apart, shorter recovers sooner once the
## link steadies.
const TRANSIT_WINDOW_SEC := 3.0
## Slack for frame timing.
const MARGIN_SEC := 0.01
# How fast the delay grows and shrinks, in seconds per second: growing plays
# at 80% speed for a moment, shrinking at 102%, too little to notice.
const RISE := 0.2
const FALL := 0.02
## A hidden tab's frames stop, so one long frame mustn't move the delay all
## at once. This is a few normal frames.
const MAX_STEP_SEC := 0.1
## The delay until snapshots have sized it. It adapts within seconds, so it
## only needs to be safe.
const START_SEC := 0.1
## How far each snapshot moves the clock toward its own reading: a small step,
## so jitter averages out.
const CLOCK_SMOOTHING := 0.05
## A reading this far off resets the clock, since smoothing would take seconds
## to get there.
const CLOCK_RESET_SEC := 0.25
## How much each snapshot moves the jitter estimate: 1/16, as RTP's
## interarrival jitter does (RFC 3550, section 6.4.1).
const JITTER_GAIN := 1.0 / 16

## Keep the delay at [member delay_sec] instead of adapting it.
var fixed := false
## The fixed delay, and the starting one when adapting.
var delay_sec := START_SEC

## Oldest first.
var _snaps: Array[Snapshot] = []
## Oldest first.
var _transits: Array[Transit] = []
## Server time minus local time, smoothed.
var _clock_offset := 0.0
var _have_clock := false
## Added to local time to get the time drawn.
var _render_offset := 0.0
## The smoothed change in transit time from one snapshot to the next, in
## seconds: how unevenly snapshots arrive.
var _jitter := 0.0


static func time_of(snap: Snapshot) -> float:
	return float(snap.tick) / Protocol.TICK_RATE


## Returns false for a snapshot no newer than one already held. The first
## snapshot of a new world replaces the old world's, so nothing from it
## (a swing, a flash) is drawn after the room moves on.
func add(snap: Snapshot, now: float) -> bool:
	if not _snaps.is_empty() and snap.tick <= _snaps[-1].tick:
		return false
	if not _snaps.is_empty() and snap.world_number != _snaps[-1].world_number:
		_snaps.clear()
	_snaps.append(snap)
	var offset := time_of(snap) - now
	if not _transits.is_empty():
		var change := absf(offset - _transits[-1].offset)
		_jitter += (change - _jitter) * JITTER_GAIN
	_transits.append(Transit.new(now, offset))
	if not _have_clock or absf(offset - _clock_offset) > CLOCK_RESET_SEC:
		_clock_offset = offset
		if not _have_clock:
			_render_offset = _clock_offset - delay_sec
		_have_clock = true
	else:
		_clock_offset = lerpf(_clock_offset, offset, CLOCK_SMOOTHING)
	return true


## Moves the delay toward one snapshot interval plus a margin behind the
## latest-arriving snapshot of the last few seconds, so the next snapshot is
## there when needed. It drifts rather than jumps, so motion only speeds up
## or slows down a little.
func update(now: float, delta: float) -> void:
	while not _transits.is_empty() and _transits[0].arrival < now - TRANSIT_WINDOW_SEC:
		_transits.pop_front()
	if not _have_clock:
		return
	if fixed or _transits.is_empty():
		_render_offset = _clock_offset - delay_sec
		return
	var latest: float = _transits.reduce(
			func(m: float, t: Transit) -> float: return minf(m, t.offset), INF)
	var target := latest - Protocol.SNAPSHOT_INTERVAL_SEC - MARGIN_SEC
	var step := minf(delta, MAX_STEP_SEC)
	if target < _render_offset:
		_render_offset = maxf(target, _render_offset - RISE * step)
	else:
		_render_offset = minf(target, _render_offset + FALL * step)


## How unevenly snapshots arrive: the smoothed difference in delay between
## one snapshot and the next. 0 for a perfectly steady link.
func jitter_ms() -> int:
	return roundi(_jitter * 1000.0)


## How far behind the newest snapshots the drawing is.
func delay_ms() -> int:
	return roundi((_clock_offset - _render_offset) * 1000.0)


## What to draw at [param now]; null before the first snapshot.
func view(now: float) -> Snapshot:
	if _snaps.is_empty():
		return null
	var render_time := now + _render_offset
	# Keep two to blend between.
	while _snaps.size() > 2 and time_of(_snaps[1]) <= render_time:
		_snaps.pop_front()
	var a := _snaps[0]
	if _snaps.size() == 1 or render_time <= time_of(a):
		return a
	var b := _snaps[1]
	var t := clampf(inverse_lerp(time_of(a), time_of(b), render_time), 0.0, 1.0)

	# Positions blend. Everything else comes from the nearer snapshot, all from
	# the same one so they agree.
	var blended := Snapshot.new()
	blended.match_ticks_left = (a if t < 0.5 else b).match_ticks_left
	blended.world_number = b.world_number
	for pb in b.players:
		var pa := a.find_player(pb.id)
		if not pa:
			pa = pb
		var p := (pa if t < 0.5 else pb).copy()
		p.pos = pa.pos.lerp(pb.pos, t)
		blended.players.append(p)
	for i in b.dummies.size():
		var db := b.dummies[i]
		var da := a.dummies[i] if i < a.dummies.size() else db
		var d := db.copy()
		d.pos = da.pos.lerp(db.pos, t)
		blended.dummies.append(d)
	return blended


## For a new connection: its clock and snapshots start over.
func reset() -> void:
	_snaps.clear()
	_transits.clear()
	_have_clock = false
	_jitter = 0.0


## When a snapshot arrived, and how far its server time was ahead of then.
class Transit:
	var arrival: float
	var offset: float

	func _init(at: float, ahead: float) -> void:
		arrival = at
		offset = ahead
