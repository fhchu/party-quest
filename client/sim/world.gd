extends RefCounted
## The game simulation. Plain data with no nodes, so the server can step it
## headless and the client can later reuse it for prediction.

const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")

var tick := 0
var players := {}  # id -> Player
var dummies: Array[Dummy] = []
var _rng := RandomNumberGenerator.new()


## Movement is 8-directional; analog input snaps to the nearest direction.
static func snap8(v: Vector2) -> Vector2:
	if v.length() < 0.01:
		return Vector2.ZERO
	return Vector2.from_angle(snappedf(v.angle(), PI / 4))


func _init(rng_seed := 1) -> void:
	_rng.seed = rng_seed
	for i in Tuning.DUMMY_COUNT:
		var d := Dummy.new()
		d.pos = Vector2(
			_rng.randf_range(Tuning.ARENA.position.x, Tuning.ARENA.end.x),
			_rng.randf_range(Tuning.ARENA.position.y, Tuning.ARENA.end.y))
		dummies.append(d)


func add_player(id: int) -> void:
	var p := Player.new()
	p.id = id
	# PLACEHOLDER (design): spawn positions.
	p.pos = Tuning.ARENA.get_center() + Vector2(24 * players.size(), 0)
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


## Facing is the last direction moved. PLACEHOLDER (design): you can move and
## turn at full speed while swinging.
func _step_player(p: Player, dt: float) -> void:
	if p.move != Vector2.ZERO:
		p.facing = p.move
	p.pos = (p.pos + p.move * Tuning.PLAYER_SPEED * dt).clamp(Tuning.ARENA.position, Tuning.ARENA.end)

	if p.swing_ticks > 0:
		p.swing_ticks -= 1
		if p.swing_ticks == 0:
			p.cooldown_ticks = Tuning.SWING_COOLDOWN_TICKS
	elif p.cooldown_ticks > 0:
		p.cooldown_ticks -= 1

	if p.attack_count > p.attacks_handled:
		p.attacks_handled = p.attack_count
		if p.swing_ticks == 0 and p.cooldown_ticks == 0:
			p.swing_ticks = Tuning.SWING_TICKS
			_resolve_swing(p)


## Hits are resolved once, when the swing starts.
func _resolve_swing(p: Player) -> void:
	for d in dummies:
		var to := d.pos - p.pos
		if to.length() <= Tuning.SWING_RADIUS and absf(p.facing.angle_to(to)) <= Tuning.SWING_ARC / 2:
			d.hit_ticks = Tuning.HIT_FLASH_TICKS


func _step_dummy(d: Dummy, dt: float) -> void:
	if d.hit_ticks > 0:
		d.hit_ticks -= 1
	d.turn_ticks -= 1
	if d.turn_ticks <= 0:
		d.turn_ticks = Tuning.DUMMY_TURN_TICKS
		d.dir = Vector2.from_angle(_rng.randf() * TAU)
	d.pos += d.dir * Tuning.DUMMY_SPEED * dt
	if not Tuning.ARENA.has_point(d.pos):
		d.dir = -d.dir
		d.pos = d.pos.clamp(Tuning.ARENA.position, Tuning.ARENA.end)


func snapshot() -> Array:
	var ps := []
	for p: Player in players.values():
		ps.append([p.id, p.pos, p.facing, p.swing_ticks, p.connected])
	var ds := []
	for d in dummies:
		ds.append([d.pos, d.hit_ticks > 0])
	return [tick, ps, ds]


class Player:
	var id: int
	var pos: Vector2
	var facing := Vector2.RIGHT
	var move := Vector2.ZERO
	var attack_count := 0  # latest total reported by the client
	var attacks_handled := 0
	var swing_ticks := 0
	var cooldown_ticks := 0
	var connected := true


class Dummy:
	var pos: Vector2
	var dir: Vector2
	var turn_ticks := 0
	var hit_ticks := 0
