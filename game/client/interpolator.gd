extends RefCounted
## Decides how far in the past to draw, and blends two snapshots for that
## moment. Nothing is predicted: everything, your own player included, is
## drawn between snapshots that have already arrived.

const GameTime := preload("res://shared/game_time.gd")
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
## One long frame (a hidden tab, a stall) mustn't move the delay all at
## once. This is a few normal frames.
const MAX_STEP_SEC := 0.1
## A gap between frames this long means the game loop stalled, as in a hidden
## tab. Snapshots handed over after it may have waited in a queue, so their
## arrival times say nothing about the link. Untuned.
const STALL_SEC := 0.25
## The most the drawing lags the newest snapshots when adapting. Past it, a
## worse link shows as freezes instead of more delay.
const MAX_DELAY_SEC := 0.25
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
## When [method update] last ran, to spot a stalled game loop.
var _last_update_at := -INF
## The smoothed change in transit time from one snapshot to the next, in
## seconds: how unevenly snapshots arrive.
var _jitter := 0.0


static func time_of(snap: Snapshot) -> float:
	return GameTime.seconds(snap.tick)


## [param a] and [param b] blended [param t] of the way from a to b, drawn
## at [param tick]. Positions blend. Everything else comes from the nearer
## snapshot, all from the same one so they agree.
static func _blend(a: Snapshot, b: Snapshot, t: float, tick: int) -> Snapshot:
	var blended := Snapshot.new()
	blended.tick = tick
	blended.run_ticks_left = (a if t < 0.5 else b).run_ticks_left
	blended.world_number = b.world_number
	for pb in b.players:
		var pa := a.find_player(pb.id)
		if not pa:
			pa = pb
		var p := (pa if t < 0.5 else pb).copy()
		p.pos = pa.pos.lerp(pb.pos, t)
		blended.players.append(p)
	for db in b.dummies:
		var da := a.find_dummy(db.id)
		if not da:
			da = db
		var d := db.copy()
		d.pos = da.pos.lerp(db.pos, t)
		d.facing = Vector2.from_angle(lerp_angle(da.facing.angle(), db.facing.angle(), t))
		# Ages count to the view's tick, so a flash lines up with what's drawn.
		d.ticks_since_struck += blended.tick - b.tick
		blended.dummies.append(d)
	for sb in b.projectiles:
		var sa := a.find_projectile(sb.id)
		var s := sb.copy()
		if sa:
			s.pos = sa.pos.lerp(sb.pos, t)
		blended.projectiles.append(s)
	return blended


## Returns false for a snapshot no newer than one already held. The first
## snapshot of a new world replaces the old world's, so nothing from it
## (a swing, a flash) is drawn after the world moves on. A snapshot handed
## over after a stall is drawn but doesn't size the delay or the clock.
func add(snap: Snapshot, now: float) -> bool:
	if not _snaps.is_empty() and snap.tick <= _snaps[-1].tick:
		return false
	if not _snaps.is_empty() and snap.world_number != _snaps[-1].world_number:
		_snaps.clear()
	_snaps.append(snap)
	if _have_clock and now - _last_update_at > STALL_SEC:
		return true
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
## or slows down a little, and never exceeds [constant MAX_DELAY_SEC].
func update(now: float, delta: float) -> void:
	_last_update_at = now
	while not _transits.is_empty() and _transits[0].arrival < now - TRANSIT_WINDOW_SEC:
		_transits.pop_front()
	if not _have_clock:
		return
	if fixed:
		_render_offset = _clock_offset - delay_sec
		return
	# Nothing timed lately, as after a hidden tab: keep the delay it had.
	if _transits.is_empty():
		return
	var latest: float = _transits.reduce(
			func(m: float, t: Transit) -> float: return minf(m, t.offset), INF)
	var target := latest - Protocol.SNAPSHOT_INTERVAL_SEC - MARGIN_SEC
	var step := minf(delta, MAX_STEP_SEC)
	if target < _render_offset:
		_render_offset = maxf(target, _render_offset - RISE * step)
	else:
		_render_offset = minf(target, _render_offset + FALL * step)
	_render_offset = maxf(_render_offset, _clock_offset - MAX_DELAY_SEC)


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
	return _blend(a, b, t, floori(render_time * GameTime.TICK_RATE))


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
