extends RefCounted
## The game simulation.
##
## Plain data with no nodes, so the server can step it headless and the client
## can reuse it for prediction.

const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")

var tick := 0
var players: Dictionary[int, Player] = {}
var dummies: Array[Dummy] = []
var _rng := RandomNumberGenerator.new()


## Snaps a direction to the nearest of 8.
static func snap8(v: Vector2) -> Vector2:
	if v.length() < 0.01:
		return Vector2.ZERO
	return Vector2.from_angle(snappedf(v.angle(), PI / 4))


## The rect a hurtbox of [param size] covers, centered on [param pos].
static func hurtbox(pos: Vector2, size: Vector2) -> Rect2:
	return Rect2(pos - size / 2, size)


## Where a hurtbox's center can be with the whole box inside the arena.
static func walkable(size: Vector2) -> Rect2:
	return Tuning.arena.grow_individual(-size.x / 2, -size.y / 2, -size.x / 2, -size.y / 2)


static func _ticks_until_ready(p: Player) -> int:
	if p.swing_ticks > 0:
		return p.swing_ticks + Tuning.swing_cooldown_ticks
	return p.cooldown_ticks


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
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false


func _init(rng_seed := 1) -> void:
	_rng.seed = rng_seed
	var area := walkable(Tuning.DUMMY_HURTBOX)
	for i in Tuning.DUMMY_COUNT:
		var d := Dummy.new()
		d.pos = Vector2(
				_rng.randf_range(area.position.x, area.end.x),
				_rng.randf_range(area.position.y, area.end.y))
		dummies.append(d)


func add_player(id: int) -> void:
	var p := Player.new()
	p.id = id
	# PLACEHOLDER (design): spawn positions.
	p.pos = Tuning.arena.get_center() + Vector2(24 * players.size(), 0)
	players[id] = p


func remove_player(id: int) -> void:
	players.erase(id)


func set_connected(id: int, connected: bool) -> void:
	var p: Player = players.get(id)
	if p:
		p.connected = connected
		p.move = Vector2.ZERO


func set_input(id: int, move: Vector2, attack_count: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.move = snap8(move)
		p.attack_count = maxi(p.attack_count, attack_count)


func step() -> void:
	var dt := 1.0 / Protocol.TICK_RATE
	tick += 1
	for d in dummies:
		_step_dummy(d, dt)
	for p: Player in players.values():
		_step_player(p, dt)


func snapshot() -> Array:
	var ps := []
	for p: Player in players.values():
		ps.append([p.id, p.pos, p.facing, p.swing_ticks, p.connected])
	var ds := []
	for d in dummies:
		ds.append([d.pos, d.hit_ticks > 0])
	return [tick, ps, ds]


## Facing is the last direction moved. The player is rooted (no moving or
## turning) during the swing, and during the cooldown if the balance says so.
func _step_player(p: Player, dt: float) -> void:
	var rooted := p.swing_ticks > 0 or (Tuning.swing_root_during_cooldown and p.cooldown_ticks > 0)
	if not rooted:
		if p.move != Vector2.ZERO:
			p.facing = p.move
		var area := walkable(Tuning.player_hurtbox)
		p.pos = (p.pos + p.move * Tuning.player_speed * dt).clamp(area.position, area.end)

	if p.swing_ticks > 0:
		p.swing_ticks -= 1
		if p.swing_ticks == 0:
			p.cooldown_ticks = Tuning.swing_cooldown_ticks
	elif p.cooldown_ticks > 0:
		p.cooldown_ticks -= 1

	# A new press is remembered if the swing will be ready within the buffer.
	if p.attack_count > p.attacks_handled:
		p.attacks_handled = p.attack_count
		p.attack_pending = _ticks_until_ready(p) <= Tuning.swing_buffer_ticks
	var ready := p.swing_ticks == 0 and p.cooldown_ticks == 0
	if ready and p.attack_pending:
		p.attack_pending = false
		p.swing_ticks = Tuning.swing_ticks
		_resolve_swing(p)


## Hits resolve once, when the swing starts.
func _resolve_swing(p: Player) -> void:
	for d in dummies:
		if _arc_touches(p.pos, p.facing, hurtbox(d.pos, Tuning.DUMMY_HURTBOX)):
			d.hit_ticks = Tuning.hit_flash_ticks


func _step_dummy(d: Dummy, dt: float) -> void:
	if d.hit_ticks > 0:
		d.hit_ticks -= 1
	d.turn_ticks -= 1
	if d.turn_ticks <= 0:
		d.turn_ticks = Tuning.dummy_turn_ticks
		d.dir = Vector2.from_angle(_rng.randf() * TAU)
	d.pos += d.dir * Tuning.DUMMY_SPEED * dt
	var area := walkable(Tuning.DUMMY_HURTBOX)
	if not area.has_point(d.pos):
		d.dir = -d.dir
		d.pos = d.pos.clamp(area.position, area.end)


class Player:
	var id: int
	var pos: Vector2
	var facing := Vector2.RIGHT
	var move := Vector2.ZERO
	var attack_count := 0  # Latest total from the client.
	var attacks_handled := 0
	var attack_pending := false  # A buffered press.
	var swing_ticks := 0
	var cooldown_ticks := 0
	var connected := true


class Dummy:
	var pos: Vector2
	var dir: Vector2
	var turn_ticks := 0
	var hit_ticks := 0
