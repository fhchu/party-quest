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
## PLACEHOLDER (design): READY and START stand in for buttons, and ENEMY
## for M3's enemies.
enum Kind {
	READY,
	START,
	ENEMY,
}

## Which dummies a fresh world gets.
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
# PLACEHOLDER (design): where the dummies are, from the arena's center.
const READY_DUMMY_OFFSET := Vector2(-100, -80)
const START_DUMMY_OFFSET := Vector2(100, -80)
const ENEMY_OFFSET := Vector2(0, -80)

var tick := 0
var players: Dictionary[int, Player] = {}
var dummies: Array[Dummy] = []
## Every dummy a swing touched during the last [method step], for the room
## to act on.
var swing_contacts: Array[SwingContact] = []


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


## [param pos] moved by [param offset], kept inside the arena for a hurtbox
## of [param size].
static func _moved_within_arena(pos: Vector2, offset: Vector2, size: Vector2) -> Vector2:
	var area := walkable(size)
	return (pos + offset).clamp(area.position, area.end)


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


## Treats every press up to [param attack_count] as already handled, so
## none of them swings: for presses made while input is ignored, and for a
## character carried into a fresh world.
func absorb_attacks(id: int, attack_count: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.attack_count = maxi(p.attack_count, attack_count)
		p.attacks_handled = p.attack_count
		p.attack_pending = false


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
	swing_contacts.clear()
	for d in dummies:
		_step_dummy(d)
	for p: Player in players.values():
		if p.invulnerable_ticks > 0:
			p.invulnerable_ticks -= 1
		if _step_player(p):
			_resolve_swing(p)
	dummies = dummies.filter(func(d: Dummy) -> bool: return not d.damageable or d.health > 0)
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
		sp.invulnerable = p.invulnerable_ticks > 0
		snap.players.append(sp)
	for d in dummies:
		var sd := Snapshot.Dummy.new()
		sd.pos = d.pos
		sd.flashing = d.flash_ticks > 0
		sd.kind = d.kind
		snap.dummies.append(sd)
	return snap


## Facing is the last direction moved. A pushed player is carried by the
## push and can't steer or start a swing. Otherwise the player is rooted (no
## moving or turning) during the swing, and during the cooldown if the
## balance says so. Returns whether a swing started, so [method step] can
## resolve what it touches.
func _step_player(p: Player) -> bool:
	var pushed := p.knockback.ticks > 0
	var rooted := (p.phase == Phase.SWINGING
			or p.phase == Phase.COOLDOWN and Tuning.swing_root_during_cooldown)
	if pushed:
		p.pos = _step_knockback(p.pos, Tuning.player_hurtbox, p.knockback)
	elif not rooted:
		if p.move != Vector2.ZERO:
			p.facing = p.move
		p.pos = _moved_within_arena(p.pos, p.move * Tuning.player_speed * DT, Tuning.player_hurtbox)

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
	if p.phase == Phase.READY and p.attack_pending and not pushed:
		p.attack_pending = false
		p.phase = Phase.SWINGING
		p.phase_ticks = Tuning.swing_ticks
		return true
	return false


## A swing acts once, when it starts: every dummy it touches flashes and is
## listed in [member swing_contacts]. A damageable dummy loses health, and
## one pushed by swings is knocked away from the attacker.
func _resolve_swing(p: Player) -> void:
	for d in dummies:
		if not _arc_touches(p.pos, p.facing, hurtbox(d.pos, d.size)):
			continue
		var contact := SwingContact.new()
		contact.attacker_id = p.id
		contact.dummy_kind = d.kind
		swing_contacts.append(contact)
		d.flash_ticks = Tuning.dummy_flash_ticks
		if d.damageable:
			d.health -= Tuning.swing_damage
		if d.pushed_by_swings:
			# PLACEHOLDER (design): straight away from the attacker.
			var push := _away(d.pos, p.pos, p.facing) * Tuning.knockback_px
			d.pos = _start_knockback(d.pos, d.size, d.knockback, push, Tuning.knockback_ticks)


func _step_dummy(d: Dummy) -> void:
	if d.flash_ticks > 0:
		d.flash_ticks -= 1
	if d.knockback.ticks > 0:
		d.pos = _step_knockback(d.pos, d.size, d.knockback)


## Each dummy with contact damage hurts every player touching it who isn't
## invulnerable, and pushes them straight away from itself.
func _contact_damage() -> void:
	for d in dummies:
		if d.contact_damage == 0:
			continue
		var box := hurtbox(d.pos, d.size)
		for p: Player in players.values():
			if not box.intersects(hurtbox(p.pos, Tuning.player_hurtbox)):
				continue
			if not _hurt(p, d.contact_damage):
				continue
			# PLACEHOLDER (design): to the right if exactly on top.
			var dir := _away(p.pos, d.pos, Vector2.RIGHT)
			_push_player(p, dir * d.contact_push_px, d.contact_push_ticks)


## Takes [param damage] from [param p] unless they're invulnerable, then
## makes them invulnerable for [member Tuning.player_invulnerable_ticks].
## Health stops at 0. Returns whether it hurt them.
func _hurt(p: Player, damage: int) -> bool:
	if p.invulnerable_ticks > 0:
		return false
	p.health = maxi(p.health - damage, 0)
	p.invulnerable_ticks = Tuning.player_invulnerable_ticks
	return true


## A push cancels the swing in progress; until it ends, the player can't
## steer or start another (see [method _step_player]).
func _push_player(p: Player, push: Vector2, ticks: int) -> void:
	if p.phase == Phase.SWINGING:
		p.phase = Phase.READY
		p.phase_ticks = 0
	p.pos = _start_knockback(p.pos, Tuning.player_hurtbox, p.knockback, push, ticks)


## Starts pushing something at [param pos] with a hurtbox of [param size] by
## [param push] (in px) over [param ticks]. 0 ticks moves it at once.
## Returns its position after this tick.
func _start_knockback(pos: Vector2, size: Vector2, knockback: Knockback, push: Vector2,
		ticks: int) -> Vector2:
	if ticks == 0:
		knockback.ticks = 0
		return _moved_within_arena(pos, push, size)
	knockback.step = push / ticks
	knockback.ticks = ticks
	return pos


## One tick of a push in progress. Returns the new position.
func _step_knockback(pos: Vector2, size: Vector2, knockback: Knockback) -> Vector2:
	knockback.ticks -= 1
	return _moved_within_arena(pos, knockback.step, size)


## A dummy of [param kind] at [param offset] from the arena's center, with
## its kind's attributes from balance.json.
func _add_dummy(kind: Kind, offset: Vector2) -> Dummy:
	var stats := Tuning.dummy_stats(Kind.keys()[kind].to_lower())
	var d := Dummy.new()
	d.kind = kind
	d.size = Tuning.dummy_hurtbox
	d.pos = Tuning.arena.get_center() + offset
	d.damageable = stats.health > 0
	d.health = stats.health
	d.pushed_by_swings = stats.pushed_by_swings
	d.contact_damage = stats.contact_damage
	d.contact_push_px = stats.contact_push_px
	d.contact_push_ticks = stats.contact_push_ticks
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
	## Left in which no damage can hurt them, after they were last hurt.
	var invulnerable_ticks := 0
	var knockback := Knockback.new()


## The defaults are an inert dummy; [method World._add_dummy] sets its
## kind's attributes.
class Dummy:
	var kind := Kind.READY
	var pos: Vector2
	var size: Vector2
	## Whether swings take health from it. A damageable dummy at 0 health is
	## removed.
	var damageable := false
	var health := 0
	var pushed_by_swings := false
	## Health a player loses touching it; 0 for none.
	var contact_damage := 0
	## How far touching it pushes a player away, in px, and over how long.
	var contact_push_px := 0.0
	var contact_push_ticks := 0
	## Left in the flash from being struck.
	var flash_ticks := 0
	var knockback := Knockback.new()


## A push in progress: px per tick, and ticks of it left (0 when not being
## pushed).
class Knockback:
	var step := Vector2.ZERO
	var ticks := 0


## A swing touching a dummy.
class SwingContact:
	var attacker_id: int
	var dummy_kind: Kind
