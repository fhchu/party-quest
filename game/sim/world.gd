extends RefCounted
## The game simulation.
##
## Plain data with no nodes, so the server can step it headless.

## A 0-tick cooldown is skipped. A buffered press can wait in any phase.
enum Phase {
	READY,
	SWINGING,
	COOLDOWN,
}

## FREE: the dummy's own movement (load-test dummies wander, the rest
## stand).
enum Motion {
	FREE,
	KNOCKED_BACK,
}

## LOAD: a wandering load-test prop. READY and START: the lobby's, hit to
## toggle ready and to start the match. ENEMY: the match's; it has health,
## hurts players who touch it, and killing every one wins.
## PLACEHOLDER (design): READY and START stand in for buttons, and ENEMY
## for M3's enemies.
enum Kind {
	LOAD,
	READY,
	START,
	ENEMY,
}

## Which standing dummies a fresh world gets.
enum Layout {
	LOBBY,
	MATCH,
}

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
# PLACEHOLDER (design): where the standing dummies are, from the arena's
# center. READY on the left, START on the right.
const READY_DUMMY_OFFSET := Vector2(-100, -80)
const START_DUMMY_OFFSET := Vector2(100, -80)
const ENEMY_OFFSET := Vector2(0, -80)

var tick := 0
var players: Dictionary[int, Player] = {}
var dummies: Array[Dummy] = []
## What swings hit during the last [method step], for the room to act on.
var hits: Array[Hit] = []
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


## Godot clips the segment to the box. A segment that only grazes the box,
## along an edge or across a corner by a fraction of a pixel, doesn't count.
static func _segment_touches(a: Vector2, b: Vector2, box: Rect2) -> bool:
	var corners := PackedVector2Array([
		box.position,
		Vector2(box.end.x, box.position.y),
		box.end,
		Vector2(box.position.x, box.end.y),
	])
	var inside := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), corners)
	return not inside.is_empty()


static func _clamp_dummy(d: Dummy, pos: Vector2) -> Vector2:
	var area := walkable(d.size)
	return pos.clamp(area.position, area.end)


## [param load_dummies] adds the wandering load-test dummies.
func _init(rng_seed := 1, load_dummies := false, layout := Layout.LOBBY) -> void:
	_rng.seed = rng_seed
	if load_dummies:
		var area := walkable(Tuning.DUMMY_HURTBOX)
		for i in Tuning.DUMMY_COUNT:
			var d := Dummy.new()
			d.kind = Kind.LOAD
			d.size = Tuning.DUMMY_HURTBOX
			d.pos = Vector2(
					_rng.randf_range(area.position.x, area.end.x),
					_rng.randf_range(area.position.y, area.end.y))
			dummies.append(d)

	match layout:
		Layout.LOBBY:
			_add_standing(Kind.READY, READY_DUMMY_OFFSET)
			_add_standing(Kind.START, START_DUMMY_OFFSET)
		Layout.MATCH:
			_add_standing(Kind.ENEMY, ENEMY_OFFSET).health = Tuning.enemy_health


func add_player(id: int) -> void:
	var p := Player.new()
	p.id = id
	# PLACEHOLDER (design): spawn positions, in a row with half a hurtbox
	# between players. IDs are seat numbers from 1, so each seat has its own
	# spot.
	var spacing := Tuning.player_hurtbox.x * 1.5
	p.pos = Tuning.arena.get_center() + Vector2(spacing * (id - 1), 0)
	p.health = Tuning.player_max_health
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
	hits.clear()
	for d in dummies:
		_step_dummy(d)
	for p: Player in players.values():
		if p.hit_ticks > 0:
			p.hit_ticks -= 1
		if _step_player(p):
			_resolve_swing(p)
	dummies = dummies.filter(func(d: Dummy) -> bool: return d.kind != Kind.ENEMY or d.health > 0)
	_contact_damage()


## The enemies still standing.
func enemies_left() -> int:
	return dummies.filter(func(d: Dummy) -> bool: return d.kind == Kind.ENEMY).size()


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
		sp.health = p.health
		sp.hit = p.hit_ticks > 0
		snap.players.append(sp)
	for d in dummies:
		var sd := Snapshot.Dummy.new()
		sd.pos = d.pos
		sd.hit = d.hit_ticks > 0
		sd.kind = d.kind
		snap.dummies.append(sd)
	return snap


## Facing is the last direction moved. The player is rooted (no moving or
## turning) during the swing, and during the cooldown if the balance says so.
## Returns whether a swing started, so [method step] can resolve its hits.
func _step_player(p: Player) -> bool:
	var rooted := (p.phase == Phase.SWINGING
			or p.phase == Phase.COOLDOWN and Tuning.swing_root_during_cooldown)
	if p.knock_ticks > 0:
		# Pushed: the push replaces the player's own movement meanwhile.
		var area := walkable(Tuning.player_hurtbox)
		p.pos = (p.pos + p.knock_step).clamp(area.position, area.end)
		p.knock_ticks -= 1
	elif not rooted:
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
## listed in [member hits]. An enemy loses health. All but the lobby's
## READY and START are pushed away from the attacker; those stay put, so
## they're always where players expect them.
func _resolve_swing(p: Player) -> void:
	for d in dummies:
		if not _arc_touches(p.pos, p.facing, hurtbox(d.pos, d.size)):
			continue
		var hit := Hit.new()
		hit.player_id = p.id
		hit.kind = d.kind
		hits.append(hit)
		if d.kind == Kind.ENEMY:
			d.health -= Tuning.swing_damage
		d.hit_ticks = Tuning.hit_flash_ticks
		if d.kind == Kind.READY or d.kind == Kind.START:
			continue
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
	if d.kind != Kind.LOAD:
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


## Each enemy hurts each player touching it and pushes them straight away
## from itself, then waits [member Tuning.contact_repeat_ticks] before
## hurting that player again.
func _contact_damage() -> void:
	for d in dummies:
		if d.kind != Kind.ENEMY:
			continue
		for id: int in d.contact_wait.keys():
			d.contact_wait[id] -= 1
			if d.contact_wait[id] <= 0:
				d.contact_wait.erase(id)
		var box := hurtbox(d.pos, d.size)
		for p: Player in players.values():
			if p.id in d.contact_wait or not box.intersects(hurtbox(p.pos, Tuning.player_hurtbox)):
				continue
			p.health = maxi(p.health - Tuning.contact_damage, 0)
			p.hit_ticks = Tuning.hit_flash_ticks
			d.contact_wait[p.id] = Tuning.contact_repeat_ticks
			_push_player(p, p.pos - d.pos)


## PLACEHOLDER (design): straight away from what hurt them (to the right
## if exactly on top), over [member Tuning.contact_knockback_ticks].
func _push_player(p: Player, away: Vector2) -> void:
	var dir := away.normalized() if not away.is_zero_approx() else Vector2.RIGHT
	var push := dir * Tuning.contact_knockback_px
	if Tuning.contact_knockback_ticks == 0:
		var area := walkable(Tuning.player_hurtbox)
		p.pos = (p.pos + push).clamp(area.position, area.end)
		return
	p.knock_step = push / Tuning.contact_knockback_ticks
	p.knock_ticks = Tuning.contact_knockback_ticks


func _add_standing(kind: Kind, offset: Vector2) -> Dummy:
	var d := Dummy.new()
	d.kind = kind
	d.size = Tuning.dummy_hurtbox
	d.pos = Tuning.arena.get_center() + offset
	dummies.append(d)
	return d


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
	var health := 0
	## Left in the hit flash.
	var hit_ticks := 0
	## Px per tick while being pushed, and ticks of it left.
	var knock_step := Vector2.ZERO
	var knock_ticks := 0


class Dummy:
	var kind := Kind.LOAD
	var pos: Vector2
	var dir: Vector2
	var size: Vector2
	## Only an ENEMY's counts; it's removed at 0.
	var health := 0
	## Ticks until it may hurt each player again, by player ID.
	var contact_wait: Dictionary[int, int] = {}
	var turn_ticks := 0
	## Left in the hit flash.
	var hit_ticks := 0
	var motion := Motion.FREE
	## Px per tick while KNOCKED_BACK.
	var knock_step := Vector2.ZERO
	var knock_ticks := 0


## A swing touching a dummy.
class Hit:
	var player_id: int
	var kind: Kind
