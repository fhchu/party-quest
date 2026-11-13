extends RefCounted
## The game simulation.
##
## Plain data with no nodes, so the server can step it headless.

const GameTime := preload("res://shared/game_time.gd")
const DataLoader := preload("res://shared/data_loader.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const RoomGraph := preload("res://shared/room_graph.gd")
const Snapshot := preload("res://net/snapshot.gd")
const World := preload("res://sim/world.gd")
const Body := preload("res://sim/body.gd")
const Actor := preload("res://sim/actor.gd")
const Player := preload("res://sim/player.gd")
const Dummy := preload("res://sim/dummy.gd")
const Projectile := preload("res://sim/projectile.gd")

## Whether the run in this world is over, and how.
enum Outcome {
	NONE,
	WON,
	LOST,
}

## [member time_up_tick] for a world with no time limit.
const NO_TIME_LIMIT := -1
## Straight pieces along the swing's curved edge: enough that it looks round,
## and within a fifth of a pixel of a true curve at its reach.
const ARC_SEGMENTS := 12

## The arena, from its top-left corner, in px.
static var arena: Rect2 = DataLoader.arena
## Centered on the player's position; used for walls and for being hit.
static var player_hurtbox: Vector2 = DataLoader.player_hurtbox
## Every dummy's.
static var dummy_hurtbox: Vector2 = DataLoader.dummy_hurtbox
## A player's health at the start of each world.
static var player_max_health: int = DataLoader.player_max_health
## How far a player walks each tick, in px.
static var walk_step: float = DataLoader.player_speed * GameTime.TICK_SEC
## Whether a player stays rooted through the swing's cooldown too.
static var root_during_cooldown: bool = DataLoader.swing_root_during_cooldown
## How long a swing's arc is active. The player is rooted meanwhile.
static var swing_ticks := GameTime.ticks(DataLoader.swing_active_sec)
## From the end of the arc to the next possible swing.
static var swing_cooldown_ticks := GameTime.ticks(DataLoader.swing_cooldown_sec)
## A press this close to idle is remembered and fires when idle.
static var swing_buffer_ticks := GameTime.ticks(DataLoader.swing_buffer_sec)
## After a player takes damage, how long no damage can hurt them.
static var hurt_invulnerable_ticks := GameTime.ticks(DataLoader.player_invulnerable_sec)
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
## Each kind's attributes, indexed by kind.
static var _dummy_stats: Array[DataLoader.DummyStats] = _load_dummy_stats()

var tick := 0
## One more than the world this one replaces, so clients jump to the new
## positions instead of sliding there.
var layout_number := 0
## Set when one of the world's run conditions is met. A town world has none.
var outcome := Outcome.NONE
## The tick its time runs out, set by [method limit_time].
var time_up_tick := NO_TIME_LIMIT
## A frozen world only counts its tick, so snapshots still count up and
## clients keep accepting them. Presses made meanwhile are spent, so none
## swings if it runs again.
var frozen := false
var players: Dictionary[int, Player] = {}
## The room the party is in.
var room := Room.new()
## The current room's.
var dummies: Array[Dummy]:
	get:
		return room.dummies
	set(value):
		room.dummies = value
var projectiles: Array[Projectile] = []
## Every dummy a swing touched during the last [method step], for the lobby
## to act on.
var swing_contacts: Array[SwingContact] = []

var _last_id := 0
## What bodies are pushed back out of in the current room; see
## [method _place_walls].
var _solids: Array[Solid] = []
## The run this world plays; null for none.
var _run: DataLoader.RunSetup
## Each takes this world and returns whether that condition is met.
var _win_checks: Array[Callable] = []
var _lose_checks: Array[Callable] = []
## The press totals of the world before, by player ID, until
## [method add_player] carries each one over.
var _carried_presses: Dictionary[int, int] = {}
## Every room the party has been in, by map name, as they left it.
var _rooms: Dictionary[String, Room] = {}


## The swing's pie slice around its attacker, pointing along +x: the shape
## that hits and the one drawn.
static func swing_arc_points() -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for i in ARC_SEGMENTS + 1:
		var t := float(i) / ARC_SEGMENTS
		var angle := lerpf(-swing_arc / 2, swing_arc / 2, t)
		points.append(Vector2.from_angle(angle) * swing_radius)
	return points


## A check for one of balance.json's run conditions: it takes the world and
## returns whether the condition is met. A time_up_sec condition also
## limits [param world]'s time. Empty for an unknown name.
static func run_condition_check(entry: DataLoader.ConditionEntry, world: World) -> Callable:
	match entry.name:
		"defeat_all":
			var kind := DataLoader.dummy_kind(entry.arg)
			return func(w: World) -> bool:
				return w.dummies.all(func(d: Dummy) -> bool: return d.kind != kind)
		"party_downed":
			return func(w: World) -> bool: return w.players_alive() == 0
		"clear_room":
			var room_name: String = entry.arg
			return func(w: World) -> bool: return w.is_room_cleared(room_name)
		"time_up_sec":
			world.limit_time(entry.arg)
			return func(w: World) -> bool: return w.is_time_up()
	return Callable()


## Straight away from [param from], or along [param fallback] when exactly
## on top of it.
static func _away(pos: Vector2, from: Vector2, fallback: Vector2) -> Vector2:
	var away := pos - from
	return away.normalized() if not away.is_zero_approx() else fallback


## Solid behind the side of [param rect] that [param normal] points away
## from; the normal points into the room.
static func _half_plane(normal: Vector2, rect: Rect2) -> Solid:
	var plane := WorldBoundaryShape2D.new()
	plane.normal = normal
	plane.distance = normal.dot(rect.get_center() - normal * rect.size / 2)
	var out := Solid.new()
	out.shape = plane
	return out


static func _box(rect: Rect2) -> Solid:
	var box := RectangleShape2D.new()
	box.size = rect.size
	var out := Solid.new()
	out.shape = box
	out.at = Transform2D(0.0, rect.get_center())
	return out


## Between players in a row, center to center: half a hurtbox apart.
static func _row_spacing() -> float:
	return player_hurtbox.x * 1.5


static func _load_dummy_stats() -> Array[DataLoader.DummyStats]:
	var out: Array[DataLoader.DummyStats] = []
	for kind in DataLoader.dummy_kind_count():
		out.append(DataLoader.dummy_stats(kind))
	return out


## Starts in [param map], or in an empty room. [param previous] is the world
## this one replaces: its tick and its players' presses carry over.
## [param run] gives the conditions that end it; with none it never ends.
func _init(map: DataLoader.Map = null, previous: World = null,
		run: DataLoader.RunSetup = null) -> void:
	_run = run
	if previous:
		# Clients drop snapshots whose tick goes backwards.
		tick = previous.tick
		layout_number = previous.layout_number + 1
		for id: int in previous.players:
			_carried_presses[id] = previous.players[id].attack_count
	if map:
		_build_room(map)
	_place_walls()
	if not run:
		return
	# After the tick carries over: a time limit counts from it.
	for entry in run.win:
		_win_checks.append(run_condition_check(entry, self))
	for entry in run.lose:
		_lose_checks.append(run_condition_check(entry, self))


func add_player(id: int, connected := true) -> void:
	var p := Player.new()
	p.id = id
	# PLACEHOLDER (design): spawn positions, in a row with half a hurtbox
	# between players. IDs are seat numbers from 1, so each seat has its own
	# spot.
	p.pos = arena.get_center() + Vector2(_row_spacing() * (id - 1), 0)
	p.size = player_hurtbox
	p.health = player_max_health
	p.walk_step = walk_step
	p.root_during_cooldown = root_during_cooldown
	p.swing_ticks = swing_ticks
	p.swing_cooldown_ticks = swing_cooldown_ticks
	p.swing_buffer_ticks = swing_buffer_ticks
	p.hurt_invulnerable_ticks = hurt_invulnerable_ticks
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
	if not p:
		return
	if frozen:
		p.discard_attacks(attack_count)
	else:
		p.set_input(move, attack_count)


func step() -> void:
	tick += 1
	swing_contacts.clear()
	if frozen:
		return
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
	_check_cleared()
	_check_doorways()
	_check_outcome()


## Moves the party into [param map]'s room: as they left it if they've been
## there, else as the map lays it out. Shots in flight are gone.
func enter_room(map: DataLoader.Map) -> void:
	if _rooms.has(map.name):
		room = _rooms[map.name]
	else:
		_build_room(map)
	projectiles.clear()
	layout_number += 1
	_place_walls()


func is_room_cleared(map_name: String) -> bool:
	return _rooms.has(map_name) and _rooms[map_name].cleared


## Its time runs out [param sec] from now. [method is_time_up] and the
## snapshot's timer follow it; a frozen world's tick still counts.
func limit_time(sec: float) -> void:
	time_up_tick = tick + GameTime.ticks(sec)


func is_time_up() -> bool:
	return time_up_tick != NO_TIME_LIMIT and tick >= time_up_tick


## The players not downed.
func players_alive() -> int:
	return players.values().filter(func(p: Player) -> bool: return not p.is_downed()).size()


func snapshot() -> Snapshot:
	var snap := Snapshot.new()
	snap.tick = tick
	snap.layout_number = layout_number
	snap.room_cleared = room.cleared
	var sides: Array[RoomGraph.Side] = []
	for door in room.doors:
		sides.append(door.side)
	snap.door_bits = RoomGraph.door_bits(sides)
	if time_up_tick != NO_TIME_LIMIT:
		snap.run_ticks_left = maxi(time_up_tick - tick, 0)
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


func _check_cleared() -> void:
	if room.cleared:
		return
	room.cleared = room.clear_checks.any(func(check: Callable) -> bool: return check.call(self))
	if room.cleared:
		_place_walls()


## The first living player whose center is past the face of an open door's
## wall takes the party through it.
func _check_doorways() -> void:
	if not room.cleared:
		return
	for door in room.doors:
		var gap := RoomShape.door(door.side)
		for p: Player in players.values():
			if not p.is_downed() and gap.has_point(p.pos):
				_go_through(door)
				return


## Moves the party into the room [param door] leads to, lined up just inside
## the door they arrive by, clear of its gap.
func _go_through(door: RoomGraph.Passage) -> void:
	enter_room(_run.rooms[door.to])
	var side := RoomGraph.opposite(door.side)
	var gap := RoomShape.door(side)
	var normal := RoomShape.inward(side)
	# PLACEHOLDER (design): a hurtbox in from the floor's edge, in seat order.
	var depth := absf(gap.size.dot(normal)) / 2 + absf(player_hurtbox.dot(normal))
	var front := gap.get_center() + normal * depth
	var ids := players.keys()
	ids.sort()
	for i in ids.size():
		var along := (i - (ids.size() - 1) / 2.0) * _row_spacing()
		players[ids[i]].pos = front + normal.orthogonal() * along


## Each wall is solid as far back as anything can be pushed: a half-plane
## along its inner face, or, while its door is open, along the arena's edge
## with the pieces either side of the gap reaching far behind it, so
## nothing gets stuck inside one.
func _place_walls() -> void:
	_solids.clear()
	for side: RoomGraph.Side in RoomGraph.Side.values():
		var normal := RoomShape.inward(side)
		if not (room.cleared and _has_door(side)):
			_solids.append(_half_plane(normal, RoomShape.floor_area()))
			continue
		_solids.append(_half_plane(normal, arena))
		for piece in RoomShape.wall(side, true):
			_solids.append(_box(piece.expand(piece.get_center() - normal * arena.size.length())))


func _has_door(side: RoomGraph.Side) -> bool:
	return room.doors.any(func(d: RoomGraph.Passage) -> bool: return d.side == side)


## Wins are checked first, so a kill on the timer's last tick still wins.
func _check_outcome() -> void:
	var met := func(check: Callable) -> bool: return check.call(self)
	if _win_checks.any(met):
		outcome = Outcome.WON
	elif _lose_checks.any(met):
		outcome = Outcome.LOST


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
	for solid in _solids:
		# Pairs of points: one on the body, then the matching one on the wall.
		var contacts := body.collider.collide_and_get_contacts(
				body.collider_transform(), solid.shape, solid.at)
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


## Makes [param map]'s room the current one, with its dummies placed.
func _build_room(map: DataLoader.Map) -> void:
	room = Room.new()
	_rooms[map.name] = room
	if _run:
		room.doors = RoomGraph.doors(_run.passages, map.name)
	for entry in map.clear_when:
		room.clear_checks.append(run_condition_check(entry, self))
	room.cleared = room.clear_checks.is_empty()
	for spot in map.dummies:
		_add_dummy(spot.kind, spot.offset, spot.on_hit)


## A dummy of [param kind] at [param offset] from the arena's center, with
## its kind's attributes from balance.json and [param on_hit] passed on.
func _add_dummy(kind: int, offset: Vector2, on_hit: String) -> Dummy:
	var stats := _dummy_stats[kind]
	var d := Dummy.new()
	d.id = _new_id()
	d.kind = kind
	d.on_hit = on_hit
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


## One room's state, kept while the party is elsewhere.
class Room:
	var dummies: Array[Dummy] = []
	## Its ways out, each seen from this room.
	var doors: Array[RoomGraph.Passage] = []
	## Set the first time any of its clear checks is met, and never unset.
	var cleared := false
	## Each takes the world and returns whether the room is cleared.
	var clear_checks: Array[Callable] = []


## A shape bodies can't overlap, placed at [member at].
class Solid:
	var shape: Shape2D
	var at := Transform2D.IDENTITY


## A swing touching a dummy.
class SwingContact:
	var attacker_id: int
	var on_hit: String
