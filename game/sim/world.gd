extends RefCounted
## The game simulation.
##
## Plain data with no nodes, so the server can step it headless.

## Which dummies a fresh world gets.
enum Layout {
	TOWN,
	RUN,
}

const GameTime := preload("res://shared/game_time.gd")
const DataLoader := preload("res://shared/data_loader.gd")
const Snapshot := preload("res://net/snapshot.gd")
const World := preload("res://sim/world.gd")
const Body := preload("res://sim/body.gd")
const Actor := preload("res://sim/actor.gd")
const Player := preload("res://sim/player.gd")
const Dummy := preload("res://sim/dummy.gd")
const Projectile := preload("res://sim/projectile.gd")

## Straight pieces along the swing's curved edge: enough that it looks round,
## and within a fifth of a pixel of a true curve at its reach.
const ARC_SEGMENTS := 12
# PLACEHOLDER (design): where the dummies are, from the arena's center.
const READY_DUMMY_OFFSET := Vector2(-100, -80)
const START_DUMMY_OFFSET := Vector2(100, -80)
const ENEMY_OFFSET := Vector2(0, -80)

## The arena, from its top-left corner, in px.
static var arena: Rect2 = DataLoader.arena
## Centered on the player's position; used for walls and for being hit.
static var player_hurtbox: Vector2 = DataLoader.player_hurtbox
## Every dummy's.
static var dummy_hurtbox: Vector2 = DataLoader.dummy_hurtbox
## A player's health at the start of each world.
static var player_max_health: int = DataLoader.player_max_health
## In px.
static var swing_radius: float = DataLoader.swing_radius
## Width of the arc in radians, centered on facing.
static var swing_arc: float = DataLoader.swing_arc
## How far a hit pushes its target, in px.
static var knockback_px: float = DataLoader.knockback_px
## How long the knockback push lasts; 0 moves the target at once.
static var knockback_ticks := GameTime.ticks(DataLoader.knockback_sec)
## Health a swing deals to a damageable dummy.
static var swing_damage: int = DataLoader.swing_damage
# The kinds the simulation places itself, by their names in balance.json's
# dummy_kinds. Ready and start are town's, hit to toggle ready and to start
# the run; enemies are the run's, and killing every one wins. How a dummy
# behaves comes from its attributes, not its kind.
# PLACEHOLDER (design): ready and start are placeholders for buttons.
static var ready_kind := DataLoader.dummy_kind("ready")
static var start_kind := DataLoader.dummy_kind("start")
static var enemy_kind := DataLoader.dummy_kind("enemy")
## Each kind's [member Dummy.on_hit]; any other kind's is NOTHING.
static var _on_hit: Dictionary[int, Dummy.OnHit] = {
	ready_kind: Dummy.OnHit.TOGGLE_READY,
	start_kind: Dummy.OnHit.START_RUN,
}
## Each kind's attributes, indexed by kind.
static var _dummy_stats: Array[DataLoader.DummyStats] = _load_dummy_stats()

var tick := 0
var players: Dictionary[int, Player] = {}
var dummies: Array[Dummy] = []
var projectiles: Array[Projectile] = []
## Every dummy a swing touched during the last [method step], for the lobby
## to act on.
var swing_contacts: Array[SwingContact] = []

var _last_id := 0
## The solid half-planes around the arena. A body is pushed back out of any
## it overlaps.
var _walls: Array[WorldBoundaryShape2D] = _arena_walls()
## The press totals of the world before, by player ID, until
## [method add_player] carries each one over.
var _carried_presses: Dictionary[int, int] = {}


## The swing's pie slice around its attacker, pointing along +x: the shape
## that hits and the one drawn.
static func swing_arc_points() -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for i in ARC_SEGMENTS + 1:
		var t := float(i) / ARC_SEGMENTS
		var angle := lerpf(-swing_arc / 2, swing_arc / 2, t)
		points.append(Vector2.from_angle(angle) * swing_radius)
	return points


## Straight away from [param from], or along [param fallback] when exactly
## on top of it.
static func _away(pos: Vector2, from: Vector2, fallback: Vector2) -> Vector2:
	var away := pos - from
	return away.normalized() if not away.is_zero_approx() else fallback


static func _arena_walls() -> Array[WorldBoundaryShape2D]:
	var out: Array[WorldBoundaryShape2D] = [
		_wall(Vector2.RIGHT, arena.position.x),
		_wall(Vector2.LEFT, -arena.end.x),
		_wall(Vector2.DOWN, arena.position.y),
		_wall(Vector2.UP, -arena.end.y),
	]
	return out


## Solid behind the line [code]normal.dot(p) == distance[/code]; the normal
## points into the arena.
static func _wall(normal: Vector2, distance: float) -> WorldBoundaryShape2D:
	var wall := WorldBoundaryShape2D.new()
	wall.normal = normal
	wall.distance = distance
	return wall


static func _load_dummy_stats() -> Array[DataLoader.DummyStats]:
	var out: Array[DataLoader.DummyStats] = []
	for kind in DataLoader.dummy_kind_count():
		out.append(DataLoader.dummy_stats(kind))
	return out


## [param previous] is the world this one replaces: its tick and its
## players' presses carry over.
func _init(layout := Layout.TOWN, previous: World = null) -> void:
	if previous:
		# Clients drop snapshots whose tick goes backwards.
		tick = previous.tick
		for id: int in previous.players:
			_carried_presses[id] = previous.players[id].attack_count
	match layout:
		Layout.TOWN:
			_add_dummy(ready_kind, READY_DUMMY_OFFSET)
			_add_dummy(start_kind, START_DUMMY_OFFSET)
		Layout.RUN:
			_add_dummy(enemy_kind, ENEMY_OFFSET)


func add_player(id: int, connected := true) -> void:
	var p := Player.new()
	p.id = id
	# PLACEHOLDER (design): spawn positions, in a row with half a hurtbox
	# between players. IDs are seat numbers from 1, so each seat has its own
	# spot.
	var spacing := player_hurtbox.x * 1.5
	p.pos = arena.get_center() + Vector2(spacing * (id - 1), 0)
	p.size = player_hurtbox
	p.health = player_max_health
	p.connected = connected
	# The client keeps counting presses across worlds; without this the press
	# that hit START would swing again in the run.
	p.discard_attacks(_carried_presses.get(id, 0))
	_carried_presses.erase(id)
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
## made while input is ignored.
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


## It stops moving until its next input.
func stop_player(id: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.move = Vector2.ZERO


func set_input(id: int, move: Vector2, attack_count: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.set_input(move, attack_count)


func step() -> void:
	tick += 1
	swing_contacts.clear()
	# Each offset is read before the step counts its push down, and applied
	# after, so a dummy's turn that swings a corner into a wall is caught too.
	for d in dummies:
		var offset := d.offset_this_tick()
		var fires := d.step(_nearest_living_player(d.pos))
		_move(d, offset)
		if fires:
			_fire(d)
	for p: Player in players.values():
		var offset := p.offset_this_tick()
		var swung := p.step()
		_move(p, offset)
		if swung:
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
	return dummies.filter(func(d: Dummy) -> bool: return d.kind == enemy_kind).size()


func snapshot() -> Snapshot:
	var snap := Snapshot.new()
	snap.tick = tick
	for p: Player in players.values():
		var sp := Snapshot.Player.new()
		sp.id = p.id
		sp.pos = p.pos
		sp.facing = p.facing
		sp.swing_ticks = p.state_ticks if p.state == Player.State.SWINGING else 0
		sp.connected = p.connected
		sp.health = p.health
		sp.invulnerable = p.invulnerable_ticks > 0
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
		d.take_hit(swing_damage, tick)
		if d.pushed_by_swings:
			_push(d, _away(d.pos, p.pos, p.facing) * knockback_px, knockback_ticks)


## A shot from [param d] toward its locked aim, pushing like touching it.
func _fire(d: Dummy) -> void:
	var s := Projectile.new()
	s.id = _new_id()
	s.pos = d.pos
	s.step = _away(d.aim_spot, d.pos, d.facing) * d.projectile_speed * GameTime.TICK_SEC
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
		var at_wall := _move(s, s.offset_this_tick())
		var struck := _living_player_touching(s)
		if struck:
			if struck.take_damage(s.damage):
				# PLACEHOLDER (design): to the right if exactly on top.
				var dir := _away(struck.pos, s.pos, Vector2.RIGHT)
				_push(struck, dir * s.push_px, s.push_ticks)
		elif not at_wall:
			flying.append(s)
	projectiles = flying


## Null if no living player touches [param s].
func _living_player_touching(s: Projectile) -> Player:
	for p: Player in players.values():
		if not p.is_downed() and s.touches_body(p):
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
			if not d.touches_body(p) or not p.take_damage(d.contact_damage):
				continue
			# PLACEHOLDER (design): to the right if exactly on top.
			var dir := _away(p.pos, d.pos, Vector2.RIGHT)
			_push(p, dir * d.contact_push_px, d.contact_push_ticks)


## Moves [param body] by [param offset], then pushes it back out of every
## wall it overlaps, so it slides along them. Returns whether a wall
## stopped it.
func _move(body: Body, offset: Vector2) -> bool:
	body.pos += offset
	var stopped := false
	for wall in _walls:
		# Pairs of points: one on the body, then the matching one on the wall.
		var contacts := body.collider.collide_and_get_contacts(
				body.collider_transform(), wall, Transform2D.IDENTITY)
		var deepest := Vector2.ZERO
		for i in range(0, contacts.size(), 2):
			var out := contacts[i + 1] - contacts[i]
			if out.length_squared() > deepest.length_squared():
				deepest = out
		if not contacts.is_empty():
			body.pos += deepest
			stopped = true
	return stopped


## Starts a push on [param actor]; a 0-tick push moves it at once.
func _push(actor: Actor, offset: Vector2, ticks: int) -> void:
	if actor.push(offset, ticks) and ticks == 0:
		_move(actor, offset)


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
func _add_dummy(kind: int, offset: Vector2) -> Dummy:
	var stats := _dummy_stats[kind]
	var d := Dummy.new()
	d.id = _new_id()
	d.kind = kind
	d.on_hit = _on_hit.get(kind, Dummy.OnHit.NOTHING)
	d.size = dummy_hurtbox
	d.pos = arena.get_center() + offset
	d.damageable = stats.health > 0
	d.health = stats.health
	d.pushed_by_swings = stats.pushed_by_swings
	d.contact_damage = stats.contact_damage
	d.contact_push_px = stats.contact_push_px
	d.contact_push_ticks = GameTime.ticks(stats.contact_push_sec)
	d.fire_interval_ticks = GameTime.ticks(stats.fire_interval_sec)
	d.fire_ticks_left = d.fire_interval_ticks
	d.aim_lock_ticks = GameTime.ticks(stats.aim_lock_sec)
	d.turn_step = stats.turn_rate * GameTime.TICK_SEC
	d.projectile_radius = stats.projectile_radius
	d.projectile_speed = stats.projectile_speed
	d.projectile_damage = stats.projectile_damage
	dummies.append(d)
	return d


## A swing touching a dummy.
class SwingContact:
	var attacker_id: int
	var on_hit: Dummy.OnHit
