extends RefCounted
## One tick of the world as clients see it. The server makes it from the
## World; snapshot_codec.gd packs it to fit one datagram.

## How many bits [member door_bits] may use: a wall each. Must hold
## shared/room_shape.gd's Side; tests/net/snapshot_codec_test.gd checks.
const DOOR_BIT_COUNT := 4
## The most a dummy's [member Dummy.ticks_since_struck] says: the largest
## value of its u8 field in snapshot_codec.gd. Anything older, or never, reads
## as this.
const STRUCK_LONG_AGO := 0xff
## [member run_ticks_left] when there's no timer to show: the largest value
## of its u16 field in snapshot_codec.gd, since 0 means time is up.
const NO_TIMER := 0xffff

var tick := 0
## Left on the run's timer; [constant NO_TIMER] outside a run or for a run
## without one.
var run_ticks_left := NO_TIMER
## Which layout it's from (World.layout_number). A new number means positions
## jump instead of sliding there: a new world, or the party entered another
## room.
var layout_number := 0
## The walls of the party's room that have doors, one bit per wall as
## shared/room_shape.gd's [code]door_bits()[/code] packs them.
var door_bits := 0
## Whether the party's room is cleared, which opens its doors.
var room_cleared := false
var players: Array[Player] = []
var dummies: Array[Dummy] = []
var projectiles: Array[Projectile] = []
## How many bytes it arrived in; 0 if it wasn't unpacked from the wire.
var packed_size := 0


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
	## Left in the swing; 0 when not swinging.
	var swing_ticks := 0
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
		p.swing_ticks = swing_ticks
		p.connected = connected
		p.health = health
		p.invulnerable = invulnerable
		return p


class Dummy:
	## Unique within its world.
	var id := 0
	var pos := Vector2.ZERO
	var facing := Vector2.DOWN
	## Ticks from a swing last touching it to the snapshot's tick, at most
	## [constant STRUCK_LONG_AGO]. Negative in a blended view when the hit
	## comes after the moment drawn.
	var ticks_since_struck := STRUCK_LONG_AGO
	## Its number in shared/data/dummy_kinds.tres.
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
