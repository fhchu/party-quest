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

## What a dummy is for. READY and START: the lobby's, hit to toggle ready
## and to start the match. ENEMY: the match's; killing every one wins. How a
## dummy behaves (health, pushed by swings, contact damage) is in its
## attributes, from balance.json.
## PLACEHOLDER (design): READY and START are placeholders for buttons.
enum Kind {
	READY,
	START,
	ENEMY,
}

## What a swing touching a dummy asks the room to do.
enum OnHit {
	NOTHING,
	TOGGLE_READY,
	START_MATCH,
}

## Which dummies a fresh world gets.
enum Layout {
	LOBBY,
	MATCH,
}

const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Player := preload("res://sim/player.gd")
const Dummy := preload("res://sim/dummy.gd")
const Projectile := preload("res://sim/projectile.gd")

const DT := 1.0 / Protocol.TICK_RATE
## Shorter inputs have no reliable direction, so they count as none. Real
## input is 0 or far longer.
const MOVE_DEAD_ZONE := 0.01
## Movement and facing snap to what four keys can make. Snapshots send facing
## as one of these.
const DIRECTIONS := 8
const DIRECTION_STEP := TAU / DIRECTIONS
## Straight pieces along the swing's curved edge: enough that it looks round,
## and within a fifth of a pixel of a true curve at its reach.
const ARC_SEGMENTS := 12
# PLACEHOLDER (design): where the dummies are, from the arena's center.
const READY_DUMMY_OFFSET := Vector2(-100, -80)
const START_DUMMY_OFFSET := Vector2(100, -80)
const ENEMY_OFFSET := Vector2(0, -80)
## Each kind's [member Dummy.on_hit].
const ON_HIT: Dictionary[Kind, OnHit] = {
	Kind.READY: OnHit.TOGGLE_READY,
	Kind.START: OnHit.START_MATCH,
	Kind.ENEMY: OnHit.NOTHING,
}

var tick := 0
var players: Dictionary[int, Player] = {}
var dummies: Array[Dummy] = []
var projectiles: Array[Projectile] = []
## Every dummy a swing touched during the last [method step], for the room
## to act on.
var swing_contacts: Array[SwingContact] = []

var _last_id := 0


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


## The swing's pie slice around its attacker, pointing along +x: the shape
## that hits and the one drawn.
static func swing_arc_points() -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for i in ARC_SEGMENTS + 1:
		var t := float(i) / ARC_SEGMENTS
		var angle := lerpf(-Tuning.swing_arc / 2, Tuning.swing_arc / 2, t)
		points.append(Vector2.from_angle(angle) * Tuning.swing_radius)
	return points


## Straight away from [param from], or along [param fallback] when exactly
## on top of it.
static func _away(pos: Vector2, from: Vector2, fallback: Vector2) -> Vector2:
	var away := pos - from
	return away.normalized() if not away.is_zero_approx() else fallback


func _init(layout := Layout.LOBBY) -> void:
	match layout:
		Layout.LOBBY:
			_add_dummy(Kind.READY, READY_DUMMY_OFFSET)
			_add_dummy(Kind.START, START_DUMMY_OFFSET)
		Layout.MATCH:
			_add_dummy(Kind.ENEMY, ENEMY_OFFSET)


func add_player(id: int) -> void:
	var p := Player.new()
	p.id = id
	# PLACEHOLDER (design): spawn positions, in a row with half a hurtbox
	# between players. IDs are seat numbers from 1, so each seat has its own
	# spot.
	var spacing := Tuning.player_hurtbox.x * 1.5
	p.pos = Tuning.arena.get_center() + Vector2(spacing * (id - 1), 0)
	p.size = Tuning.player_hurtbox
	p.health = Tuning.player_max_health
	players[id] = p


func remove_player(id: int) -> void:
	players.erase(id)


## Gives player [param from] the ID [param to], which must be free. The
## character stays where it is.
func renumber_player(from: int, to: int) -> void:
	var p: Player = players.get(from)
	if p:
		players.erase(from)
		p.id = to
		players[to] = p


## Throws away every press up to [param attack_count] unswung: for presses
## made while input is ignored, and for a character carried into a fresh
## world.
func discard_attacks(id: int, attack_count: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.discard_attacks(attack_count)


## A new connection counts its presses from scratch.
func set_connected(id: int, connected: bool) -> void:
	var p: Player = players.get(id)
	if p:
		p.connected = connected
		p.reset_presses()


func set_input(id: int, move: Vector2, attack_count: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.set_input(move, attack_count)


func step() -> void:
	tick += 1
	swing_contacts.clear()
	for d in dummies:
		if d.step(_nearest_living_player(d.pos)):
			_fire(d)
	for p: Player in players.values():
		if p.step():
			_resolve_swing(p)
	_step_projectiles()
	dummies = dummies.filter(func(d: Dummy) -> bool: return not d.is_destroyed())
	_contact_damage()


## Advances the tick and nothing else: the world holds still, and snapshots
## still count up, so clients keep accepting them.
func count_tick() -> void:
	tick += 1
	swing_contacts.clear()


## The players not downed.
func players_alive() -> int:
	return players.values().filter(func(p: Player) -> bool: return not p.is_downed()).size()


## The enemies left alive.
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
		sp.invulnerable_ticks = p.invulnerable_ticks
		snap.players.append(sp)
	for d in dummies:
		var sd := Snapshot.Dummy.new()
		sd.id = d.id
		sd.pos = d.pos
		sd.facing = d.facing
		sd.ticks_since_struck = mini(tick - d.struck_tick, Snapshot.STRUCK_LONG_AGO)
		sd.kind = d.kind
		snap.dummies.append(sd)
	for s in projectiles:
		var ss := Snapshot.Projectile.new()
		ss.id = s.id
		ss.pos = s.pos
		ss.radius = s.radius
		snap.projectiles.append(ss)
	return snap


## A swing acts once, when it starts: every dummy it touches takes the hit
## (see [method Dummy.take_hit]) and is listed in [member swing_contacts].
func _resolve_swing(p: Player) -> void:
	var arc := ConvexPolygonShape2D.new()
	arc.points = swing_arc_points()
	var arc_at := Transform2D(p.facing.angle(), p.pos)
	for d in dummies:
		if not d.touches(arc, arc_at):
			continue
		var contact := SwingContact.new()
		contact.attacker_id = p.id
		contact.on_hit = d.on_hit
		swing_contacts.append(contact)
		# PLACEHOLDER (design): straight away from the attacker.
		var push := _away(d.pos, p.pos, p.facing) * Tuning.knockback_px
		d.take_hit(Tuning.swing_damage, push, Tuning.knockback_ticks, tick)


## A shot from [param d] toward its locked aim, pushing like touching it.
func _fire(d: Dummy) -> void:
	var s := Projectile.new()
	s.id = _new_id()
	s.pos = d.pos
	s.velocity = _away(d.aim_spot, d.pos, d.facing) * d.projectile_speed
	s.radius = d.projectile_radius
	s.damage = d.projectile_damage
	s.push_px = d.contact_push_px
	s.push_ticks = d.contact_push_ticks
	projectiles.append(s)


## Moves every shot. One touching a living player hurts them (unless
## they're invulnerable) and pushes them straight away from it; it's gone
## either way, as is one touching a wall. Shots pass through dummies and
## downed players.
func _step_projectiles() -> void:
	var flying: Array[Projectile] = []
	for s in projectiles:
		s.step()
		var struck := _living_player_touching(s)
		if struck:
			if struck.take_damage(s.damage):
				# PLACEHOLDER (design): to the right if exactly on top.
				struck.push(_away(struck.pos, s.pos, Vector2.RIGHT) * s.push_px, s.push_ticks)
		elif not s.is_at_wall(Tuning.arena):
			flying.append(s)
	projectiles = flying


## Null if no living player touches [param s].
func _living_player_touching(s: Projectile) -> Player:
	for p: Player in players.values():
		if not p.is_downed() and s.touches(p):
			return p
	return null


func _new_id() -> int:
	_last_id += 1
	return _last_id


## Each dummy with contact damage hurts every player touching it who isn't
## invulnerable, and pushes them straight away from itself.
func _contact_damage() -> void:
	for d in dummies:
		if d.contact_damage == 0:
			continue
		for p: Player in players.values():
			if not d.touches_actor(p) or not p.take_damage(d.contact_damage):
				continue
			# PLACEHOLDER (design): to the right if exactly on top.
			var dir := _away(p.pos, d.pos, Vector2.RIGHT)
			p.push(dir * d.contact_push_px, d.contact_push_ticks)


## The living player nearest [param pos], ties going to the lower seat;
## null if nobody is alive. Dropped players count.
func _nearest_living_player(pos: Vector2) -> Player:
	var nearest: Player = null
	var ids := players.keys()
	ids.sort()
	for id: int in ids:
		var p := players[id]
		if p.is_downed():
			continue
		if not nearest or pos.distance_to(p.pos) < pos.distance_to(nearest.pos):
			nearest = p
	return nearest


## A dummy of [param kind] at [param offset] from the arena's center, with
## its kind's attributes from balance.json.
func _add_dummy(kind: Kind, offset: Vector2) -> Dummy:
	var stats := Tuning.dummy_stats(Kind.keys()[kind].to_lower())
	var d := Dummy.new()
	d.id = _new_id()
	d.kind = kind
	d.on_hit = ON_HIT[kind]
	d.size = Tuning.dummy_hurtbox
	d.pos = Tuning.arena.get_center() + offset
	d.damageable = stats.health > 0
	d.health = stats.health
	d.pushed_by_swings = stats.pushed_by_swings
	d.contact_damage = stats.contact_damage
	d.contact_push_px = stats.contact_push_px
	d.contact_push_ticks = stats.contact_push_ticks
	d.fire_interval_ticks = stats.fire_interval_ticks
	d.fire_ticks_left = stats.fire_interval_ticks
	d.aim_lock_ticks = stats.aim_lock_ticks
	d.turn_rate = stats.turn_rate
	d.projectile_radius = stats.projectile_radius
	d.projectile_speed = stats.projectile_speed
	d.projectile_damage = stats.projectile_damage
	dummies.append(d)
	return d


## A swing touching a dummy.
class SwingContact:
	var attacker_id: int
	var on_hit: OnHit
