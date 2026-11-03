extends RefCounted
## The game simulation.
##
## Plain data with no nodes, so the server can step it headless.

## A 0-tick cooldown is skipped. A buffered press can wait in any phase.
enum Phase { READY, SWINGING, COOLDOWN }

## FREE: the dummy's own movement (the target dummy stands, others wander).
enum Motion { FREE, KNOCKED_BACK }

const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")
const Snapshot := preload("res://net/snapshot.gd")

const DT := 1.0 / Protocol.TICK_RATE
## Shorter inputs have no reliable direction, so they count as none. Real
## input is 0 or far longer.
const MOVE_DEAD_ZONE := 0.01
## Movement and facing snap to what four keys can make. Snapshots send facing
## as one of these.
const DIRECTIONS := 8
const DIRECTION_STEP := TAU / DIRECTIONS
## PLACEHOLDER (design): where the target dummy stands, from the arena's
## center.
const TARGET_DUMMY_OFFSET := Vector2(0, -80)

var tick := 0
var players: Dictionary[int, Player] = {}
var dummies: Array[Dummy] = []
var _rng := RandomNumberGenerator.new()


## Snaps a direction to the nearest of [constant DIRECTIONS].
static func snap_direction(v: Vector2) -> Vector2:
	if v.length() < MOVE_DEAD_ZONE:
		return Vector2.ZERO
	return Vector2.from_angle(snappedf(v.angle(), DIRECTION_STEP))


## The rect a hurtbox of [param size] covers, centered on [param pos].
static func hurtbox(pos: Vector2, size: Vector2) -> Rect2:
	return Rect2(pos - size / 2, size)


## Where a hurtbox's center can be with the whole box inside the arena.
static func walkable(size: Vector2) -> Rect2:
	return Tuning.arena.grow_individual(-size.x / 2, -size.y / 2, -size.x / 2, -size.y / 2)


static func _ticks_until_ready(p: Player) -> int:
	match p.phase:
		Phase.SWINGING:
			return p.phase_ticks + Tuning.swing_cooldown_ticks
		Phase.COOLDOWN:
			return p.phase_ticks
	return 0


## Whether the swing arc (a pie slice) touches [param box]: the box holds the
## center, its nearest point is inside the slice, or a straight edge of the
## slice crosses it.
static func _arc_touches(center: Vector2, facing: Vector2, box: Rect2) -> bool:
	if box.has_point(center):
		return true
	var nearest := center.clamp(box.position, box.end)
	if center.distance_to(nearest) > Tuning.swing_radius:
		return false
	if absf(facing.angle_to(nearest - center)) <= Tuning.swing_arc / 2:
		return true
	for side in [-1, 1]:
		var tip := center + facing.rotated(side * Tuning.swing_arc / 2) * Tuning.swing_radius
		if _segment_touches(center, tip, box):
			return true
	return false


static func _segment_touches(a: Vector2, b: Vector2, box: Rect2) -> bool:
	if box.has_point(a) or box.has_point(b):
		return true
	var corners := [
		box.position,
		Vector2(box.end.x, box.position.y),
		box.end,
		Vector2(box.position.x, box.end.y),
	]
	for i in corners.size():
		var next: Vector2 = corners[(i + 1) % corners.size()]
		if Geometry2D.segment_intersects_segment(a, b, corners[i], next) != null:
			return true
	return false


static func _clamp_dummy(d: Dummy, pos: Vector2) -> Vector2:
	var area := walkable(d.size)
	return pos.clamp(area.position, area.end)


func _init(rng_seed := 1) -> void:
	_rng.seed = rng_seed
	var area := walkable(Tuning.DUMMY_HURTBOX)
	for i in Tuning.DUMMY_COUNT:
		var d := Dummy.new()
		d.size = Tuning.DUMMY_HURTBOX
		d.pos = Vector2(
				_rng.randf_range(area.position.x, area.end.x),
				_rng.randf_range(area.position.y, area.end.y))
		dummies.append(d)

	var target := Dummy.new()
	target.target = true
	target.size = Tuning.target_dummy_hurtbox
	target.pos = Tuning.arena.get_center() + TARGET_DUMMY_OFFSET
	dummies.append(target)


func add_player(id: int) -> void:
	var p := Player.new()
	p.id = id
	# PLACEHOLDER (design): spawn positions, in a row with half a hurtbox
	# between players. IDs are seat numbers from 1, so each seat has its own
	# spot.
	var spacing := Tuning.player_hurtbox.x * 1.5
	p.pos = Tuning.arena.get_center() + Vector2(spacing * (id - 1), 0)
	players[id] = p


func remove_player(id: int) -> void:
	players.erase(id)


## A new connection counts its presses from scratch.
func set_connected(id: int, connected: bool) -> void:
	var p: Player = players.get(id)
	if p:
		p.connected = connected
		p.move = Vector2.ZERO
		p.attack_count = 0
		p.attacks_handled = 0
		p.attack_pending = false


func set_input(id: int, move: Vector2, attack_count: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.move = snap_direction(move)
		p.attack_count = maxi(p.attack_count, attack_count)


func step() -> void:
	tick += 1
	for d in dummies:
		_step_dummy(d)
	for p: Player in players.values():
		if _step_player(p):
			_resolve_swing(p)


func snapshot() -> Snapshot:
	var snap := Snapshot.new()
	snap.tick = tick
	for p: Player in players.values():
		var sp := Snapshot.Player.new()
		sp.id = p.id
		sp.pos = p.pos
		sp.facing = p.facing
		sp.swing_ticks = p.phase_ticks if p.phase == Phase.SWINGING else 0
		sp.connected = p.connected
		snap.players.append(sp)
	for d in dummies:
		var sd := Snapshot.Dummy.new()
		sd.pos = d.pos
		sd.hit = d.hit_ticks > 0
		sd.target = d.target
		snap.dummies.append(sd)
	return snap


## Facing is the last direction moved. The player is rooted (no moving or
## turning) during the swing, and during the cooldown if the balance says so.
## Returns whether a swing started, so [method step] can resolve its hits.
func _step_player(p: Player) -> bool:
	var rooted := (p.phase == Phase.SWINGING
			or p.phase == Phase.COOLDOWN and Tuning.swing_root_during_cooldown)
	if not rooted:
		if p.move != Vector2.ZERO:
			p.facing = p.move
		var area := walkable(Tuning.player_hurtbox)
		p.pos = (p.pos + p.move * Tuning.player_speed * DT).clamp(area.position, area.end)

	if p.phase != Phase.READY:
		p.phase_ticks -= 1
		if p.phase_ticks == 0:
			if p.phase == Phase.SWINGING and Tuning.swing_cooldown_ticks > 0:
				p.phase = Phase.COOLDOWN
				p.phase_ticks = Tuning.swing_cooldown_ticks
			else:
				p.phase = Phase.READY

	# A new press is remembered if the swing will be ready within the buffer.
	if p.attack_count > p.attacks_handled:
		p.attacks_handled = p.attack_count
		p.attack_pending = _ticks_until_ready(p) <= Tuning.swing_buffer_ticks
	if p.phase == Phase.READY and p.attack_pending:
		p.attack_pending = false
		p.phase = Phase.SWINGING
		p.phase_ticks = Tuning.swing_ticks
		return true
	return false


## Hits resolve once, when the swing starts: each dummy hit flashes and is
## pushed away from the attacker.
func _resolve_swing(p: Player) -> void:
	for d in dummies:
		if not _arc_touches(p.pos, p.facing, hurtbox(d.pos, d.size)):
			continue
		d.hit_ticks = Tuning.hit_flash_ticks
		# PLACEHOLDER (design): pushed straight away from the attacker.
		var away := d.pos - p.pos
		var dir := away.normalized() if not away.is_zero_approx() else p.facing
		if Tuning.knockback_ticks == 0:
			d.pos = _clamp_dummy(d, d.pos + dir * Tuning.knockback_px)
		else:
			d.motion = Motion.KNOCKED_BACK
			d.knock_step = dir * Tuning.knockback_px / Tuning.knockback_ticks
			d.knock_ticks = Tuning.knockback_ticks


func _step_dummy(d: Dummy) -> void:
	if d.hit_ticks > 0:
		d.hit_ticks -= 1
	if d.motion == Motion.KNOCKED_BACK:
		d.pos = _clamp_dummy(d, d.pos + d.knock_step)
		d.knock_ticks -= 1
		if d.knock_ticks == 0:
			d.motion = Motion.FREE
		return
	if d.target:
		return
	d.turn_ticks -= 1
	if d.turn_ticks <= 0:
		d.turn_ticks = Tuning.dummy_turn_ticks
		d.dir = Vector2.from_angle(_rng.randf() * TAU)
	d.pos += d.dir * Tuning.DUMMY_SPEED * DT
	var area := walkable(d.size)
	if not area.has_point(d.pos):
		d.dir = -d.dir
		d.pos = d.pos.clamp(area.position, area.end)


class Player:
	var id: int
	var pos: Vector2
	var facing := Vector2.RIGHT
	var move := Vector2.ZERO
	## Latest total from the client.
	var attack_count := 0
	var attacks_handled := 0
	## A buffered press.
	var attack_pending := false
	var phase := Phase.READY
	## Left in the phase; unused while READY.
	var phase_ticks := 0
	var connected := true


class Dummy:
	var pos: Vector2
	var dir: Vector2
	var size: Vector2
	## The target dummy, which never wanders.
	var target := false
	var turn_ticks := 0
	## Left in the hit flash.
	var hit_ticks := 0
	var motion := Motion.FREE
	## Px per tick while KNOCKED_BACK.
	var knock_step := Vector2.ZERO
	var knock_ticks := 0
