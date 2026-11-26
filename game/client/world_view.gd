extends RefCounted
## The world as the client draws it: one snapshot as it arrived, or two
## blended by the Interpolator. ClientState makes one from each snapshot, so
## nothing past it depends on the wire format.

## [member run_ticks_left] when there's no timer to show.
const NO_TIMER := -1
## [member Dummy.ticks_since_struck] for a dummy not struck in a long while:
## far longer than any flash.
const LONG_AGO := 1 << 20

var tick := 0
## Left on the run's timer; [constant NO_TIMER] outside a run or for a run
## without one.
var run_ticks_left := NO_TIMER
## A new number means positions jump instead of sliding there: a new world,
## or the party entered another room.
var layout_number := 0
## The walls of the party's room that have doors, one bit per wall.
var door_bits := 0
## Whether the party's room is cleared, which opens its doors.
var room_cleared := false
## Seeds how the party's room's floor is drawn.
var graphics_seed := 0
var players: Array[Player] = []
var dummies: Array[Dummy] = []
var projectiles: Array[Projectile] = []


## Null if no player has [param id].
func find_player(id: int) -> Player:
	for p in players:
		if p.id == id:
			return p
	return null


## Null if no dummy has [param id].
func find_dummy(id: int) -> Dummy:
	for d in dummies:
		if d.id == id:
			return d
	return null


## Null if no projectile has [param id].
func find_projectile(id: int) -> Projectile:
	for s in projectiles:
		if s.id == id:
			return s
	return null


class Player:
	## The seat number.
	var id := 0
	var pos := Vector2.ZERO
	var facing := Vector2.RIGHT
	## For each item slot, ticks since its action became active, counting the
	## first as 1; 0 while idle or empty.
	var slot_ticks := PackedByteArray()
	var connected := true
	var health := 0
	## Can't be hurt for now: they were hurt a moment ago.
	var invulnerable := false

	## At 0 health: out of the fight until the run ends.
	func is_downed() -> bool:
		return health == 0

	func copy() -> Player:
		var p := Player.new()
		p.id = id
		p.pos = pos
		p.facing = facing
		p.slot_ticks = slot_ticks.duplicate()
		p.connected = connected
		p.health = health
		p.invulnerable = invulnerable
		return p


class Dummy:
	## Unique within its world.
	var id := 0
	var pos := Vector2.ZERO
	var facing := Vector2.DOWN
	## Ticks from a swing last touching it to the moment drawn. Negative in a
	## blended view when the hit comes after that moment.
	var ticks_since_struck := LONG_AGO
	## Its number among the dummy kinds (ClientLoader.dummy_looks).
	var kind := 0
	## While its aim is locked for a charge, the ticks until it charges;
	## else 0. Fractional in a blended view.
	var charge_windup_ticks_left := 0.0

	func copy() -> Dummy:
		var d := Dummy.new()
		d.id = id
		d.pos = pos
		d.facing = facing
		d.ticks_since_struck = ticks_since_struck
		d.charge_windup_ticks_left = charge_windup_ticks_left
		d.kind = kind
		return d


class Projectile:
	## Unique within its world, among dummies and projectiles both.
	var id := 0
	var pos := Vector2.ZERO
	## In px.
	var radius := 0.0

	func copy() -> Projectile:
		var s := Projectile.new()
		s.id = id
		s.pos = pos
		s.radius = radius
		return s
